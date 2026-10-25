/* =====================================================================
   Football Transfer ROI  |  Step 3 of 4: build the clean star schema
   ---------------------------------------------------------------------
   Turns raw stg text into typed, keyed dw tables, scoped to:
     - the top 5 European leagues (dw.dim_competition)
     - seasons 2020/21 to 2025/26 (dw.dim_season)
   To change the scope, edit those two inserts and re-run the whole file.
   The script is re-runnable: it drops and rebuilds every dw table.

   Design notes (useful for your README and interviews):
     - Seasons run 1 July to 30 June, so both transfer windows (summer and
       January) fall inside the season they affect.
     - 2026/27 is excluded on purpose: it is in progress, and partial
       seasons would distort points-per-euro comparisons.
     - Club results are derived from raw scores here, not taken from the
       dataset's club_games table, so the points logic is fully ours.
     - The source records free transfers, loans and loan returns all as a
       fee of 0, and unknown fees as NULL. fee_category keeps them apart.
   ===================================================================== */

USE FootballTransferROI;
GO

/* ---------- drop in dependency order (children first) ---------- */
DROP TABLE IF EXISTS dw.fact_appearance;
DROP TABLE IF EXISTS dw.fact_transfer;
DROP TABLE IF EXISTS dw.fact_player_valuation;
DROP TABLE IF EXISTS dw.fact_club_match;
DROP TABLE IF EXISTS dw.fact_match;
DROP TABLE IF EXISTS dw.dim_player;
DROP TABLE IF EXISTS dw.dim_club;
DROP TABLE IF EXISTS dw.dim_season;
DROP TABLE IF EXISTS dw.dim_competition;
GO

/* =====================================================================
   DIMENSIONS
   ===================================================================== */

/* ---------- dim_competition: the five leagues in scope ---------- */
CREATE TABLE dw.dim_competition (
    competition_id   VARCHAR(10)   NOT NULL CONSTRAINT PK_dim_competition PRIMARY KEY,
    competition_name NVARCHAR(100) NOT NULL,
    country_name     NVARCHAR(100) NOT NULL
);

INSERT INTO dw.dim_competition (competition_id, competition_name, country_name)
VALUES ('GB1', N'Premier League', N'England'),
       ('ES1', N'LaLiga',         N'Spain'),
       ('IT1', N'Serie A',        N'Italy'),
       ('L1',  N'Bundesliga',     N'Germany'),
       ('FR1', N'Ligue 1',        N'France');
GO

/* ---------- dim_season: one row per season, with its date window ---------- */
CREATE TABLE dw.dim_season (
    season_start_year    SMALLINT NOT NULL CONSTRAINT PK_dim_season PRIMARY KEY,
    season_label         CHAR(7)  NOT NULL,  -- 2024/25
    window_start         DATE     NOT NULL,  -- 1 July
    window_end           DATE     NOT NULL   -- 30 June
);

WITH years AS (
    SELECT CAST(2020 AS SMALLINT) AS y
    UNION ALL
    SELECT CAST(y + 1 AS SMALLINT) FROM years WHERE y < 2025
)
INSERT INTO dw.dim_season (season_start_year, season_label, window_start, window_end)
SELECT y,
       CONCAT(y, '/', RIGHT(CAST(y + 1 AS VARCHAR(4)), 2)),
       DATEFROMPARTS(y, 7, 1),
       DATEFROMPARTS(y + 1, 6, 30)
FROM years;
GO

/* ---------- dim_club: every club that played an in-scope league match ----------
   Built from match data rather than the clubs file, because the clubs file
   only knows each club's CURRENT league; relegated clubs would go missing. */
CREATE TABLE dw.dim_club (
    club_id                 INT           NOT NULL CONSTRAINT PK_dim_club PRIMARY KEY,
    club_name               NVARCHAR(200) NOT NULL,
    current_competition_id  VARCHAR(20)   NULL,
    stadium_name            NVARCHAR(200) NULL,
    stadium_seats           INT           NULL
);

WITH league_games AS (
    SELECT g.home_club_id AS club_id_txt, g.home_club_name AS club_name, g.[date] AS date_txt
    FROM stg.games g
    JOIN dw.dim_competition c ON c.competition_id = g.competition_id
    JOIN dw.dim_season s      ON s.season_start_year = TRY_CAST(g.season AS SMALLINT)
    UNION ALL
    SELECT g.away_club_id, g.away_club_name, g.[date]
    FROM stg.games g
    JOIN dw.dim_competition c ON c.competition_id = g.competition_id
    JOIN dw.dim_season s      ON s.season_start_year = TRY_CAST(g.season AS SMALLINT)
),
latest_name AS (
    SELECT TRY_CAST(club_id_txt AS INT) AS club_id,
           club_name,
           ROW_NUMBER() OVER (PARTITION BY TRY_CAST(club_id_txt AS INT)
                              ORDER BY TRY_CONVERT(DATE, LEFT(date_txt, 10), 23) DESC) AS rn
    FROM league_games
    WHERE TRY_CAST(club_id_txt AS INT) IS NOT NULL
),
clubs_dedup AS (
    SELECT TRY_CAST(club_id AS INT) AS club_id, name, domestic_competition_id,
           stadium_name, stadium_seats,
           ROW_NUMBER() OVER (PARTITION BY TRY_CAST(club_id AS INT) ORDER BY (SELECT NULL)) AS rn
    FROM stg.clubs
)
INSERT INTO dw.dim_club (club_id, club_name, current_competition_id, stadium_name, stadium_seats)
SELECT ln.club_id,
       COALESCE(cl.name, ln.club_name, CONCAT(N'Club ', ln.club_id)),
       cl.domestic_competition_id,
       cl.stadium_name,
       TRY_CAST(TRY_CAST(cl.stadium_seats AS FLOAT) AS INT)
FROM latest_name ln
LEFT JOIN clubs_dedup cl ON cl.club_id = ln.club_id AND cl.rn = 1
WHERE ln.rn = 1;
GO

/* ---------- dim_player ---------- */
CREATE TABLE dw.dim_player (
    player_id                 INT           NOT NULL CONSTRAINT PK_dim_player PRIMARY KEY,
    player_name               NVARCHAR(200) NOT NULL,
    position                  NVARCHAR(50)  NULL,
    sub_position              NVARCHAR(100) NULL,
    date_of_birth             DATE          NULL,
    country_of_citizenship    NVARCHAR(100) NULL,
    current_club_id           INT           NULL,
    current_market_value_eur  DECIMAL(18,2) NULL,
    highest_market_value_eur  DECIMAL(18,2) NULL
);

WITH p AS (
    SELECT *,
           ROW_NUMBER() OVER (PARTITION BY TRY_CAST(player_id AS INT) ORDER BY (SELECT NULL)) AS rn
    FROM stg.players
    WHERE TRY_CAST(player_id AS INT) IS NOT NULL
)
INSERT INTO dw.dim_player
SELECT TRY_CAST(player_id AS INT),
       COALESCE(NULLIF(LTRIM(RTRIM(name)), N''), CONCAT(N'Player ', player_id)),
       position,
       sub_position,
       TRY_CONVERT(DATE, LEFT(date_of_birth, 10), 23),
       country_of_citizenship,
       TRY_CAST(TRY_CAST(current_club_id AS FLOAT) AS INT),
       TRY_CAST(TRY_CAST(market_value_in_eur AS FLOAT) AS DECIMAL(18,2)),
       TRY_CAST(TRY_CAST(highest_market_value_in_eur AS FLOAT) AS DECIMAL(18,2))
FROM p
WHERE rn = 1;
GO

/* =====================================================================
   FACTS
   ===================================================================== */

/* ---------- fact_match: one row per league match ---------- */
CREATE TABLE dw.fact_match (
    game_id            INT          NOT NULL CONSTRAINT PK_fact_match PRIMARY KEY,
    competition_id     VARCHAR(10)  NOT NULL CONSTRAINT FK_match_competition REFERENCES dw.dim_competition (competition_id),
    season_start_year  SMALLINT     NOT NULL CONSTRAINT FK_match_season      REFERENCES dw.dim_season (season_start_year),
    matchday           NVARCHAR(50) NULL,
    match_date         DATE         NULL,
    home_club_id       INT          NOT NULL CONSTRAINT FK_match_home_club   REFERENCES dw.dim_club (club_id),
    away_club_id       INT          NOT NULL CONSTRAINT FK_match_away_club   REFERENCES dw.dim_club (club_id),
    home_goals         TINYINT      NULL,  -- NULL = not played (postponed/abandoned)
    away_goals         TINYINT      NULL,
    attendance         INT          NULL
);

WITH g AS (
    SELECT TRY_CAST(g.game_id AS INT)                         AS game_id,
           g.competition_id,
           TRY_CAST(g.season AS SMALLINT)                     AS season_start_year,
           g.[round]                                          AS matchday,
           TRY_CONVERT(DATE, LEFT(g.[date], 10), 23)          AS match_date,
           TRY_CAST(g.home_club_id AS INT)                    AS home_club_id,
           TRY_CAST(g.away_club_id AS INT)                    AS away_club_id,
           TRY_CAST(TRY_CAST(g.home_club_goals AS FLOAT) AS TINYINT) AS home_goals,
           TRY_CAST(TRY_CAST(g.away_club_goals AS FLOAT) AS TINYINT) AS away_goals,
           TRY_CAST(TRY_CAST(g.attendance AS FLOAT) AS INT)   AS attendance,
           ROW_NUMBER() OVER (PARTITION BY TRY_CAST(g.game_id AS INT) ORDER BY (SELECT NULL)) AS rn
    FROM stg.games g
    JOIN dw.dim_competition c ON c.competition_id = g.competition_id
    JOIN dw.dim_season s      ON s.season_start_year = TRY_CAST(g.season AS SMALLINT)
)
INSERT INTO dw.fact_match
SELECT game_id, competition_id, season_start_year, matchday, match_date,
       home_club_id, away_club_id, home_goals, away_goals, attendance
FROM g
WHERE rn = 1
  AND game_id IS NOT NULL
  AND home_club_id IS NOT NULL
  AND away_club_id IS NOT NULL;
GO

/* ---------- fact_club_match: two rows per played match (one per club) ----------
   This is the table league tables and points-per-season are built from. */
CREATE TABLE dw.fact_club_match (
    game_id        INT     NOT NULL CONSTRAINT FK_clubmatch_match    REFERENCES dw.fact_match (game_id),
    club_id        INT     NOT NULL CONSTRAINT FK_clubmatch_club     REFERENCES dw.dim_club (club_id),
    opponent_id    INT     NOT NULL CONSTRAINT FK_clubmatch_opponent REFERENCES dw.dim_club (club_id),
    is_home        BIT     NOT NULL,
    goals_for      TINYINT NOT NULL,
    goals_against  TINYINT NOT NULL,
    result         CHAR(1) NOT NULL CONSTRAINT CK_clubmatch_result CHECK (result IN ('W', 'D', 'L')),
    points         TINYINT NOT NULL,
    CONSTRAINT PK_fact_club_match PRIMARY KEY (game_id, club_id)
);

INSERT INTO dw.fact_club_match
SELECT m.game_id,
       v.club_id,
       v.opponent_id,
       v.is_home,
       v.goals_for,
       v.goals_against,
       CASE WHEN v.goals_for > v.goals_against THEN 'W'
            WHEN v.goals_for = v.goals_against THEN 'D'
            ELSE 'L' END,
       CASE WHEN v.goals_for > v.goals_against THEN 3
            WHEN v.goals_for = v.goals_against THEN 1
            ELSE 0 END
FROM dw.fact_match m
CROSS APPLY (VALUES
    (m.home_club_id, m.away_club_id, CAST(1 AS BIT), m.home_goals, m.away_goals),
    (m.away_club_id, m.home_club_id, CAST(0 AS BIT), m.away_goals, m.home_goals)
) AS v (club_id, opponent_id, is_home, goals_for, goals_against)
WHERE m.home_goals IS NOT NULL
  AND m.away_goals IS NOT NULL;
GO

/* ---------- fact_player_valuation: market value history ----------
   Starts a year before the first season so every signing has a
   "value at time of purchase" to compare against. */
CREATE TABLE dw.fact_player_valuation (
    player_id         INT           NOT NULL CONSTRAINT FK_valuation_player REFERENCES dw.dim_player (player_id),
    valuation_date    DATE          NOT NULL,
    market_value_eur  DECIMAL(18,2) NOT NULL,
    club_id           INT           NULL,  -- club at the time; may be outside the top 5
    CONSTRAINT PK_fact_player_valuation PRIMARY KEY (player_id, valuation_date)
);

WITH v AS (
    SELECT TRY_CAST(pv.player_id AS INT)                                AS player_id,
           TRY_CONVERT(DATE, LEFT(pv.[date], 10), 23)                   AS valuation_date,
           TRY_CAST(TRY_CAST(pv.market_value_in_eur AS FLOAT) AS DECIMAL(18,2)) AS market_value_eur,
           TRY_CAST(TRY_CAST(pv.current_club_id AS FLOAT) AS INT)       AS club_id
    FROM stg.player_valuations pv
),
v_dedup AS (
    SELECT *, ROW_NUMBER() OVER (PARTITION BY player_id, valuation_date
                                 ORDER BY market_value_eur DESC) AS rn
    FROM v
    WHERE player_id IS NOT NULL
      AND valuation_date IS NOT NULL
      AND market_value_eur IS NOT NULL
      AND valuation_date >= (SELECT DATEADD(YEAR, -1, MIN(window_start)) FROM dw.dim_season)
      AND valuation_date <= (SELECT MAX(window_end) FROM dw.dim_season)
)
INSERT INTO dw.fact_player_valuation
SELECT d.player_id, d.valuation_date, d.market_value_eur, d.club_id
FROM v_dedup d
JOIN dw.dim_player p ON p.player_id = d.player_id
WHERE d.rn = 1;
GO

/* ---------- fact_transfer: every move in or out of an in-scope club ----------
   from/to clubs have no foreign key on purpose: the other side of a deal
   is often a club outside the top 5 (e.g. Benfica selling to Liverpool). */
CREATE TABLE dw.fact_transfer (
    transfer_key                  INT IDENTITY(1,1) NOT NULL CONSTRAINT PK_fact_transfer PRIMARY KEY,
    player_id                     INT           NOT NULL CONSTRAINT FK_transfer_player REFERENCES dw.dim_player (player_id),
    transfer_date                 DATE          NOT NULL,
    season_start_year             SMALLINT      NOT NULL CONSTRAINT FK_transfer_season REFERENCES dw.dim_season (season_start_year),
    from_club_id                  INT           NULL,
    from_club_name                NVARCHAR(200) NULL,
    to_club_id                    INT           NULL,
    to_club_name                  NVARCHAR(200) NULL,
    fee_eur                       DECIMAL(18,2) NULL,
    market_value_at_transfer_eur  DECIMAL(18,2) NULL,
    fee_category                  VARCHAR(30)   NOT NULL,  -- see CASE below
    is_top5_buyer                 BIT           NOT NULL,  -- to_club is in dim_club
    is_top5_seller                BIT           NOT NULL   -- from_club is in dim_club
);

WITH t AS (
    SELECT TRY_CAST(tr.player_id AS INT)                                AS player_id,
           TRY_CONVERT(DATE, LEFT(tr.transfer_date, 10), 23)            AS transfer_date,
           TRY_CAST(TRY_CAST(tr.from_club_id AS FLOAT) AS INT)          AS from_club_id,
           tr.from_club_name,
           TRY_CAST(TRY_CAST(tr.to_club_id AS FLOAT) AS INT)            AS to_club_id,
           tr.to_club_name,
           TRY_CAST(TRY_CAST(tr.transfer_fee AS FLOAT) AS DECIMAL(18,2))        AS fee_eur,
           TRY_CAST(TRY_CAST(tr.market_value_in_eur AS FLOAT) AS DECIMAL(18,2)) AS mv_eur
    FROM stg.transfers tr
),
t_dedup AS (
    SELECT *, ROW_NUMBER() OVER (PARTITION BY player_id, transfer_date, from_club_id, to_club_id
                                 ORDER BY fee_eur DESC) AS rn
    FROM t
    WHERE player_id IS NOT NULL AND transfer_date IS NOT NULL
)
INSERT INTO dw.fact_transfer (
    player_id, transfer_date, season_start_year, from_club_id, from_club_name,
    to_club_id, to_club_name, fee_eur, market_value_at_transfer_eur,
    fee_category, is_top5_buyer, is_top5_seller)
SELECT d.player_id,
       d.transfer_date,
       s.season_start_year,
       d.from_club_id, d.from_club_name,
       d.to_club_id,   d.to_club_name,
       d.fee_eur,
       d.mv_eur,
       CASE WHEN d.fee_eur IS NULL THEN 'Unknown fee'
            WHEN d.fee_eur = 0     THEN 'Zero fee (free/loan/return)'
            ELSE 'Paid fee' END,
       CASE WHEN buyer.club_id  IS NOT NULL THEN 1 ELSE 0 END,
       CASE WHEN seller.club_id IS NOT NULL THEN 1 ELSE 0 END
FROM t_dedup d
JOIN dw.dim_season s  ON d.transfer_date BETWEEN s.window_start AND s.window_end
JOIN dw.dim_player p  ON p.player_id = d.player_id
LEFT JOIN dw.dim_club buyer  ON buyer.club_id  = d.to_club_id
LEFT JOIN dw.dim_club seller ON seller.club_id = d.from_club_id
WHERE d.rn = 1
  AND (buyer.club_id IS NOT NULL OR seller.club_id IS NOT NULL);
GO

/* ---------- fact_appearance: player minutes in in-scope league matches ----------
   Lets you test whether expensive signings actually played. */
CREATE TABLE dw.fact_appearance (
    appearance_id   VARCHAR(50) NOT NULL CONSTRAINT PK_fact_appearance PRIMARY KEY,
    game_id         INT         NOT NULL CONSTRAINT FK_appearance_match  REFERENCES dw.fact_match (game_id),
    player_id       INT         NOT NULL CONSTRAINT FK_appearance_player REFERENCES dw.dim_player (player_id),
    club_id         INT         NOT NULL CONSTRAINT FK_appearance_club   REFERENCES dw.dim_club (club_id),
    minutes_played  SMALLINT    NULL,
    goals           TINYINT     NULL,
    assists         TINYINT     NULL,
    yellow_cards    TINYINT     NULL,
    red_cards       TINYINT     NULL
);

WITH a AS (
    SELECT ap.appearance_id,
           TRY_CAST(ap.game_id AS INT)                                  AS game_id,
           TRY_CAST(ap.player_id AS INT)                                AS player_id,
           TRY_CAST(TRY_CAST(ap.player_club_id AS FLOAT) AS INT)        AS club_id,
           TRY_CAST(TRY_CAST(ap.minutes_played AS FLOAT) AS SMALLINT)   AS minutes_played,
           TRY_CAST(TRY_CAST(ap.goals AS FLOAT) AS TINYINT)             AS goals,
           TRY_CAST(TRY_CAST(ap.assists AS FLOAT) AS TINYINT)           AS assists,
           TRY_CAST(TRY_CAST(ap.yellow_cards AS FLOAT) AS TINYINT)      AS yellow_cards,
           TRY_CAST(TRY_CAST(ap.red_cards AS FLOAT) AS TINYINT)         AS red_cards,
           ROW_NUMBER() OVER (PARTITION BY ap.appearance_id ORDER BY (SELECT NULL)) AS rn
    FROM stg.appearances ap
)
INSERT INTO dw.fact_appearance
SELECT a.appearance_id, a.game_id, a.player_id, a.club_id,
       a.minutes_played, a.goals, a.assists, a.yellow_cards, a.red_cards
FROM a
JOIN dw.fact_match m ON m.game_id   = a.game_id
JOIN dw.dim_player p ON p.player_id = a.player_id
JOIN dw.dim_club   c ON c.club_id   = a.club_id
WHERE a.rn = 1
  AND a.appearance_id IS NOT NULL;
GO

/* =====================================================================
   INDEXES for the joins Week 2 and Power BI will lean on
   ===================================================================== */
CREATE INDEX IX_fact_match_season_comp   ON dw.fact_match (season_start_year, competition_id);
CREATE INDEX IX_fact_club_match_club     ON dw.fact_club_match (club_id) INCLUDE (points, goals_for, goals_against);
CREATE INDEX IX_fact_transfer_buyer      ON dw.fact_transfer (to_club_id, season_start_year) INCLUDE (fee_eur);
CREATE INDEX IX_fact_transfer_seller     ON dw.fact_transfer (from_club_id, season_start_year) INCLUDE (fee_eur);
CREATE INDEX IX_fact_appearance_player   ON dw.fact_appearance (player_id, club_id) INCLUDE (minutes_played);
GO

/* ---------- summary ---------- */
SELECT 'dim_competition'       AS table_name, COUNT(*) AS row_count FROM dw.dim_competition       UNION ALL
SELECT 'dim_season',                          COUNT(*)              FROM dw.dim_season            UNION ALL
SELECT 'dim_club',                            COUNT(*)              FROM dw.dim_club              UNION ALL
SELECT 'dim_player',                          COUNT(*)              FROM dw.dim_player            UNION ALL
SELECT 'fact_match',                          COUNT(*)              FROM dw.fact_match            UNION ALL
SELECT 'fact_club_match',                     COUNT(*)              FROM dw.fact_club_match       UNION ALL
SELECT 'fact_player_valuation',               COUNT(*)              FROM dw.fact_player_valuation UNION ALL
SELECT 'fact_transfer',                       COUNT(*)              FROM dw.fact_transfer         UNION ALL
SELECT 'fact_appearance',                     COUNT(*)              FROM dw.fact_appearance;
