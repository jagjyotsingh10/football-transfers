/* =====================================================================
   Football Transfer ROI  |  Step 5: squad portfolio model and reporting views
   ---------------------------------------------------------------------
   Treats each club's squad as an asset portfolio: players are the assets,
   Transfermarkt market values are their prices. Run after step 3.
   Re-runnable: drops and rebuilds its tables, recreates its views.

   How a squad is built at a snapshot date:
     - Snapshots are 30 June, 2020 to 2026: the end of each season and the
       financial year-end for most clubs. 30 June 2020 is the opening
       position; 30 June 2021 closes 2020/21, and so on to 2025/26.
     - A player's value is his latest valuation in the 12 months up to the
       snapshot. Players with no valuation in that year are left out.
     - His club is whichever came last: the club on that valuation, or the
       club he moved to in his latest transfer. Valuations only come every
       few months, so on their own they lag behind transfers.
     - Loanees count for the club they are at; the source can't tell a loan
       from a free transfer, so ownership can't be separated from squad.
     - The portfolio is the club's 25 most valuable players (value_rank_in_club
       <= 25), like a 25-man registered squad. The source stopped valuing
       most reserve and youth players in 2024 (about 7,400 players at top 5
       clubs valued in 2023, 3,800 in 2024), so counting everyone would make
       squads look like they halved. The top 25 hold 96-98% of squad value in
       every year and are covered consistently.

   Reporting views (schema rpt) are the layer Power BI connects to.
   ===================================================================== */

USE FootballTransferROI;
GO

IF SCHEMA_ID('rpt') IS NULL EXEC('CREATE SCHEMA rpt');
GO

DROP TABLE IF EXISTS dw.fact_portfolio_snapshot;
DROP TABLE IF EXISTS dw.dim_snapshot;
GO

/* ---------- dim_snapshot: each 30 June (season end), plus each 1 September (season start) ----------
   Season-end snapshots drive Q1-Q10. Season-start snapshots (squad after the
   summer window, valued before a ball is kicked) drive Q11, so points are
   compared with value the club had going in, not value earned by winning. */
CREATE TABLE dw.dim_snapshot (
    snapshot_date      DATE        NOT NULL CONSTRAINT PK_dim_snapshot PRIMARY KEY,
    snapshot_year      SMALLINT    NOT NULL,
    snapshot_type      VARCHAR(12) NOT NULL CONSTRAINT CK_snapshot_type CHECK (snapshot_type IN ('Season end', 'Season start')),
    season_start_year  SMALLINT    NOT NULL,  -- season it closes (end) or opens (start)
    season_label       CHAR(7)     NOT NULL
);

WITH years AS (
    SELECT CAST(2020 AS SMALLINT) AS y
    UNION ALL
    SELECT CAST(y + 1 AS SMALLINT) FROM years WHERE y < 2026
)
INSERT INTO dw.dim_snapshot (snapshot_date, snapshot_year, snapshot_type, season_start_year, season_label)
SELECT DATEFROMPARTS(y, 6, 30), y, 'Season end', y - 1, CONCAT(y - 1, '/', RIGHT(CAST(y AS VARCHAR(4)), 2))
FROM years
UNION ALL
SELECT DATEFROMPARTS(y, 9, 1), y, 'Season start', y, CONCAT(y, '/', RIGHT(CAST(y + 1 AS VARCHAR(4)), 2))
FROM years
WHERE y <= 2025;
GO

/* ---------- fact_portfolio_snapshot: one row per player per snapshot ---------- */
CREATE TABLE dw.fact_portfolio_snapshot (
    snapshot_date          DATE          NOT NULL CONSTRAINT FK_portfolio_snapshot REFERENCES dw.dim_snapshot (snapshot_date),
    player_id              INT           NOT NULL CONSTRAINT FK_portfolio_player   REFERENCES dw.dim_player (player_id),
    club_id                INT           NOT NULL CONSTRAINT FK_portfolio_club     REFERENCES dw.dim_club (club_id),
    market_value_eur       DECIMAL(18,2) NOT NULL,
    valuation_date         DATE          NOT NULL,
    value_year_before_eur  DECIMAL(18,2) NULL,  -- latest value 12 to 24 months before the snapshot
    age_years              DECIMAL(4,1)  NULL,
    value_rank_in_club     SMALLINT      NOT NULL,  -- 1 = most valuable; portfolio = rank <= 25
    CONSTRAINT PK_fact_portfolio_snapshot PRIMARY KEY (snapshot_date, player_id)
);

WITH latest_valuation AS (
    SELECT s.snapshot_date, v.player_id, v.market_value_eur, v.valuation_date, v.club_id,
           ROW_NUMBER() OVER (PARTITION BY s.snapshot_date, v.player_id ORDER BY v.valuation_date DESC) AS rn
    FROM dw.dim_snapshot s
    JOIN dw.fact_player_valuation v
      ON v.valuation_date <= s.snapshot_date
     AND v.valuation_date >  DATEADD(YEAR, -1, s.snapshot_date)
),
latest_move AS (
    SELECT s.snapshot_date, t.player_id, t.to_club_id, t.transfer_date,
           ROW_NUMBER() OVER (PARTITION BY s.snapshot_date, t.player_id
                              ORDER BY t.transfer_date DESC, t.transfer_key DESC) AS rn
    FROM dw.dim_snapshot s
    JOIN dw.fact_transfer t ON t.transfer_date <= s.snapshot_date
),
year_before AS (
    SELECT s.snapshot_date, v.player_id, v.market_value_eur,
           ROW_NUMBER() OVER (PARTITION BY s.snapshot_date, v.player_id ORDER BY v.valuation_date DESC) AS rn
    FROM dw.dim_snapshot s
    JOIN dw.fact_player_valuation v
      ON v.valuation_date <= DATEADD(YEAR, -1, s.snapshot_date)
     AND v.valuation_date >  DATEADD(YEAR, -2, s.snapshot_date)
),
assigned AS (
    SELECT lv.snapshot_date, lv.player_id, lv.market_value_eur, lv.valuation_date,
           CASE WHEN lm.transfer_date >= lv.valuation_date THEN lm.to_club_id ELSE lv.club_id END AS club_id
    FROM latest_valuation lv
    LEFT JOIN latest_move lm ON lm.snapshot_date = lv.snapshot_date AND lm.player_id = lv.player_id AND lm.rn = 1
    WHERE lv.rn = 1
)
INSERT INTO dw.fact_portfolio_snapshot
SELECT a.snapshot_date, a.player_id, a.club_id, a.market_value_eur, a.valuation_date,
       yb.market_value_eur,
       CAST(DATEDIFF(DAY, p.date_of_birth, a.snapshot_date) / 365.25 AS DECIMAL(4,1)),
       ROW_NUMBER() OVER (PARTITION BY a.club_id, a.snapshot_date ORDER BY a.market_value_eur DESC, a.player_id)
FROM assigned a
JOIN dw.dim_club   c ON c.club_id   = a.club_id      -- only clubs that played in the top 5
JOIN dw.dim_player p ON p.player_id = a.player_id
LEFT JOIN year_before yb ON yb.snapshot_date = a.snapshot_date AND yb.player_id = a.player_id AND yb.rn = 1
WHERE a.market_value_eur > 0;
GO

CREATE INDEX IX_portfolio_club ON dw.fact_portfolio_snapshot (club_id, snapshot_date)
    INCLUDE (market_value_eur, value_year_before_eur, age_years, value_rank_in_club);
GO

/* ---------- the portfolio: each club's 25 most valuable players ---------- */
CREATE OR ALTER VIEW rpt.vw_portfolio_player AS
SELECT ps.snapshot_date, ps.club_id, ps.player_id, p.player_name, p.position,
       ps.market_value_eur, ps.valuation_date, ps.value_year_before_eur, ps.age_years, ps.value_rank_in_club
FROM dw.fact_portfolio_snapshot ps
JOIN dw.dim_player p ON p.player_id = ps.player_id
WHERE ps.value_rank_in_club <= 25;
GO

/* =====================================================================
   REPORTING VIEWS
   ===================================================================== */

/* ---------- club-seasons in scope (club played in a top 5 league that season) ---------- */
CREATE OR ALTER VIEW rpt.vw_club_season AS
SELECT DISTINCT m.competition_id, m.season_start_year, cm.club_id
FROM dw.fact_club_match cm
JOIN dw.fact_match m ON m.game_id = cm.game_id;
GO

/* ---------- which portfolios to report at each snapshot ----------
   30 Jun 2021-2026: clubs that played the season it closes.
   30 Jun 2020 (opening): clubs that played 2020/21, as their starting point. */
CREATE OR ALTER VIEW rpt.vw_snapshot_scope AS
SELECT s.snapshot_date, s.snapshot_year, s.season_label AS closes_season_label,
       cs.club_id, cs.competition_id, cs.season_start_year,
       CAST(CASE WHEN s.snapshot_year = 2020 THEN 1 ELSE 0 END AS BIT) AS is_opening
FROM dw.dim_snapshot s
JOIN rpt.vw_club_season cs
  ON cs.season_start_year = CASE WHEN s.snapshot_year = 2020 THEN 2020 ELSE s.snapshot_year - 1 END
WHERE s.snapshot_type = 'Season end';
GO

/* ---------- Q1, Q2, Q4, Q6, Q10: one row per club per snapshot ---------- */
CREATE OR ALTER VIEW rpt.vw_club_portfolio AS
WITH totals AS (
    SELECT club_id, snapshot_date,
           COUNT(*)                                                     AS squad_size,
           SUM(market_value_eur)                                        AS total_value_eur,
           SUM(CASE WHEN value_rank_in_club <= 5 THEN market_value_eur END) AS top5_value_eur,
           AVG(age_years)                                               AS avg_age,
           SUM(market_value_eur * age_years) / NULLIF(SUM(CASE WHEN age_years IS NOT NULL THEN market_value_eur END), 0)
                                                                        AS value_weighted_age,
           SUM(CASE WHEN value_year_before_eur IS NOT NULL THEN market_value_eur END)          AS value_with_history_eur,
           SUM(CASE WHEN market_value_eur < value_year_before_eur THEN market_value_eur END)   AS declining_value_eur,
           SUM(CASE WHEN market_value_eur < value_year_before_eur
                    THEN value_year_before_eur - market_value_eur END)                         AS value_lost_eur,
           SUM(CASE WHEN market_value_eur < value_year_before_eur THEN 1 ELSE 0 END)           AS declining_players
    FROM rpt.vw_portfolio_player
    WHERE snapshot_date IN (SELECT snapshot_date FROM dw.dim_snapshot WHERE snapshot_type = 'Season end')
    GROUP BY club_id, snapshot_date
),
with_prev AS (
    SELECT t.*,
           LAG(total_value_eur) OVER (PARTITION BY club_id ORDER BY snapshot_date) AS prev_total_value_eur,
           LAG(snapshot_date)   OVER (PARTITION BY club_id ORDER BY snapshot_date) AS prev_snapshot_date
    FROM totals t
)
SELECT sc.snapshot_date,
       sc.snapshot_year,
       sc.closes_season_label,
       sc.is_opening,
       sc.competition_id,
       comp.competition_name,
       sc.club_id,
       c.club_name,
       w.squad_size,
       CAST(CASE WHEN w.squad_size < 20 THEN 1 ELSE 0 END AS BIT)                    AS is_thin_squad,  -- under 20 valued players
       w.total_value_eur,
       CAST(w.total_value_eur / w.squad_size AS DECIMAL(18,2))                       AS avg_value_eur,
       w.top5_value_eur,
       CAST(100.0 * w.top5_value_eur / w.total_value_eur AS DECIMAL(5,1))            AS top5_share_pct,
       CASE WHEN w.prev_snapshot_date = DATEADD(YEAR, -1, w.snapshot_date)
            THEN w.total_value_eur - w.prev_total_value_eur END                      AS value_change_eur,
       CASE WHEN w.prev_snapshot_date = DATEADD(YEAR, -1, w.snapshot_date)
            THEN CAST(100.0 * (w.total_value_eur - w.prev_total_value_eur) / w.prev_total_value_eur AS DECIMAL(7,1)) END
                                                                                     AS value_change_pct,
       w.declining_players,
       w.value_with_history_eur,  -- value of players who also had a value a year earlier
       w.declining_value_eur,
       w.value_lost_eur,
       CAST(100.0 * w.declining_value_eur / NULLIF(w.value_with_history_eur, 0) AS DECIMAL(5,1)) AS declining_exposure_pct,
       CAST(w.avg_age AS DECIMAL(4,1))                                               AS avg_age,
       CAST(w.value_weighted_age AS DECIMAL(4,1))                                    AS value_weighted_age,
       RANK() OVER (PARTITION BY sc.competition_id, sc.snapshot_date ORDER BY w.total_value_eur DESC) AS value_rank_in_league,
       CAST(100.0 * (w.total_value_eur / w.squad_size)
            / (SUM(w.total_value_eur) OVER (PARTITION BY sc.competition_id, sc.snapshot_date)
               / SUM(w.squad_size)    OVER (PARTITION BY sc.competition_id, sc.snapshot_date)) AS DECIMAL(6,1))
                                                                                     AS avg_value_index_league,  -- 100 = league average
       CAST(100.0 * (w.total_value_eur / w.squad_size)
            / (SUM(w.total_value_eur) OVER (PARTITION BY sc.snapshot_date)
               / SUM(w.squad_size)    OVER (PARTITION BY sc.snapshot_date)) AS DECIMAL(6,1))
                                                                                     AS avg_value_index_top5     -- 100 = top 5 average
FROM rpt.vw_snapshot_scope sc
JOIN with_prev w           ON w.club_id = sc.club_id AND w.snapshot_date = sc.snapshot_date
JOIN dw.dim_club c         ON c.club_id = sc.club_id
JOIN dw.dim_competition comp ON comp.competition_id = sc.competition_id;
GO

/* ---------- Q5, Q6: portfolio composition, long format for Power BI ---------- */
CREATE OR ALTER VIEW rpt.vw_portfolio_composition AS
WITH tagged AS (
    SELECT snapshot_date, club_id, market_value_eur,
           COALESCE(NULLIF(position, N'Missing'), N'Unknown') AS position,
           CASE WHEN age_years IS NULL THEN N'Unknown'
                WHEN age_years < 21 THEN N'Under 21'
                WHEN age_years < 25 THEN N'21-24'
                WHEN age_years < 29 THEN N'25-28'
                ELSE N'29+' END AS age_band
    FROM rpt.vw_portfolio_player
),
unpivoted AS (
    SELECT snapshot_date, club_id, N'Position' AS dimension, position AS category, market_value_eur FROM tagged
    UNION ALL
    SELECT snapshot_date, club_id, N'Age band', age_band, market_value_eur FROM tagged
)
SELECT sc.snapshot_date, sc.closes_season_label, sc.competition_id, sc.club_id, c.club_name,
       u.dimension, u.category,
       COUNT(*)                AS players,
       SUM(u.market_value_eur) AS value_eur,
       CAST(100.0 * SUM(u.market_value_eur)
            / SUM(SUM(u.market_value_eur)) OVER (PARTITION BY sc.snapshot_date, sc.club_id, u.dimension) AS DECIMAL(5,1)) AS value_share_pct
FROM unpivoted u
JOIN rpt.vw_snapshot_scope sc ON sc.club_id = u.club_id AND sc.snapshot_date = u.snapshot_date
JOIN dw.dim_club c            ON c.club_id = u.club_id
GROUP BY sc.snapshot_date, sc.closes_season_label, sc.competition_id, sc.club_id, c.club_name, u.dimension, u.category;
GO

/* ---------- Q5: club benchmark at the latest snapshot (30 Jun 2026, clubs in 2025/26) ---------- */
CREATE OR ALTER VIEW rpt.vw_club_kpis AS
WITH latest AS (
    SELECT * FROM rpt.vw_club_portfolio WHERE snapshot_year = 2026
),
opening AS (   -- 30 Jun 2020 portfolio, only for clubs in the top 5 in 2020/21:
               -- a promoted club's lower-league value is too small a base for growth rates
    SELECT club_id, total_value_eur
    FROM rpt.vw_club_portfolio
    WHERE snapshot_year = 2020
),
position_mix AS (
    SELECT club_id,
           SUM(CASE WHEN category = N'Goalkeeper' THEN value_share_pct ELSE 0 END) AS goalkeeper_share_pct,
           SUM(CASE WHEN category = N'Defender'   THEN value_share_pct ELSE 0 END) AS defender_share_pct,
           SUM(CASE WHEN category = N'Midfield'   THEN value_share_pct ELSE 0 END) AS midfield_share_pct,
           SUM(CASE WHEN category = N'Attack'     THEN value_share_pct ELSE 0 END) AS attack_share_pct
    FROM rpt.vw_portfolio_composition
    WHERE dimension = N'Position' AND snapshot_date = '2026-06-30'
    GROUP BY club_id
)
SELECT l.competition_id, l.competition_name, l.club_id, l.club_name,
       l.total_value_eur, l.value_rank_in_league, l.squad_size, l.avg_value_eur,
       l.avg_value_index_league, l.top5_share_pct, l.value_weighted_age,
       l.value_change_pct                                                         AS growth_last_year_pct,
       o.total_value_eur                                                          AS value_2020_eur,
       CAST(100.0 * (POWER(l.total_value_eur / o.total_value_eur, 1.0 / 6) - 1) AS DECIMAL(6,1)) AS cagr_2020_2026_pct,
       pm.goalkeeper_share_pct, pm.defender_share_pct, pm.midfield_share_pct, pm.attack_share_pct
FROM latest l
LEFT JOIN opening o       ON o.club_id = l.club_id
LEFT JOIN position_mix pm ON pm.club_id = l.club_id;
GO

/* ---------- Q9: valuation volatility ----------
   Volatility = standard deviation of the log change between a player's
   consecutive valuations (Transfermarkt revalues every few months), over
   the 3 years up to each snapshot, with at least 3 changes. Log changes
   treat a rise and an equal fall symmetrically and stop cheap players'
   huge % jumps (EUR 0.2m to 5m = +2,400%) from swamping the measure.
   Shown x100, so 30 = a typical revaluation moves the value about 30%. */
CREATE OR ALTER VIEW rpt.vw_player_volatility AS
WITH changes AS (
    SELECT player_id, valuation_date,
           LOG(market_value_eur / NULLIF(LAG(market_value_eur) OVER (PARTITION BY player_id ORDER BY valuation_date), 0)) AS log_change
    FROM dw.fact_player_valuation
    WHERE market_value_eur > 0
)
SELECT s.snapshot_date, c.player_id,
       COUNT(*)                                             AS valuation_changes,
       CAST(100 * STDEV(c.log_change) AS DECIMAL(7,1))      AS volatility_pct,
       CAST(100 * (EXP(AVG(c.log_change)) - 1) AS DECIMAL(7,1)) AS avg_change_pct  -- geometric mean per revaluation
FROM dw.dim_snapshot s
JOIN changes c
  ON c.valuation_date <= s.snapshot_date
 AND c.valuation_date >  DATEADD(YEAR, -3, s.snapshot_date)
WHERE c.log_change IS NOT NULL
  AND s.snapshot_type = 'Season end'
GROUP BY s.snapshot_date, c.player_id
HAVING COUNT(*) >= 3;
GO

CREATE OR ALTER VIEW rpt.vw_club_volatility AS
SELECT sc.snapshot_date, sc.closes_season_label, sc.competition_id, sc.club_id, c.club_name,
       COUNT(v.player_id)                                                            AS players_measured,
       CAST(100.0 * SUM(CASE WHEN v.player_id IS NOT NULL THEN ps.market_value_eur END)
            / SUM(ps.market_value_eur) AS DECIMAL(5,1))                              AS value_covered_pct,
       CAST(SUM(ps.market_value_eur * v.volatility_pct)
            / NULLIF(SUM(CASE WHEN v.player_id IS NOT NULL THEN ps.market_value_eur END), 0) AS DECIMAL(6,1))
                                                                                     AS portfolio_volatility_pct   -- value-weighted
FROM rpt.vw_snapshot_scope sc
JOIN rpt.vw_portfolio_player ps ON ps.club_id = sc.club_id AND ps.snapshot_date = sc.snapshot_date
JOIN dw.dim_club c              ON c.club_id = sc.club_id
LEFT JOIN rpt.vw_player_volatility v ON v.player_id = ps.player_id AND v.snapshot_date = ps.snapshot_date
GROUP BY sc.snapshot_date, sc.closes_season_label, sc.competition_id, sc.club_id, c.club_name;
GO

/* ---------- Q3: value change of paid signings while at the buying club ----------
   Value at transfer comes from the transfer record (or the latest valuation
   before it). Latest value = latest valuation after the move and before the
   player's next move, so it measures his time at the buying club only. */
CREATE OR ALTER VIEW rpt.vw_signing_appreciation AS
WITH signings AS (
    SELECT t.transfer_key, t.player_id, t.transfer_date, t.season_start_year, cs.competition_id,
           t.to_club_id, t.from_club_name, t.fee_eur, t.market_value_at_transfer_eur
    FROM dw.fact_transfer t
    JOIN rpt.vw_club_season cs ON cs.club_id = t.to_club_id AND cs.season_start_year = t.season_start_year
    WHERE t.fee_category = 'Paid fee'
)
SELECT s.transfer_key, s.transfer_date, se.season_label, s.competition_id,
       s.to_club_id AS club_id, c.club_name, s.from_club_name,
       s.player_id, p.player_name, p.position,
       CAST(DATEDIFF(DAY, p.date_of_birth, s.transfer_date) / 365.25 AS DECIMAL(4,1)) AS age_at_transfer,
       s.fee_eur,
       COALESCE(s.market_value_at_transfer_eur, vb.market_value_eur) AS value_at_transfer_eur,
       va.market_value_eur                                           AS latest_value_eur,
       va.valuation_date                                             AS latest_value_date,
       nm.next_move_date,
       CAST(CASE WHEN nm.next_move_date IS NULL THEN 1 ELSE 0 END AS BIT) AS still_at_club,
       va.market_value_eur - COALESCE(s.market_value_at_transfer_eur, vb.market_value_eur) AS appreciation_eur,
       CAST(100.0 * (va.market_value_eur - COALESCE(s.market_value_at_transfer_eur, vb.market_value_eur))
            / NULLIF(COALESCE(s.market_value_at_transfer_eur, vb.market_value_eur), 0) AS DECIMAL(8,1)) AS appreciation_pct,
       va.market_value_eur - s.fee_eur                               AS value_vs_fee_eur,
       CAST(DATEDIFF(DAY, s.transfer_date, va.valuation_date) / 365.25 AS DECIMAL(4,1)) AS years_measured
FROM signings s
JOIN dw.dim_player p ON p.player_id = s.player_id
JOIN dw.dim_club   c ON c.club_id   = s.to_club_id
JOIN dw.dim_season se ON se.season_start_year = s.season_start_year
OUTER APPLY (SELECT MIN(t2.transfer_date) AS next_move_date
             FROM dw.fact_transfer t2
             WHERE t2.player_id = s.player_id AND t2.transfer_date > s.transfer_date) nm
OUTER APPLY (SELECT TOP 1 v.market_value_eur
             FROM dw.fact_player_valuation v
             WHERE v.player_id = s.player_id AND v.valuation_date <= s.transfer_date
             ORDER BY v.valuation_date DESC) vb
OUTER APPLY (SELECT TOP 1 v.market_value_eur, v.valuation_date
             FROM dw.fact_player_valuation v
             WHERE v.player_id = s.player_id
               AND v.valuation_date > s.transfer_date
               AND v.valuation_date < COALESCE(nm.next_move_date, '9999-12-31')
             ORDER BY v.valuation_date DESC) va;
GO

/* ---------- Q8: fee paid vs market value at the time of transfer ----------
   Every paid deal where the buyer or the seller was in a top 5 league that season. */
CREATE OR ALTER VIEW rpt.vw_fee_vs_value AS
SELECT t.transfer_key, t.transfer_date, se.season_label,
       t.player_id, p.player_name, p.position,
       t.from_club_id, t.from_club_name, sell.competition_id AS seller_competition_id,
       t.to_club_id,   t.to_club_name,   buy.competition_id  AS buyer_competition_id,
       t.fee_eur, t.market_value_at_transfer_eur,
       t.fee_eur - t.market_value_at_transfer_eur                                   AS premium_eur,
       CAST(100.0 * (t.fee_eur - t.market_value_at_transfer_eur)
            / NULLIF(t.market_value_at_transfer_eur, 0) AS DECIMAL(8,1))            AS premium_pct,
       CASE WHEN t.market_value_at_transfer_eur IS NULL OR t.market_value_at_transfer_eur = 0 THEN 'No market value'
            WHEN t.fee_eur < 0.9 * t.market_value_at_transfer_eur THEN 'Below value (<90%)'
            WHEN t.fee_eur > 1.1 * t.market_value_at_transfer_eur THEN 'Above value (>110%)'
            ELSE 'Around value (90-110%)' END                                       AS price_band
FROM dw.fact_transfer t
JOIN dw.dim_player p  ON p.player_id = t.player_id
JOIN dw.dim_season se ON se.season_start_year = t.season_start_year
LEFT JOIN rpt.vw_club_season buy  ON buy.club_id  = t.to_club_id   AND buy.season_start_year  = t.season_start_year
LEFT JOIN rpt.vw_club_season sell ON sell.club_id = t.from_club_id AND sell.season_start_year = t.season_start_year
WHERE t.fee_category = 'Paid fee'
  AND (buy.club_id IS NOT NULL OR sell.club_id IS NOT NULL);
GO

/* ---------- Q7: fees paid and received per club-season in the top 5 ---------- */
CREATE OR ALTER VIEW rpt.vw_club_transfer_balance AS
WITH moves AS (
    SELECT to_club_id AS club_id, season_start_year,
           CASE WHEN fee_category = 'Paid fee' THEN fee_eur END AS paid_eur, CAST(NULL AS DECIMAL(18,2)) AS received_eur,
           1 AS deals_in, 0 AS deals_out,
           CASE WHEN fee_category = 'Unknown fee' THEN 1 ELSE 0 END AS unknown_in, 0 AS unknown_out
    FROM dw.fact_transfer
    UNION ALL
    SELECT from_club_id, season_start_year,
           NULL, CASE WHEN fee_category = 'Paid fee' THEN fee_eur END,
           0, 1,
           0, CASE WHEN fee_category = 'Unknown fee' THEN 1 ELSE 0 END
    FROM dw.fact_transfer
)
SELECT cs.competition_id, cs.season_start_year, se.season_label, cs.club_id, c.club_name,
       COALESCE(SUM(m.paid_eur), 0)                                AS fees_paid_eur,
       COALESCE(SUM(m.received_eur), 0)                            AS fees_received_eur,
       COALESCE(SUM(m.paid_eur), 0) - COALESCE(SUM(m.received_eur), 0) AS net_spend_eur,
       COALESCE(SUM(m.deals_in), 0)                                AS deals_in,
       COALESCE(SUM(m.deals_out), 0)                               AS deals_out,
       COALESCE(SUM(m.unknown_in), 0)                              AS unknown_fee_deals_in,
       COALESCE(SUM(m.unknown_out), 0)                             AS unknown_fee_deals_out
FROM rpt.vw_club_season cs
JOIN dw.dim_club c    ON c.club_id = cs.club_id
JOIN dw.dim_season se ON se.season_start_year = cs.season_start_year
LEFT JOIN moves m     ON m.club_id = cs.club_id AND m.season_start_year = cs.season_start_year
GROUP BY cs.competition_id, cs.season_start_year, se.season_label, cs.club_id, c.club_name;
GO

/* ---------- dimensions for Power BI ---------- */
CREATE OR ALTER VIEW rpt.vw_dim_club AS
SELECT club_id, club_name, current_competition_id, stadium_name, stadium_seats FROM dw.dim_club;
GO
CREATE OR ALTER VIEW rpt.vw_dim_competition AS
SELECT competition_id, competition_name, country_name FROM dw.dim_competition;
GO
CREATE OR ALTER VIEW rpt.vw_dim_snapshot AS
SELECT snapshot_date, snapshot_year, snapshot_type, season_start_year, season_label FROM dw.dim_snapshot;
GO

/* ---------- Q11: league table, built from raw scores ----------
   position = on-pitch table (points, then goal difference, then goals scored).
   official_position = the source's position after the club's final-round
   match, which includes point deductions and each league's own tie-breakers.
   Final round, not latest date: a postponed game played late (Atalanta's
   round 29 in June 2024) carries the position from its own round. */
CREATE OR ALTER VIEW rpt.vw_league_table AS
WITH totals AS (
    SELECT m.competition_id, m.season_start_year, cm.club_id,
           COUNT(*)                                          AS played,
           SUM(CASE WHEN cm.result = 'W' THEN 1 ELSE 0 END)  AS won,
           SUM(CASE WHEN cm.result = 'D' THEN 1 ELSE 0 END)  AS drawn,
           SUM(CASE WHEN cm.result = 'L' THEN 1 ELSE 0 END)  AS lost,
           SUM(cm.goals_for)                                 AS goals_for,
           SUM(cm.goals_against)                             AS goals_against,
           SUM(cm.points)                                    AS points
    FROM dw.fact_club_match cm
    JOIN dw.fact_match m ON m.game_id = cm.game_id
    GROUP BY m.competition_id, m.season_start_year, cm.club_id
),
last_match AS (
    SELECT m.competition_id, m.season_start_year, cm.club_id,
           CASE WHEN cm.is_home = 1 THEN m.home_position ELSE m.away_position END AS official_position,
           ROW_NUMBER() OVER (PARTITION BY m.competition_id, m.season_start_year, cm.club_id
                              ORDER BY TRY_CAST(LEFT(m.matchday, CHARINDEX('.', m.matchday + '.') - 1) AS INT) DESC,
                                       m.match_date DESC) AS rn   -- matchday is '38. Matchday'
    FROM dw.fact_club_match cm
    JOIN dw.fact_match m ON m.game_id = cm.game_id
)
SELECT t.competition_id, comp.competition_name, t.season_start_year, se.season_label,
       t.club_id, c.club_name,
       t.played, t.won, t.drawn, t.lost, t.goals_for, t.goals_against,
       t.goals_for - t.goals_against                                         AS goal_difference,
       t.points,
       CAST(1.0 * t.points / t.played AS DECIMAL(4,2))                       AS points_per_game,
       RANK() OVER (PARTITION BY t.competition_id, t.season_start_year
                    ORDER BY t.points DESC, t.goals_for - t.goals_against DESC, t.goals_for DESC) AS position,
       lm.official_position,
       COUNT(*) OVER (PARTITION BY t.competition_id, t.season_start_year)    AS clubs_in_league
FROM totals t
JOIN dw.dim_club c            ON c.club_id = t.club_id
JOIN dw.dim_competition comp  ON comp.competition_id = t.competition_id
JOIN dw.dim_season se         ON se.season_start_year = t.season_start_year
LEFT JOIN last_match lm       ON lm.competition_id = t.competition_id AND lm.season_start_year = t.season_start_year
                             AND lm.club_id = t.club_id AND lm.rn = 1;
GO

/* ---------- Q11: season-start portfolio value vs points ----------
   Expected points come from a line fitted within each league across all six
   seasons: points per game against the log of the club's value relative to
   the league average that season. points_vs_expected > 0 = more points
   than the squad's value predicts. */
CREATE OR ALTER VIEW rpt.vw_value_vs_points AS
WITH start_value AS (
    SELECT ps.club_id, ds.season_start_year, SUM(ps.market_value_eur) AS value_eur, COUNT(*) AS squad_size
    FROM rpt.vw_portfolio_player ps
    JOIN dw.dim_snapshot ds ON ds.snapshot_date = ps.snapshot_date AND ds.snapshot_type = 'Season start'
    GROUP BY ps.club_id, ds.season_start_year
),
joined AS (
    SELECT lt.*, sv.value_eur AS season_start_value_eur, sv.squad_size,
           sv.value_eur / AVG(sv.value_eur) OVER (PARTITION BY lt.competition_id, lt.season_start_year) AS value_index,
           RANK() OVER (PARTITION BY lt.competition_id, lt.season_start_year ORDER BY sv.value_eur DESC) AS value_rank
    FROM rpt.vw_league_table lt
    JOIN start_value sv ON sv.club_id = lt.club_id AND sv.season_start_year = lt.season_start_year
),
xy AS (
    SELECT j.*, LOG(j.value_index) AS x, 1.0 * j.points / j.played AS y
    FROM joined j
),
fit AS (
    SELECT xy.*,
           (AVG(x * y) OVER (PARTITION BY competition_id) - AVG(x) OVER (PARTITION BY competition_id) * AVG(y) OVER (PARTITION BY competition_id))
             / NULLIF(VARP(x) OVER (PARTITION BY competition_id), 0) AS slope,
           AVG(x) OVER (PARTITION BY competition_id) AS mean_x,
           AVG(y) OVER (PARTITION BY competition_id) AS mean_y
    FROM xy
)
SELECT competition_id, competition_name, season_start_year, season_label, club_id, club_name,
       played, points, points_per_game, position, official_position, clubs_in_league,
       season_start_value_eur, squad_size, value_rank,
       CAST(value_index AS DECIMAL(6,2))                                        AS value_index,  -- 1 = league average
       CAST((mean_y + slope * (x - mean_x)) * played AS DECIMAL(5,1))           AS expected_points,
       CAST(points - (mean_y + slope * (x - mean_x)) * played AS DECIMAL(5,1))  AS points_vs_expected,
       value_rank - position                                                    AS places_above_value_rank
FROM fit;
GO

/* ---------- summary: season-start portfolios matched to league tables (expect 588) ---------- */
SELECT COUNT(*) AS club_seasons_with_value_and_points FROM rpt.vw_value_vs_points;

/* ---------- summary: reported portfolios per snapshot ---------- */
SELECT snapshot_date, COUNT(*) AS clubs, AVG(squad_size) AS avg_squad,
       SUM(CAST(is_thin_squad AS INT)) AS thin_squads,
       CAST(SUM(total_value_eur) / 1e9 AS DECIMAL(8,2)) AS total_value_eur_bn
FROM rpt.vw_club_portfolio
GROUP BY snapshot_date
ORDER BY snapshot_date;
