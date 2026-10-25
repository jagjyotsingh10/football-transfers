# Data Quality Log

Results of `sql/04_data_quality_checks.sql`, with what each one means for the analysis.

**Dataset version:** downloaded from Kaggle on 2026-10-25 (the dataset refreshes weekly, so record the date)
**Pipeline run:** 2026-10-25, SQL Server 2022 Express, Python 3.13

| # | Check | Result | Action / decision |
|---|---|---|---|
| 1 | Rows kept, staging → warehouse | games 88,958 → 10,734 · transfers 175,165 → 17,913 · valuations 656,301 → 116,243 · appearances 1,894,350 → 326,283 · players 50,149 → 10,515 | Drops are the scope filter (5 leagues, 2020/21–2025/26, valuations from July 2019), not lost data. Players are limited to those linked to a top 5 club (valued at one, moved to or from one, or played for one); their full valuation history is kept so pre-move values are available. |
| 2 | All 5 league codes present | GB1, ES1, IT1, L1, FR1 all found | None needed. |
| 3 | League-seasons complete | 30 of 30 complete, 0 matches without a score. 10,734 matches = 380 × 21 + 306 × 9 (306-match seasons: Bundesliga all 6, Ligue 1 from 2023/24) | None needed. Points per season can be compared across every club-season. |
| 4 | Clubs with wrong games played | 0 rows: every club played 38 (or 34) games | None needed. |
| 5 | Share of incoming deals with a known paid fee | Paid 19.7% (2020/21) rising to 28.3% (2025/26). Unknown 10.9–12.6%. Zero (free/loan/return) 59.5–68.7%. Paid fees total €3.59bn (2020/21) to €7.56bn (2025/26) | The main caveat. Spend figures cover paid fees only; every spend chart and table will state that coverage. Unknown fees are excluded, not counted as zero. |
| 6 | Top 15 fees look right | Led by Isak (€145m, Newcastle → Liverpool), Bellingham (€127m), Wirtz (€125m), Enzo Fernández (€121m), Grealish (€117.5m). All recognisable, fees in euros | None needed: units and season mapping are correct. Neymar to Al-Hilal appears because the seller (PSG) is in scope; outgoing deals count towards net spend. |
| 7 | Implausible values | 0 in all 6 checks (fee > €250m, negative fee, minutes > 130, missing match date, match date outside season, same-club transfer) | None needed. |
| 8 | Rows dropped during typing | 0 unreadable transfer dates, 0 transfers with an unknown player, 0 unreadable valuations, 0 duplicate appearance IDs | None needed: the source is clean enough that `TRY_CAST` dropped nothing. |
| 9 | Date coverage | Matches 2020-08-21 to 2026-05-24 · transfers 2020-07-01 to 2026-06-30 | Matches the scope: 2025/26 is complete, 2026/27 is excluded. |

## Found while building the portfolio model (step 5)

| Issue | Evidence | Decision |
|---|---|---|
| Valuation coverage drops in 2024 | Players valued while at a top 5 club: 6,711 in 2023, 3,571 in 2024, 3,368 in 2025. The cheapest valued player rose from €10k to €50k | The source stopped valuing most reserve and youth players. First-team coverage held: 99–100% of players with 450+ league minutes are valued in every season except 2024/25 (95.6%). A portfolio is the club's 25 most valuable players, which hold 96–98% of squad value in every year |
| Valuations lag transfers | Isak's latest valuation on 1 Sept 2022 still showed Real Sociedad, a week after his move to Newcastle | A player's club at a snapshot is whichever came last: his latest transfer or his latest valuation |
| Thin squads after relegation | 10 portfolios in June 2025 and 3 in June 2026 have under 20 valued players (e.g. Montpellier, Las Palmas: 13) | Kept, flagged `is_thin_squad` so they can be filtered out |
| Tiny bases distort growth rates | Como's June 2020 portfolio (Serie C) is under €1m, giving +210%/yr | Growth since 2020 is only calculated for clubs in the top 5 in 2020/21 |
| % changes explode for cheap players | A €0.2m player revalued at €5m is +2,400%; plain % volatility put Wolves at 349% | Volatility uses log changes |
| Identical Q8 price-band counts | 1,505 deals above 110% of value and 1,505 below 90% | Recounted independently: genuine. 224 deals were priced exactly at market value |

## Known limitations
- Transfermarkt fees are reported or estimated figures, not audited club accounts.
- Loans, free transfers and loan returns are all recorded as €0, so "net spend" covers paid fees only.
- About 1 in 9 incoming deals has an unknown fee; these are left out of spend totals, so spend is a lower bound.
- Add-ons and installments aren't separated from headline fees.
- Wages are not in the dataset, so this measures transfer spend and asset value, not total squad cost.
- Loanees count for the club they play for: the source can't tell a loan from a free transfer, so owned players can't be separated from the squad.
