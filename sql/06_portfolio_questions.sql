/* =====================================================================
   Football Transfer ROI  |  Step 6: the 10 portfolio questions
   ---------------------------------------------------------------------
   Run after step 5. Each section answers one question from the reporting
   views; the written answers are in docs/findings.md.
   "Latest" = 30 Jun 2026, the end of 2025/26. Values in EUR millions.
   ===================================================================== */

USE FootballTransferROI;
GO
SET NOCOUNT ON;

/* =====================================================================
   Q1. How has the total market value of each club's portfolio changed over time?
   ===================================================================== */

-- 1a. Total portfolio value by league at each 30 June
SELECT snapshot_date,
       CAST(SUM(CASE WHEN competition_id = 'GB1' THEN total_value_eur END) / 1e6 AS INT) AS premier_league_m,
       CAST(SUM(CASE WHEN competition_id = 'ES1' THEN total_value_eur END) / 1e6 AS INT) AS laliga_m,
       CAST(SUM(CASE WHEN competition_id = 'IT1' THEN total_value_eur END) / 1e6 AS INT) AS serie_a_m,
       CAST(SUM(CASE WHEN competition_id = 'L1'  THEN total_value_eur END) / 1e6 AS INT) AS bundesliga_m,
       CAST(SUM(CASE WHEN competition_id = 'FR1' THEN total_value_eur END) / 1e6 AS INT) AS ligue_1_m,
       CAST(SUM(total_value_eur) / 1e6 AS INT)                                           AS top5_m
FROM rpt.vw_club_portfolio
GROUP BY snapshot_date
ORDER BY snapshot_date;

-- 1b. Fastest and slowest growing portfolios, 30 Jun 2020 to 30 Jun 2026
--     (clubs in the top 5 in both 2020/21 and 2025/26)
SELECT TOP 10 club_name, competition_id,
       CAST(value_2020_eur / 1e6 AS INT) AS value_2020_m, CAST(total_value_eur / 1e6 AS INT) AS value_2026_m,
       cagr_2020_2026_pct
FROM rpt.vw_club_kpis WHERE value_2020_eur IS NOT NULL
ORDER BY cagr_2020_2026_pct DESC;

SELECT TOP 10 club_name, competition_id,
       CAST(value_2020_eur / 1e6 AS INT) AS value_2020_m, CAST(total_value_eur / 1e6 AS INT) AS value_2026_m,
       cagr_2020_2026_pct
FROM rpt.vw_club_kpis WHERE value_2020_eur IS NOT NULL
ORDER BY cagr_2020_2026_pct ASC;

-- 1c. Biggest single-season swings (EUR)
SELECT TOP 5 closes_season_label, club_name, CAST(value_change_eur / 1e6 AS INT) AS change_m, value_change_pct
FROM rpt.vw_club_portfolio WHERE value_change_eur IS NOT NULL ORDER BY value_change_eur DESC;
SELECT TOP 5 closes_season_label, club_name, CAST(value_change_eur / 1e6 AS INT) AS change_m, value_change_pct
FROM rpt.vw_club_portfolio WHERE value_change_eur IS NOT NULL ORDER BY value_change_eur ASC;

/* =====================================================================
   Q2. Which clubs have the highest concentration risk (top 5 players' share of value)?
   ===================================================================== */

-- 2a. Most concentrated portfolios, latest
SELECT TOP 10 club_name, competition_id, CAST(total_value_eur / 1e6 AS INT) AS value_m, top5_share_pct, is_thin_squad
FROM rpt.vw_club_portfolio WHERE snapshot_year = 2026
ORDER BY top5_share_pct DESC;

-- 2b. Least concentrated, latest
SELECT TOP 5 club_name, competition_id, CAST(total_value_eur / 1e6 AS INT) AS value_m, top5_share_pct
FROM rpt.vw_club_portfolio WHERE snapshot_year = 2026
ORDER BY top5_share_pct ASC;

-- 2c. Average concentration by league over time
SELECT snapshot_date, competition_id, CAST(AVG(top5_share_pct) AS DECIMAL(5,1)) AS avg_top5_share_pct
FROM rpt.vw_club_portfolio
GROUP BY snapshot_date, competition_id
ORDER BY competition_id, snapshot_date;

/* =====================================================================
   Q3. Which acquisitions have appreciated most after joining a new club?
   ===================================================================== */

-- 3a. Biggest gains in EUR (value at transfer -> latest value at the buying club)
SELECT TOP 15 season_label, player_name, from_club_name, club_name,
       CAST(fee_eur / 1e6 AS DECIMAL(6,1))                AS fee_m,
       CAST(value_at_transfer_eur / 1e6 AS DECIMAL(6,1))  AS value_at_transfer_m,
       CAST(latest_value_eur / 1e6 AS DECIMAL(6,1))       AS latest_value_m,
       CAST(appreciation_eur / 1e6 AS DECIMAL(6,1))       AS gain_m,
       appreciation_pct, years_measured, still_at_club
FROM rpt.vw_signing_appreciation
WHERE appreciation_eur IS NOT NULL
ORDER BY appreciation_eur DESC;

-- 3b. Biggest % gains among signings valued at EUR 5m+ when they joined
SELECT TOP 10 season_label, player_name, club_name,
       CAST(value_at_transfer_eur / 1e6 AS DECIMAL(6,1)) AS value_at_transfer_m,
       CAST(latest_value_eur / 1e6 AS DECIMAL(6,1))      AS latest_value_m,
       appreciation_pct
FROM rpt.vw_signing_appreciation
WHERE value_at_transfer_eur >= 5e6 AND appreciation_pct IS NOT NULL
ORDER BY appreciation_pct DESC;

-- 3c. How often do signings gain value? By value when bought, with 12+ months measured
WITH banded AS (
    SELECT appreciation_eur, appreciation_pct,
           CASE WHEN value_at_transfer_eur < 10e6 THEN '1. under 10m'
                WHEN value_at_transfer_eur < 30e6 THEN '2. 10-30m'
                WHEN value_at_transfer_eur < 60e6 THEN '3. 30-60m'
                ELSE '4. 60m+' END AS value_band
    FROM rpt.vw_signing_appreciation
    WHERE appreciation_eur IS NOT NULL AND years_measured >= 1 AND value_at_transfer_eur > 0
)
SELECT DISTINCT value_band,
       COUNT(*) OVER (PARTITION BY value_band) AS signings,
       CAST(100.0 * SUM(CASE WHEN appreciation_eur > 0 THEN 1 ELSE 0 END) OVER (PARTITION BY value_band)
            / COUNT(*) OVER (PARTITION BY value_band) AS DECIMAL(5,1))                                AS pct_gained,
       CAST(PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY appreciation_pct) OVER (PARTITION BY value_band) AS DECIMAL(6,1)) AS median_change_pct
FROM banded
ORDER BY value_band;

/* =====================================================================
   Q4. Which clubs are most exposed to declining asset values, and how has it changed?
   Exposure = share of portfolio value in players worth less than a year earlier.
   ===================================================================== */

-- 4a. Most exposed, latest
SELECT TOP 10 club_name, competition_id, declining_players, squad_size,
       declining_exposure_pct, CAST(value_lost_eur / 1e6 AS DECIMAL(6,1)) AS value_lost_m
FROM rpt.vw_club_portfolio WHERE snapshot_year = 2026
ORDER BY declining_exposure_pct DESC;

-- 4b. Exposure over time, all reported clubs (2021 onwards: valuations start mid-2019)
SELECT snapshot_date,
       CAST(SUM(declining_value_eur) * 100.0 / SUM(value_with_history_eur) AS DECIMAL(5,1)) AS top5_exposure_pct,
       CAST(SUM(value_lost_eur) / 1e6 AS INT) AS value_lost_m
FROM rpt.vw_club_portfolio
WHERE snapshot_year >= 2021
GROUP BY snapshot_date
ORDER BY snapshot_date;

-- 4c. Persistently exposed: average exposure across 2021-2026, clubs reported in all 6 years
SELECT TOP 10 club_name, competition_id, COUNT(*) AS years,
       CAST(AVG(declining_exposure_pct) AS DECIMAL(5,1)) AS avg_exposure_pct,
       CAST(SUM(value_lost_eur) / 1e6 AS INT)            AS value_lost_m
FROM rpt.vw_club_portfolio
WHERE snapshot_year >= 2021
GROUP BY club_id, club_name, competition_id
HAVING COUNT(*) = 6
ORDER BY avg_exposure_pct DESC;

/* =====================================================================
   Q5. How do clubs compare in value, growth and composition?
   ===================================================================== */

-- 5a. Benchmark of the 15 most valuable portfolios, latest
SELECT TOP 15 club_name, competition_id, CAST(total_value_eur / 1e6 AS INT) AS value_m,
       value_rank_in_league, cagr_2020_2026_pct, growth_last_year_pct, top5_share_pct, value_weighted_age,
       goalkeeper_share_pct, defender_share_pct, midfield_share_pct, attack_share_pct
FROM rpt.vw_club_kpis
ORDER BY total_value_eur DESC;

-- 5b. League benchmark, latest
SELECT k.competition_name, COUNT(*) AS clubs,
       CAST(SUM(k.total_value_eur) / 1e6 AS INT)                     AS total_value_m,
       CAST(AVG(k.total_value_eur) / 1e6 AS INT)                     AS avg_club_value_m,
       CAST(MAX(k.total_value_eur) / NULLIF(MIN(k.total_value_eur), 0) AS DECIMAL(5,1)) AS richest_to_poorest_ratio,
       CAST(AVG(k.cagr_2020_2026_pct) AS DECIMAL(5,1))               AS avg_cagr_pct,
       CAST(AVG(k.attack_share_pct) AS DECIMAL(5,1))                 AS avg_attack_share_pct
FROM rpt.vw_club_kpis k
GROUP BY k.competition_name
ORDER BY total_value_m DESC;

/* =====================================================================
   Q6. How does a portfolio's age profile relate to its value and growth?
   ===================================================================== */

-- 6a. Correlation of value-weighted age with portfolio value (same snapshot)
--     and with growth over the following season
WITH pairs AS (
    SELECT cur.value_weighted_age AS age, cur.total_value_eur / 1e6 AS value_m, nxt.value_change_pct AS next_growth_pct
    FROM rpt.vw_club_portfolio cur
    LEFT JOIN rpt.vw_club_portfolio nxt
      ON nxt.club_id = cur.club_id AND nxt.snapshot_year = cur.snapshot_year + 1
)
SELECT COUNT(*) AS club_snapshots,
       CAST((AVG(age * value_m) - AVG(age) * AVG(value_m)) / (STDEVP(age) * STDEVP(value_m)) AS DECIMAL(4,2)) AS corr_age_value,
       (SELECT CAST((AVG(age * next_growth_pct) - AVG(age) * AVG(next_growth_pct))
                    / (STDEVP(age) * STDEVP(next_growth_pct)) AS DECIMAL(4,2))
        FROM pairs WHERE next_growth_pct IS NOT NULL)                                                       AS corr_age_next_growth
FROM pairs;

-- 6b. Growth over the following season by age group of the portfolio
WITH pairs AS (
    SELECT cur.value_weighted_age, nxt.value_change_pct AS next_growth_pct
    FROM rpt.vw_club_portfolio cur
    JOIN rpt.vw_club_portfolio nxt ON nxt.club_id = cur.club_id AND nxt.snapshot_year = cur.snapshot_year + 1
)
SELECT CASE WHEN value_weighted_age < 24 THEN '1. under 24'
            WHEN value_weighted_age < 25.5 THEN '2. 24-25.5'
            WHEN value_weighted_age < 27 THEN '3. 25.5-27'
            ELSE '4. 27+' END AS portfolio_age,
       COUNT(*) AS club_seasons,
       CAST(AVG(next_growth_pct) AS DECIMAL(5,1)) AS avg_next_season_growth_pct
FROM pairs
GROUP BY CASE WHEN value_weighted_age < 24 THEN '1. under 24'
              WHEN value_weighted_age < 25.5 THEN '2. 24-25.5'
              WHEN value_weighted_age < 27 THEN '3. 25.5-27'
              ELSE '4. 27+' END
ORDER BY portfolio_age;

-- 6c. Share of top 5 portfolio value by age band over time
SELECT snapshot_date, category AS age_band,
       CAST(100.0 * SUM(value_eur) / SUM(SUM(value_eur)) OVER (PARTITION BY snapshot_date) AS DECIMAL(5,1)) AS value_share_pct
FROM rpt.vw_portfolio_composition
WHERE dimension = N'Age band'
GROUP BY snapshot_date, category
ORDER BY snapshot_date, category;

-- 6d. Youngest and oldest valuable portfolios, latest
SELECT TOP 5 club_name, CAST(total_value_eur / 1e6 AS INT) AS value_m, value_weighted_age, cagr_2020_2026_pct
FROM rpt.vw_club_kpis ORDER BY value_weighted_age ASC;
SELECT TOP 5 club_name, CAST(total_value_eur / 1e6 AS INT) AS value_m, value_weighted_age, cagr_2020_2026_pct
FROM rpt.vw_club_kpis ORDER BY value_weighted_age DESC;

/* =====================================================================
   Q7. Which clubs have the biggest gap between fees paid and received?
   Period: 2020/21-2025/26, seasons the club spent in a top 5 league.
   ===================================================================== */
WITH totals AS (
    SELECT club_id, club_name, COUNT(*) AS seasons,
           SUM(fees_paid_eur) AS paid, SUM(fees_received_eur) AS received, SUM(net_spend_eur) AS net,
           SUM(unknown_fee_deals_in + unknown_fee_deals_out) AS unknown_fee_deals
    FROM rpt.vw_club_transfer_balance
    GROUP BY club_id, club_name
)
SELECT * FROM (
    SELECT TOP 10 'Net spender' AS side, club_name, seasons,
           CAST(paid / 1e6 AS INT) AS paid_m, CAST(received / 1e6 AS INT) AS received_m, CAST(net / 1e6 AS INT) AS net_m,
           unknown_fee_deals
    FROM totals ORDER BY net DESC
) s
UNION ALL
SELECT * FROM (
    SELECT TOP 10 'Net seller' AS side, club_name, seasons,
           CAST(paid / 1e6 AS INT) AS paid_m, CAST(received / 1e6 AS INT) AS received_m, CAST(net / 1e6 AS INT) AS net_m,
           unknown_fee_deals
    FROM totals ORDER BY net ASC
) r;

/* =====================================================================
   Q8. How does market value compare with the fee at the time of transfer?
   ===================================================================== */

-- 8a. Price bands
SELECT price_band, COUNT(*) AS deals,
       CAST(100.0 * COUNT(*) / SUM(COUNT(*)) OVER () AS DECIMAL(5,1)) AS pct_of_deals,
       CAST(SUM(fee_eur) / 1e6 AS INT) AS fees_m
FROM rpt.vw_fee_vs_value
GROUP BY price_band
ORDER BY deals DESC;

-- 8b. Fee vs value by buying league (deals into top 5 clubs)
SELECT DISTINCT comp.competition_name,
       COUNT(*) OVER (PARTITION BY f.buyer_competition_id) AS deals,
       CAST(SUM(f.fee_eur) OVER (PARTITION BY f.buyer_competition_id)
            / SUM(f.market_value_at_transfer_eur) OVER (PARTITION BY f.buyer_competition_id) AS DECIMAL(4,2)) AS fee_to_value_ratio,
       CAST(PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY f.premium_pct) OVER (PARTITION BY f.buyer_competition_id) AS DECIMAL(6,1)) AS median_premium_pct
FROM rpt.vw_fee_vs_value f
JOIN dw.dim_competition comp ON comp.competition_id = f.buyer_competition_id
WHERE f.market_value_at_transfer_eur > 0;

-- 8c. Biggest premiums over market value (EUR)
SELECT TOP 10 season_label, player_name, from_club_name, to_club_name,
       CAST(fee_eur / 1e6 AS DECIMAL(6,1)) AS fee_m,
       CAST(market_value_at_transfer_eur / 1e6 AS DECIMAL(6,1)) AS value_m,
       CAST(premium_eur / 1e6 AS DECIMAL(6,1)) AS premium_m, premium_pct
FROM rpt.vw_fee_vs_value WHERE market_value_at_transfer_eur > 0
ORDER BY premium_eur DESC;

-- 8d. Buying clubs that pay most above value (10+ paid signings with a market value)
SELECT TOP 10 to_club_name, COUNT(*) AS deals,
       CAST(SUM(fee_eur) / SUM(market_value_at_transfer_eur) AS DECIMAL(4,2)) AS fee_to_value_ratio,
       CAST(SUM(premium_eur) / 1e6 AS INT) AS total_premium_m
FROM rpt.vw_fee_vs_value
WHERE buyer_competition_id IS NOT NULL AND market_value_at_transfer_eur > 0
GROUP BY to_club_id, to_club_name
HAVING COUNT(*) >= 10
ORDER BY fee_to_value_ratio DESC;

/* =====================================================================
   Q9. How volatile are player valuations, and which portfolios are most volatile?
   ===================================================================== */

-- 9a. Player volatility by position and value, latest (3 years to 30 Jun 2026)
SELECT COALESCE(NULLIF(pp.position, N'Missing'), N'Unknown') AS position,
       COUNT(*) AS players,
       CAST(AVG(v.volatility_pct) AS DECIMAL(5,1)) AS avg_volatility_pct,
       CAST(AVG(CASE WHEN pp.market_value_eur >= 30e6 THEN v.volatility_pct END) AS DECIMAL(5,1)) AS avg_volatility_30m_plus_pct
FROM rpt.vw_portfolio_player pp
JOIN rpt.vw_player_volatility v ON v.player_id = pp.player_id AND v.snapshot_date = pp.snapshot_date
WHERE pp.snapshot_date = '2026-06-30'
GROUP BY COALESCE(NULLIF(pp.position, N'Missing'), N'Unknown');

-- 9b. Most and least volatile portfolios, latest
SELECT TOP 10 club_name, competition_id, portfolio_volatility_pct, players_measured, value_covered_pct
FROM rpt.vw_club_volatility WHERE snapshot_date = '2026-06-30'
ORDER BY portfolio_volatility_pct DESC;
SELECT TOP 5 club_name, competition_id, portfolio_volatility_pct, players_measured, value_covered_pct
FROM rpt.vw_club_volatility WHERE snapshot_date = '2026-06-30'
ORDER BY portfolio_volatility_pct ASC;

-- 9c. Volatility of the club's total value: std dev of season-on-season % change, 2021-2026
SELECT TOP 10 club_name, competition_id, COUNT(*) AS changes,
       CAST(STDEV(value_change_pct) AS DECIMAL(5,1)) AS total_value_volatility_pct,
       CAST(AVG(value_change_pct)   AS DECIMAL(5,1)) AS avg_change_pct
FROM rpt.vw_club_portfolio
WHERE value_change_pct IS NOT NULL
GROUP BY club_id, club_name, competition_id
HAVING COUNT(*) = 6
ORDER BY total_value_volatility_pct DESC;

/* =====================================================================
   Q10. Which clubs have the highest average asset value for their portfolio size?
   ===================================================================== */
SELECT TOP 15 club_name, competition_id, squad_size,
       CAST(avg_value_eur / 1e6 AS DECIMAL(5,1)) AS avg_value_m,
       avg_value_index_league, avg_value_index_top5
FROM rpt.vw_club_portfolio
WHERE snapshot_year = 2026
ORDER BY avg_value_eur DESC;

SELECT competition_id,
       CAST(SUM(total_value_eur) / SUM(squad_size) / 1e6 AS DECIMAL(5,1)) AS league_avg_value_m,
       CAST(MAX(avg_value_index_league) AS DECIMAL(6,1)) AS top_club_index
FROM rpt.vw_club_portfolio
WHERE snapshot_year = 2026
GROUP BY competition_id
ORDER BY league_avg_value_m DESC;
