# Data Quality Log

Results of `sql/04_data_quality_checks.sql`, with what each one means for the analysis.

**Dataset version:** downloaded from Kaggle on 2026-10-25 (the dataset refreshes weekly, so record the date)
**Pipeline run:** 2026-10-25, SQL Server 2022 Express, Python 3.13

| # | Check | Result | Action / decision |
|---|---|---|---|
| 1 | Rows kept, staging → warehouse | games 88,958 → 10,734 · transfers 175,165 → 17,913 · valuations 656,301 → 355,765 · appearances 1,894,350 → 326,283 · players 50,149 → 50,149 | Drops are the scope filter (5 leagues, 2020/21–2025/26, valuations from July 2019), not lost data. Players are kept in full because transfers and valuations reference them. |
| 2 | All 5 league codes present | GB1, ES1, IT1, L1, FR1 all found | None needed. |
| 3 | League-seasons complete | 30 of 30 complete, 0 matches without a score. 10,734 matches = 380 × 21 + 306 × 9 (306-match seasons: Bundesliga all 6, Ligue 1 from 2023/24) | None needed. Points per season can be compared across every club-season. |
| 4 | Clubs with wrong games played | 0 rows: every club played 38 (or 34) games | None needed. |
| 5 | Share of incoming deals with a known paid fee | Paid 19.7% (2020/21) rising to 28.3% (2025/26). Unknown 10.9–12.6%. Zero (free/loan/return) 59.5–68.7%. Paid fees total €3.59bn (2020/21) to €7.56bn (2025/26) | The main caveat. Spend figures cover paid fees only; every spend chart and table will state that coverage. Unknown fees are excluded, not counted as zero. |
| 6 | Top 15 fees look right | Led by Isak (€145m, Newcastle → Liverpool), Bellingham (€127m), Wirtz (€125m), Enzo Fernández (€121m), Grealish (€117.5m). All recognisable, fees in euros | None needed: units and season mapping are correct. Neymar to Al-Hilal appears because the seller (PSG) is in scope; outgoing deals count towards net spend. |
| 7 | Implausible values | 0 in all 6 checks (fee > €250m, negative fee, minutes > 130, missing match date, match date outside season, same-club transfer) | None needed. |
| 8 | Rows dropped during typing | 0 unreadable transfer dates, 0 transfers with an unknown player, 0 unreadable valuations, 0 duplicate appearance IDs | None needed: the source is clean enough that `TRY_CAST` dropped nothing. |
| 9 | Date coverage | Matches 2020-08-21 to 2026-05-24 · transfers 2020-07-01 to 2026-06-30 | Matches the scope: 2025/26 is complete, 2026/27 is excluded. |

## Known limitations
- Transfermarkt fees are reported or estimated figures, not audited club accounts.
- Loans, free transfers and loan returns are all recorded as €0, so "net spend" covers paid fees only.
- About 1 in 9 incoming deals has an unknown fee; these are left out of spend totals, so spend is a lower bound.
- Add-ons and installments aren't separated from headline fees.
- Wages are not in the dataset, so this measures transfer spend, not total squad cost.
