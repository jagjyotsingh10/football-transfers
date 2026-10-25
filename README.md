# Football Squads as Asset Portfolios

**Business question:** Treating each club's squad as a portfolio of player assets, how have value, risk and growth changed across Europe's top 5 leagues from 2020 to 2026, and which clubs buy, hold and sell assets well?

**Stack:** SQL Server (data model and analysis), Python (data load), Power BI (dashboard)
**Data:** [Football Data from Transfermarkt](https://www.kaggle.com/datasets/davidcariboo/player-scores) on Kaggle, top 5 leagues only

**Answers to all 11 questions: [`docs/findings.md`](docs/findings.md)**

| # | Question | Headline |
|---|---|---|
| 1 | How has each club's portfolio value changed over time? | Top 5 value up 38% to €32.6bn; Premier League +71% |
| 2 | Which clubs have the highest concentration risk? | Levante: 71.8% of value in its top 5 players |
| 3 | Which acquisitions appreciated most after joining? | Vitinha at PSG: €30m to €140m |
| 4 | Which clubs are most exposed to declining values? | About a third of all value is in declining players; Athletic Bilbao 79% |
| 5 | How do clubs compare on value, growth, composition? | PSG €1.40bn, Man City €1.35bn, Arsenal €1.28bn |
| 6 | How does age profile relate to value and growth? | Weak link (r = -0.16); the top 5 is getting younger |
| 7 | Which clubs have the biggest fees paid vs received gap? | Chelsea +€1.01bn net; Lille -€310m |
| 8 | How do fees compare with market value at transfer? | Only 15.6% of deals within 10% of value |
| 9 | How volatile are valuations? | About 30% per revaluation; Arsenal's portfolio is the steadiest |
| 10 | Which clubs have the highest average asset value? | PSG €55.8m per player, 5.4× the Ligue 1 average |
| 11 | Does portfolio value buy league points? | Largely: value explains 60% of points per game; the most valuable squad won 19 of 30 titles |

---

## Setup (Windows)

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
| 3 | `sql/03_build_warehouse.sql` | SSMS | Builds the typed star schema in `dw`, limited to the top 5 leagues |
| 4 | `sql/04_data_quality_checks.sql` | SSMS | Runs 9 checks on completeness, fee reliability and implausible values |
| 5 | `sql/05_portfolio_model.sql` | SSMS | Builds the portfolio snapshots and the `rpt` reporting views Power BI uses |
| 6 | `sql/06_portfolio_questions.sql` | SSMS | Answers the 11 questions |
| 7 | `powerbi/build_pbip.py` | Terminal | Generates the Power BI project from the `rpt` views (only needed after changing views or pages) |
| 8 | `powerbi/FootballPortfolio.pbip` | Power BI Desktop | Open, then Home → Refresh. `powerbi/check_model.ps1` compares its numbers with SQL |

Re-running step 3 drops step 5's tables (they depend on it), so run step 5 again afterwards.

Step 2 command:
```
.venv\Scripts\python.exe python/02_load_staging.py --data-dir "C:\data\player-scores"
```
If your instance has a different name, add `--server "YOURPC\SQLEXPRESS"`. If you have the older driver, add `--driver "ODBC Driver 17 for SQL Server"`. The appearances file is the biggest, so expect a few minutes.

---

## Data model

Relationships (foreign keys):
```
fact_match              → dim_competition, dim_season, dim_club (home), dim_club (away)
fact_club_match         → fact_match, dim_club (club), dim_club (opponent)
fact_appearance         → fact_match, dim_player, dim_club
fact_player_valuation   → dim_player
fact_transfer           → dim_player, dim_season
                          (buyer/seller clubs flagged, not keyed: the other side
                           of a deal is often a club outside the top 5)
fact_portfolio_snapshot → dim_snapshot, dim_player, dim_club
```

| Table | Grain | Purpose |
|---|---|---|
| `dim_competition` | league | Premier League, LaLiga, Serie A, Bundesliga, Ligue 1 |
| `dim_season` | season | 2020/21–2025/26, with 1 July–30 June windows |
| `dim_snapshot` | snapshot date | Season end (30 June 2020–2026) and season start (1 September 2020–2025) |
| `dim_club` | club | Every club that played an in-scope league match |
| `dim_player` | player | Players linked to a top 5 club (10,515 of 50,149 in the source) |
| `fact_match` | match | Scores, date, attendance, official league position after the match |
| `fact_club_match` | club × match | Result and points, the basis for league tables |
| `fact_transfer` | transfer | Fee, market value at transfer, fee category |
| `fact_player_valuation` | player × date | Market value history (from a year before 2020/21) |
| `fact_appearance` | player × match | Minutes, goals, assists, cards |
| `fact_portfolio_snapshot` | player × snapshot | Each player's club, value, value a year earlier and age at each snapshot |

Reporting views (`rpt` schema, for Power BI): `vw_league_table`, `vw_value_vs_points`, `vw_club_portfolio`, `vw_portfolio_player`, `vw_portfolio_composition`, `vw_club_kpis`, `vw_club_volatility`, `vw_player_volatility`, `vw_signing_appreciation`, `vw_fee_vs_value`, `vw_club_transfer_balance`, plus `vw_dim_club`, `vw_dim_competition`, `vw_dim_snapshot`.

---

## Dashboard (Power BI)

`powerbi/FootballPortfolio.pbip` is a Power BI Project: the model (TMDL) and report pages (PBIR JSON) are plain text, generated by `powerbi/build_pbip.py`, so every change is reviewable in git. It imports the `rpt` views from SQL Server.

| Page | Questions | What it shows |
|---|---|---|
| Overview | Q1, Q5 | Headline cards, total value by league over time, most valuable portfolios |
| Club benchmark | Q5, Q6, Q10 | Benchmark table, age vs value, value share by age band, average value per player |
| Risk | Q2, Q4, Q9 | Top-5 concentration, declining exposure over time and by club, volatility |
| Transfers | Q3, Q7, Q8 | Biggest value gains after signing, net spend, fee vs market value |
| Value vs points | Q11 | Title and top-4 rates, value vs points per game, points by value rank, over/underperformers |

Every page has a league slicer. The model has 10 tables, 16 relationships and 27 DAX measures; `check_model.ps1` confirmed 9 of 9 headline numbers match SQL exactly.

---

## Design decisions

1. **Raw and clean data are separate.** Everything lands in `stg` as text, and typing happens in SQL with `TRY_CAST`, so bad values become NULLs that the quality checks can count instead of crashing the load.
2. **Top 5 leagues only.** Clubs come from top 5 league matches, and players are limited to those linked to a top 5 club, keeping the warehouse to about a fifth of the source.
3. **Seasons run 1 July to 30 June**, so the summer and January windows both count toward the season they affect. 2026/27 is excluded because it is in progress.
4. **Clubs come from match data, not the clubs file.** The clubs file only records each club's *current* league, so relegated clubs would otherwise disappear.
5. **Portfolios are valued every 30 June**, the end of each season and most clubs' financial year-end.
6. **A player's club is whichever came last: his latest transfer or his latest valuation.** Valuations come every few months, so on their own they lag behind transfers.
7. **A portfolio is the club's 25 most valuable players.** The source stopped valuing most reserve and youth players in 2024; the top 25 hold 96–98% of value in every year, so squads stay comparable.
8. **Fees are split into three categories.** The source records free transfers, loans and loan returns all as €0, and unknown fees as blank. `fee_category` keeps "paid", "zero" and "unknown" apart so spend totals can state their coverage honestly.
9. **Volatility uses log changes**, so cheap players' huge percentage jumps don't swamp the measure.
10. **Points are compared with season-start value (1 September), not season-end.** End-of-season values rise because a team did well, which would make value look more predictive than it is.
11. **Points are calculated from raw scores** (3 for a win, 1 for a draw), so point deductions are excluded. The tables are checked against the source's official positions.

## Data quality log
See `docs/data_quality_log.md`. All 9 checks passed on the 2026-10-25 download: every league-season is complete and nothing was dropped during typing. The main caveats are fee coverage (only 20–28% of incoming deals per season have a known paid fee) and the 2024 drop in valuation coverage, handled by the 25-player portfolio.

---

## Roadmap
- [x] **Week 1:** Database, load pipeline, star schema, data quality checks
- [x] **Week 2:** Portfolio model, league tables, reporting views, answers to the 11 questions
- [x] **Week 3:** Power BI: 5 pages (overview, club benchmark, risk, transfers, value vs points), model verified against SQL
- [ ] **Week 3 polish:** visual review, screenshots
- [ ] **Week 4:** Recommendations, screenshots, walkthrough
