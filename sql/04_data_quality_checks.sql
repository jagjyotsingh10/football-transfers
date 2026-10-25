/* =====================================================================
   Football Transfer ROI  |  Step 4 of 4: data quality checks
   ---------------------------------------------------------------------
   Run after step 3. Each query returns a small result set; read the
   comment above it to know what "good" looks like. Write down anything
   surprising in docs/data_quality_log.md: those notes become a README
   section and strong interview answers ("here's what I found and fixed").
   ===================================================================== */

USE FootballTransferROI;
GO

/* ---------- 1. Did anything get lost between staging and the warehouse? ----------
   Large drops are expected (we keep 5 leagues and 6 seasons); the point is
   to know the numbers and explain them. */
SELECT 'games'             AS source_table, (SELECT COUNT(*) FROM stg.games)             AS stg_rows, (SELECT COUNT(*) FROM dw.fact_match)            AS dw_rows UNION ALL
SELECT 'transfers',                         (SELECT COUNT(*) FROM stg.transfers),                     (SELECT COUNT(*) FROM dw.fact_transfer)                    UNION ALL
SELECT 'player_valuations',                 (SELECT COUNT(*) FROM stg.player_valuations),             (SELECT COUNT(*) FROM dw.fact_player_valuation)            UNION ALL
SELECT 'appearances',                       (SELECT COUNT(*) FROM stg.appearances),                   (SELECT COUNT(*) FROM dw.fact_appearance)                  UNION ALL
SELECT 'players',                           (SELECT COUNT(*) FROM stg.players),                       (SELECT COUNT(*) FROM dw.dim_player);

/* ---------- 2. Are all five league codes present in the source? ----------
   Expect 5 rows, all 'found'. A 'MISSING' means the dataset renamed a code. */
SELECT c.competition_id, c.competition_name,
       CASE WHEN EXISTS (SELECT 1 FROM stg.competitions s WHERE s.competition_id = c.competition_id)
            THEN 'found' ELSE 'MISSING' END AS in_source
FROM dw.dim_competition c;

/* ---------- 3. Is every league-season complete? ----------
   A full double round-robin has clubs x (clubs - 1) matches.
   Expect 20 clubs (380 matches) for England, Spain, Italy; 18 clubs (306)
   for Germany; France had 20 clubs until 2022/23 and 18 from 2023/24. */
WITH clubs_per_season AS (
    SELECT m.competition_id, m.season_start_year, COUNT(DISTINCT cm.club_id) AS clubs
    FROM dw.fact_club_match cm
    JOIN dw.fact_match m ON m.game_id = cm.game_id
    GROUP BY m.competition_id, m.season_start_year
),
matches_per_season AS (
    SELECT competition_id, season_start_year,
           COUNT(*)                                                      AS matches_in_data,
           SUM(CASE WHEN home_goals IS NULL THEN 1 ELSE 0 END)           AS matches_without_score
    FROM dw.fact_match
    GROUP BY competition_id, season_start_year
)
SELECT mp.competition_id, s.season_label, cp.clubs,
       cp.clubs * (cp.clubs - 1)  AS matches_expected,
       mp.matches_in_data,
       mp.matches_without_score,
       CASE WHEN mp.matches_in_data - mp.matches_without_score = cp.clubs * (cp.clubs - 1)
            THEN 'complete' ELSE 'CHECK' END AS status
FROM matches_per_season mp
JOIN clubs_per_season cp ON cp.competition_id = mp.competition_id AND cp.season_start_year = mp.season_start_year
JOIN dw.dim_season s     ON s.season_start_year = mp.season_start_year
ORDER BY mp.competition_id, mp.season_start_year;

/* ---------- 4. Does every club play the right number of games? ----------
   Each club should play 2 x (clubs - 1) matches per season (38 or 34).
   Any rows returned here need a look. */
WITH club_season AS (
    SELECT m.competition_id, m.season_start_year, cm.club_id, COUNT(*) AS games_played
    FROM dw.fact_club_match cm
    JOIN dw.fact_match m ON m.game_id = cm.game_id
    GROUP BY m.competition_id, m.season_start_year, cm.club_id
),
league_size AS (
    SELECT competition_id, season_start_year, COUNT(*) AS clubs
    FROM club_season
    GROUP BY competition_id, season_start_year
)
SELECT cs.competition_id, cs.season_start_year, c.club_name, cs.games_played,
       2 * (ls.clubs - 1) AS games_expected
FROM club_season cs
JOIN league_size ls ON ls.competition_id = cs.competition_id AND ls.season_start_year = cs.season_start_year
JOIN dw.dim_club c  ON c.club_id = cs.club_id
WHERE cs.games_played <> 2 * (ls.clubs - 1)
ORDER BY cs.competition_id, cs.season_start_year;

/* ---------- 5. How reliable are transfer fees? (the key caveat of this project) ----------
   Zero fees mix free transfers, loans and loan returns; unknown fees are NULL.
   Report what share of incoming deals and money is covered by known paid fees. */
SELECT s.season_label,
       t.fee_category,
       COUNT(*)                      AS deals,
       CAST(100.0 * COUNT(*) / SUM(COUNT(*)) OVER (PARTITION BY s.season_label) AS DECIMAL(5,1)) AS pct_of_deals,
       CAST(SUM(t.fee_eur) / 1e6 AS DECIMAL(12,1))  AS total_fees_eur_m
FROM dw.fact_transfer t
JOIN dw.dim_season s ON s.season_start_year = t.season_start_year
WHERE t.is_top5_buyer = 1
GROUP BY s.season_label, t.fee_category
ORDER BY s.season_label, t.fee_category;

/* ---------- 6. Sanity check: the 15 biggest fees in scope ----------
   You should recognise these deals. If you don't, something is off
   (e.g. fees in the wrong unit or a broken season mapping). */
SELECT TOP 15 s.season_label, p.player_name, t.from_club_name, t.to_club_name,
       CAST(t.fee_eur / 1e6 AS DECIMAL(8,1)) AS fee_eur_m,
       CAST(t.market_value_at_transfer_eur / 1e6 AS DECIMAL(8,1)) AS market_value_eur_m
FROM dw.fact_transfer t
JOIN dw.dim_player p ON p.player_id = t.player_id
JOIN dw.dim_season s ON s.season_start_year = t.season_start_year
ORDER BY t.fee_eur DESC;

/* ---------- 7. Implausible values ----------
   Expect zero rows from each. */
SELECT 'fee above 250m'           AS issue, COUNT(*) AS row_count FROM dw.fact_transfer   WHERE fee_eur > 250000000 UNION ALL
SELECT 'negative fee',                      COUNT(*)              FROM dw.fact_transfer   WHERE fee_eur < 0         UNION ALL
SELECT 'minutes above 130',                 COUNT(*)              FROM dw.fact_appearance WHERE minutes_played > 130 UNION ALL
SELECT 'match without a date',              COUNT(*)              FROM dw.fact_match      WHERE match_date IS NULL  UNION ALL
SELECT 'match date outside its season',     COUNT(*)
    FROM dw.fact_match m JOIN dw.dim_season s ON s.season_start_year = m.season_start_year
    WHERE m.match_date NOT BETWEEN s.window_start AND DATEADD(MONTH, 1, s.window_end) UNION ALL  -- allows late play-offs
SELECT 'transfer to and from same club',    COUNT(*)              FROM dw.fact_transfer   WHERE from_club_id = to_club_id;

/* ---------- 8. What did the cleaning step drop, and why? ----------
   Rows in staging that could not be typed. Small counts are normal;
   note them in your data quality log. */
SELECT 'transfers: unreadable date'         AS issue, COUNT(*) AS row_count FROM stg.transfers         WHERE TRY_CONVERT(DATE, LEFT(transfer_date, 10), 23) IS NULL UNION ALL
SELECT 'transfers: player not in players',            COUNT(*)              FROM stg.transfers t       WHERE NOT EXISTS (SELECT 1 FROM stg.players p WHERE p.player_id = t.player_id) UNION ALL
SELECT 'valuations: unreadable value',                COUNT(*)              FROM stg.player_valuations WHERE TRY_CAST(market_value_in_eur AS FLOAT) IS NULL UNION ALL
SELECT 'appearances: duplicate appearance_id',        COUNT(*) - COUNT(DISTINCT appearance_id) FROM stg.appearances;

/* ---------- 9. Coverage: how fresh is the data? ----------
   The latest in-scope match should be from late May / June 2026. */
SELECT MIN(match_date) AS first_match, MAX(match_date) AS last_match FROM dw.fact_match;
SELECT MIN(transfer_date) AS first_transfer, MAX(transfer_date) AS last_transfer FROM dw.fact_transfer;
