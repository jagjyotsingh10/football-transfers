# Football Transfer ROI: Does Transfer Spending Buy Results?

**Business question:** Across Europe's top 5 leagues (2020/21 to 2025/26), which clubs turn transfer spending into league points efficiently, and which overspend?

**Stack:** SQL Server (data model and analysis), Python (data load), Power BI (dashboard)
**Data:** [Football Data from Transfermarkt](https://www.kaggle.com/datasets/davidcariboo/player-scores) on Kaggle

> This README covers Week 1 (setup). Findings, dashboard screenshots and recommendations get added in Weeks 2–4.

---

## Week 1 setup (Windows)

### 1. Install the tools (free)
- **SQL Server 2022 Express** (choose "Basic" install). Note the instance name it shows, usually `localhost\SQLEXPRESS`.
- **SQL Server Management Studio (SSMS)**
- **ODBC Driver 18 for SQL Server** (often installed with SSMS already)
- **Python 3.10–3.13** (pyodbc has no prebuilt package for 3.15 yet; with the Python install manager, `py install 3.13`), then in the project folder:
  ```
  py -V:3.13 -m venv .venv
  .venv\Scripts\python.exe -m pip install -r requirements.txt
  ```

### 2. Download the data
Download the dataset from Kaggle (Download button, top right) and unzip it into a folder such as `C:\data\player-scores`. You need these files from it: `competitions`, `clubs`, `games`, `players`, `player_valuations`, `transfers`, `appearances` (`.csv` or `.csv.gz` both work). The CSVs are kept out of the repo because the dataset is large and updates weekly.

### 3. Run the scripts in order

| Step | File | Run it in | What it does |
|---|---|---|---|
| 1 | `sql/01_create_database.sql` | SSMS | Creates the `FootballTransferROI` database with `stg` (raw) and `dw` (clean) schemas |
| 2 | `python/02_load_staging.py` | Terminal | Loads the CSVs into `stg` as raw text, matched by column name; checks row counts |
| 3 | `sql/03_build_warehouse.sql` | SSMS | Builds the typed star schema in `dw` with primary and foreign keys |
| 4 | `sql/04_data_quality_checks.sql` | SSMS | Runs 9 checks on completeness, fee reliability and implausible values |

Step 2 command:
```
.venv\Scripts\python.exe python/02_load_staging.py --data-dir "C:\data\player-scores"
```
If your instance has a different name, add `--server "YOURPC\SQLEXPRESS"`. If you have the older driver, add `--driver "ODBC Driver 17 for SQL Server"`. The appearances file is the biggest, so expect a few minutes.

---

## Data model

Relationships (foreign keys):
```
fact_match            → dim_competition, dim_season, dim_club (home), dim_club (away)
fact_club_match       → fact_match, dim_club (club), dim_club (opponent)
fact_appearance       → fact_match, dim_player, dim_club
fact_player_valuation → dim_player
fact_transfer         → dim_player, dim_season
                        (buyer/seller clubs flagged, not keyed: the other side
                         of a deal is often a club outside the top 5)
```

| Table | Grain | Purpose |
|---|---|---|
| `dim_competition` | league | Premier League, LaLiga, Serie A, Bundesliga, Ligue 1 |
| `dim_season` | season | 2020/21–2025/26, with 1 July–30 June windows |
| `dim_club` | club | Every club that played an in-scope league match |
| `dim_player` | player | Profile and current/peak market value |
| `fact_match` | match | Scores, date, attendance |
| `fact_club_match` | club × match | Result and points, the basis for league tables |
| `fact_transfer` | transfer | Fee, market value at transfer, fee category |
| `fact_player_valuation` | player × date | Market value history (from a year before 2020/21) |
| `fact_appearance` | player × match | Minutes, goals, assists, cards |

---

## Design decisions

1. **Raw and clean data are separate.** Everything lands in `stg` as text, and typing happens in SQL with `TRY_CAST`, so bad values become NULLs that the quality checks can count instead of crashing the load.
2. **Seasons run 1 July to 30 June**, so the summer and January windows both count toward the season they affect.
3. **2026/27 is excluded**: it's in progress, and a partial season would distort points-per-euro comparisons.
4. **Clubs come from match data, not the clubs file.** The clubs file only records each club's *current* league, so relegated clubs would otherwise disappear.
5. **Points are calculated from raw scores** (3 for a win, 1 for a draw) rather than taken from a pre-built table.
6. **Fees are split into three categories.** The source records free transfers, loans and loan returns all as €0, and unknown fees as blank. `fee_category` keeps "paid", "zero" and "unknown" apart so spend totals can state their coverage honestly.

## Data quality log
See `docs/data_quality_log.md`. All 9 checks passed on the 2026-10-25 download: every league-season is complete and nothing was dropped during typing. The main caveat is fee coverage: only 20–28% of incoming deals per season have a known paid fee, so spend figures are paid fees only and state their coverage.

---

## Roadmap
- [x] **Week 1:** Database, load pipeline, star schema, data quality checks
- [ ] **Week 2:** SQL analysis: league tables from raw results, net spend per club-season, cost per point, signing value change, minutes played by expensive signings; reporting views for Power BI
- [ ] **Week 3:** Power BI: league overview, spend vs. performance, club drill-through
- [ ] **Week 4:** Findings, recommendations, screenshots, walkthrough
