# Findings: club squads as asset portfolios

Top 5 European leagues, 30 June 2020 to 30 June 2026. Source queries: `sql/06_portfolio_questions.sql`.
Data: Transfermarkt via Kaggle, downloaded 2026-10-25. Market values are Transfermarkt estimates, not audited accounts.

**How a portfolio is defined.** At each 30 June (and each 1 September, for Q11), a club's portfolio is its 25 most valuable players, valued at their latest
Transfermarkt valuation in the previous 12 months. A player's club is whichever came last: his latest transfer or his latest
valuation. The 25-player cut keeps squads comparable across years: the source stopped valuing most reserve and youth players
in 2024, and the top 25 hold 96-98% of squad value in every year. "Latest" means 30 June 2026, the end of 2025/26.

---

## Q1. How has each club's portfolio value changed over time?

**Total top 5 portfolio value rose 38%, from €23.6bn (June 2020) to €32.6bn (June 2026).** The Premier League drove most of it.

| League | June 2020 | June 2026 | Change |
|---|---|---|---|
| Premier League | €7.4bn | €12.7bn | +71% |
| LaLiga | €4.8bn | €5.2bn | +9% |
| Serie A | €4.3bn | €5.2bn | +21% |
| Bundesliga | €4.1bn | €5.0bn | +22% |
| Ligue 1 | €2.9bn | €4.5bn | +55% |

- **Fastest growers** (compound annual growth, clubs in the top 5 in both 2020/21 and 2025/26): RC Lens +57.8%/yr (€17m to €264m), VfB Stuttgart +36.0%, RC Strasbourg +29.6%, FC Lorient +29.0%, Brighton +24.2%. Lens and Stuttgart had just been promoted in 2020, so they started from a small base.
- **Biggest decliners:** Valencia -17.5%/yr (€381m to €119m), Getafe -14.6%, Sevilla -10.1%, Borussia Mönchengladbach -9.6%, Napoli -6.0%.
- **Biggest one-season swings:** Arsenal +€356m in 2022/23; Inter Milan -€195m in 2021/22 (after selling Lukaku and Hakimi).

## Q2. Which clubs have the highest concentration risk?

**Smaller clubs carry the most concentration risk. At Levante, 71.8% of the portfolio's value sits in its five most valuable players.**

- Most concentrated (June 2026): Levante 71.8%, Nantes 67.7%, Angers 66.4%, Köln 66.2%, Elche 66.0%.
- Least concentrated: Tottenham 34.0%, Leeds 34.6%, AC Milan 35.3%, Brighton 35.9%.
- The Premier League is the least concentrated league and getting less so: the average club's top-5 share fell from 47.6% (2020) to 42.1% (2026). LaLiga is the most concentrated at 55.8%.
- Among elite clubs, Barcelona (52.7%) and Real Madrid (50.8%) are far more dependent on a few stars than Manchester City (38.2%) or Arsenal (37.5%).

## Q3. Which acquisitions appreciated most after joining?

**Vitinha is the biggest gain: valued at €30m when PSG signed him from Porto in 2022, €140m by 2026 (+€110m).**

| Player | Move | Value at signing | Latest value at club | Gain |
|---|---|---|---|---|
| Vitinha | Porto → PSG, 2022/23 | €30m | €140m | +€110m |
| Jude Bellingham | Birmingham → Dortmund, 2020/21 | €11m | €120m | +€109m |
| Michael Olise | Crystal Palace → Bayern, 2024/25 | €55m | €150m | +€95m |
| Alexander Isak | Real Sociedad → Newcastle, 2022/23 | €30m | €120m | +€90m |
| Désiré Doué | Rennes → PSG, 2024/25 | €30m | €120m | +€90m |

- Biggest percentage gains (valued at €5m+ when signed): Carlos Baleba at Brighton +1,000% (€5m to €55m), Bellingham +991%, Yann Bisseck at Inter +900%.
- **Cheap signings appreciate; expensive ones mostly don't.** Of signings valued under €10m, 54% gained value (median +20%). Of signings valued at €60m+, only 28% gained (median -32%).
- Measured on paid transfers only, from the value at signing to the latest valuation before the player's next move.

## Q4. Which clubs are most exposed to declining asset values?

**About a third of top 5 portfolio value is in players worth less than a year earlier. That share peaked at 43.5% in June 2022.**

- Exposure by year: 37.4% (2021), 43.5% (2022), 34.0% (2023), 33.3% (2024), 36.6% (2025), 35.5% (2026). Value lost by those players: €3.8bn to €4.9bn a year.
- Most exposed in June 2026: Athletic Bilbao 79.0%, Heidenheim 76.9%, Napoli 75.3%, Getafe 73.2%, Fiorentina 69.4%. In euros, the biggest losses were **Real Madrid** (€270.0m, 58.6% exposed) and **Liverpool** (€255.5m, 67.8%).
- Persistently exposed (average 2021-2026, clubs in all six seasons): Atlético Madrid 54.2%, Manchester United 53.6%, Liverpool 51.4%, Napoli 50.8%, Marseille 50.2%.
- Exposure = value of players worth less than 12 months earlier ÷ value of players who had a valuation 12 months earlier.

## Q5. How do clubs compare on value, growth and composition?

**PSG has the most valuable portfolio (€1.40bn), ahead of Manchester City (€1.35bn), Arsenal (€1.28bn) and Real Madrid (€1.24bn).**

| Club | Value | Growth/yr since 2020 | Top-5 share | Value-weighted age | Most value in |
|---|---|---|---|---|---|
| Paris Saint-Germain | €1,396m | +10.5% | 45.8% | 24.5 | Attack 37% |
| Manchester City | €1,347m | +5.9% | 38.2% | 25.5 | Defence 36% |
| Arsenal | €1,281m | +15.3% | 37.5% | 25.9 | Defence 35% |
| Real Madrid | €1,239m | +6.0% | 50.8% | 24.9 | Attack 42% |
| FC Barcelona | €1,137m | +5.7% | 52.7% | 23.7 | Midfield 37% |
| Chelsea | €1,131m | +8.8% | 39.8% | 24.0 | Defence 32% |
| Bayern Munich | €965m | +4.5% | 49.7% | 26.0 | Midfield 38% |
| Liverpool | €955m | +0.9% | 46.6% | 25.4 | Midfield 43% |

- The Premier League's average club is worth €634m, more than double any other league (€249m to €278m).
- The Premier League is also the most even: its richest club is worth 6.3× its poorest. In LaLiga that gap is 48.4×.

## Q6. How does age profile relate to value and growth?

**Younger portfolios are slightly more valuable and grow faster, but age explains little on its own.**

- Correlation between value-weighted age and portfolio value: -0.16. With next-season growth: -0.06. Both are weak.
- Grouped, the pattern is clearer. Portfolios with a value-weighted age under 24 grew 17.7% the following season on average, against 7.9% for those aged 25.5-27. Only 26 club-seasons fall in the under-24 group.
- **The top 5 is getting younger.** Players aged 29+ held 22.6% of portfolio value in 2020 and 12.6% in 2026. Under-21s rose from 6.7% to 10.5%.
- Youngest portfolios (June 2026): Angers 22.3, Strasbourg 22.5, Nantes 22.9. Oldest: Cremonese 29.4, Rayo Vallecano 29.1.

## Q7. Which clubs have the biggest gap between fees paid and received?

**Chelsea is the biggest net spender: €2.07bn paid, €1.06bn received, €1.01bn net over 2020/21-2025/26.**

| Net spenders | Net | | Net sellers | Net |
|---|---|---|---|---|
| Chelsea | +€1,010m | | Lille | -€310m |
| Manchester United | +€861m | | Eintracht Frankfurt | -€170m |
| Arsenal | +€841m | | Olympique Lyon | -€167m |
| Tottenham | +€740m | | Valencia | -€146m |
| Paris Saint-Germain | +€706m | | Real Sociedad | -€136m |

- Counts seasons the club spent in a top 5 league and paid fees only. About 1 in 9 incoming deals has an unknown fee, so these figures are lower bounds.
- The top 8 net spenders are all Premier League clubs or PSG.

## Q8. How does market value compare with the transfer fee?

**Fees and market values often disagree. 41.8% of deals went for more than 110% of market value, 41.8% for less than 90%, and only 15.6% within 10%.**

- Across the 3,572 paid deals involving top 5 clubs that have a market value, Premier League clubs pay the most above value: a fee-to-value ratio of 1.23 and a median premium of +23.9%. LaLiga (0.87, median -16.0%) and Bundesliga (0.89, median -11.1%) clubs buy below value.
- Biggest premiums: Enzo Fernández to Chelsea (€121m fee vs €55m value, +€66m), Antony to Manchester United (€95m vs €35m), Grealish to Manchester City (€117.5m vs €65m).
- Clubs paying most above value (10+ signings): Lorient 1.91×, Sheffield United 1.70×, Ipswich 1.64×, Newcastle 1.60×. Chelsea paid the largest total premium: €551m across 52 deals.

## Q9. How volatile are valuations, and which portfolios are most volatile?

**A typical player's value moves about 30% at each revaluation. Elite portfolios are the most stable.**

- Average volatility by position (3 years to June 2026): Attack 31.7%, Midfield 30.3%, Defence 29.4%, Goalkeeper 26.4%. Players worth €30m+ are steadier (23-28%).
- Most volatile portfolios (value-weighted): Angers 69.7%, Levante 51.6%, Strasbourg 50.3%, Como 47.5%. Angers and Strasbourg also have the two youngest portfolios (Q6).
- Least volatile: Arsenal 14.5%, Leeds 17.5%, Liverpool 17.7%, Manchester City 18.3%.
- Total portfolio value swung most at Lens (standard deviation of season-on-season change 138%) and Stuttgart (101%), both because of rapid growth.
- Volatility = standard deviation of the log change between consecutive valuations, ×100, over the 3 years up to each snapshot (at least 3 changes per player).

## Q10. Which clubs have the highest average asset value for their portfolio size?

**PSG's players are worth €55.8m each on average, 5.4× the Ligue 1 average. That is the biggest lead any club has over its league.**

- Highest average value (June 2026): PSG €55.8m, Manchester City €53.9m, Arsenal €51.2m, Real Madrid €49.6m, Barcelona €45.5m.
- Against their own league average (100 = average): PSG 541, Real Madrid 449, Barcelona 412, Bayern 344, Inter 266. Manchester City is only 211 because the Premier League average is so high (€25.5m, against €10.3m to €11.2m elsewhere).
- Against the whole top 5, PSG is at 401 and Manchester City at 387.

## Q11. Does portfolio value buy league points?

**Yes, largely. Portfolio value at the start of a season explains 60% of the variation in points per game, and the most valuable squad won the league in 19 of 30 league-seasons.**

| League | Rank correlation (value rank vs finish) | Variation in points explained (R²) |
|---|---|---|
| Serie A | 0.86 | 72% |
| Ligue 1 | 0.78 | 61% |
| LaLiga | 0.76 | 67% |
| Premier League | 0.72 | 58% |
| Bundesliga | 0.66 | 52% |
| All five | 0.76 | 60% |

| Value rank at season start | Avg points per game | Avg finish | Champions | Top 4 | Bottom 3 |
|---|---|---|---|---|---|
| Most valuable | 2.21 | 1.8 | 63.3% | 96.7% | 0% |
| 2nd-4th | 1.89 | 4.1 | 12.2% | 67.8% | 0% |
| 5th-10th | 1.44 | 8.9 | 0% | 13.8% | 3.9% |
| 11th or lower | 1.07 | 13.9 | 0% | 1.8% | 29.5% |

- **No club outside its league's 4 most valuable squads won a title.** The 11 champions that weren't the most valuable include Liverpool 2024/25 (4th most valuable), Napoli 2022/23 and 2024/25 (4th), Leverkusen 2023/24 (3rd) and Lille 2020/21 (4th).
- **Biggest single-season overperformers** (points above what their value predicts): Girona 2023/24 +30.7 (11th most valuable, finished 3rd), Lens 2022/23 +30.1 (8th, finished 2nd), Stuttgart 2023/24 +29.8 (11th, finished 2nd), Leverkusen 2023/24 +29.5 (champions unbeaten).
- **Biggest underperformers:** Schalke 2020/21 -32.5 (9th most valuable, relegated with 16 points), Chelsea 2022/23 -24.9 (3rd most valuable, finished 12th), Tottenham 2024/25 -24.8 and 2025/26 -24.1 (finished 17th both times).
- **Consistent overperformers** (average per season): Lens +14.9, Manchester City +9.9, Bayern +9.6, Inter +9.1, Arsenal +8.8. **Consistent underperformers:** Southampton -12.2, Valencia -10.1, Leicester -9.7, Tottenham -9.1, Chelsea -8.2.
- The elite clubs beating the line every year suggests value pays off more than proportionally at the very top: the fitted line (log of relative value) understates how dominant the richest squads are.
- How it's measured: value is the 25-player portfolio on 1 September, after the summer window, so points are compared with value the club had going in, not value it earned by winning. Points are on-pitch points from match results. Expected points come from a line fitted within each league across all six seasons: points per game against the log of the club's value relative to that season's league average.
- League tables were checked against the source's official final positions: 541 of 582 club-seasons match. 34 of the 41 differences are clubs level on points (LaLiga and Serie A break ties on head-to-head), and the rest come from point deductions (Juventus -10 in 2022/23, Everton -8 in 2023/24, Nice in 2021/22) moving the clubs around them.

---

## Limitations
- Market values are Transfermarkt estimates. Fees are reported figures, not audited accounts; add-ons are not separated.
- Loanees count for the club they play for: the source can't tell a loan from a free transfer.
- The source stopped valuing most reserve and youth players in 2024. The 25-player portfolio handles this, but 10 clubs in June 2025 and 3 in June 2026 have fewer than 20 valued players (`is_thin_squad`), mostly clubs just relegated.
- Growth since 2020 for promoted clubs starts from a squad valued in a lower league.
- Q11 uses a 1 September squad; in 2020 the summer window ran to 5 October, so a few late 2020 signings are missed. Points ignore deductions.
- Wages are not in the dataset, so this is asset value, not total squad cost.
