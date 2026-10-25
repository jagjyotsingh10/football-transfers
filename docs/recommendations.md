# Recommendations

For a club's sporting director and finance director, treating the squad as a portfolio of player assets.
Based on Europe's top 5 leagues, June 2020 to June 2026. Every number comes from `sql/06_portfolio_questions.sql`;
the full answers are in [`findings.md`](findings.md).

**In one line:** squad value buys points, but extra spending doesn't buy points beyond what that value already predicts.
The clubs that win on both value and results buy young players near market value, sell before decline, and avoid
leaning on a handful of stars.

---

## 1. Buy young: it is the clearest driver of value gained

| Age when signed | Paid signings | Gained value |
|---|---|---|
| Under 23 | 580 | **71.6%** |
| 23-26 | 611 | 45.7% |
| 27 or older | 357 | **11.8%** |

Price points the same way: 54% of signings valued under €10m gained value (median +20%), against 28% of those valued
at €60m+ (median -32%). Vitinha (€30m to €140m at PSG), Bellingham (€11m to €120m at Dortmund) and Baleba
(€5m to €55m at Brighton) were all young when bought.

**Do:** aim most of the transfer budget at players under 23. Treat a signing aged 27+ or costing €60m+ as a
purchase of results now, not an asset that will hold its value, and price it that way.

## 2. Pay close to market value, and make a premium justify itself

Only 15.6% of paid deals were priced within 10% of the player's market value; 41.8% went above 110%. Premier League
clubs pay **€1.23 per €1 of market value** (median premium +23.9%); LaLiga (0.87) and Bundesliga (0.89) clubs buy
below value. The biggest premiums were Enzo Fernández (€66m over value), Antony (€60m) and Grealish (€52.5m).

**Do:** set a default ceiling of about 110% of market value. Anything above it needs a written case (a positional
gap, no alternative, resale clause). For selling clubs outside England, the Premier League premium is the market to
sell into.

## 3. Judge spending by points above expectation, not by league position

Season-start squad value explains **60%** of the variation in points per game, and the most valuable squad won its
league 19 times in 30. But net spend adds nothing on top: across the 61 clubs present in all six seasons, net spend and
points above expectation have a correlation of **-0.02**.

| Club | Net spend 2020/21-2025/26 | Points vs expected, per season |
|---|---|---|
| RC Lens | -€106m (net seller) | **+14.9** |
| Brighton | +€36m | +5.7 |
| Lille | -€310m (net seller) | +5.4 |
| Manchester United | +€861m | -4.3 |
| Chelsea | +€1,010m | **-8.2** |
| Tottenham | +€740m | -9.1 |

**Do:** set the season target from the squad's value rank (the dashboard's expected points), and review the manager,
recruitment and the squad against points above or below that line. A 6th-place finish with the 9th most valuable
squad is a success; with the 3rd most valuable it is not.

## 4. Keep any five players under half the portfolio

The most concentrated portfolios put two-thirds or more of their value in five players: Levante 71.8%, Nantes 67.7%,
Angers 66.4%, Köln 66.2%. Among the elite, Barcelona (52.7%) and Real Madrid (50.8%) depend far more on a few stars than
Manchester City (38.2%) or Arsenal (37.5%). Premier League clubs average 42.1% and are getting less concentrated.

**Do:** track the top-5 share every window and keep it below about 50%. Above that, one injury or one sale moves
half the balance sheet; plan a successor for each of the five before it is needed.

## 5. Sell before players decline

About a third of all portfolio value sits in players worth less than a year earlier (35.5% in June 2026, peaking at
43.5% in 2022), costing €3.8bn to €4.9bn a year. Some clubs carry it persistently: Atlético Madrid (54.2% on average),
Manchester United (53.6%) and Liverpool (51.4%). The biggest losses in the year to June 2026 were Real Madrid's
(€270m) and Liverpool's (€256m). The market has
already moved: players aged 29+ held 22.6% of value in 2020 and 12.6% in 2026.

**Do:** review every player whose value has fallen two revaluations in a row, and every player turning 28, as a sale
candidate while there is still value to recover. Keep declining exposure below the top 5 average of about a third.

## 6. Accept volatility as the price of growth, but size it

A typical player's value moves about 30% at each revaluation. The steadiest portfolios are elite and settled (Arsenal
14.5%, Liverpool 17.7%, Manchester City 18.3%); the most volatile are young and fast-changing (Angers 69.7%,
Strasbourg 50.3%, Como 47.5%). Younger portfolios also grew faster: 17.7% the following season for a value-weighted age
under 24, against 7.9% for 25.5-27.

**Do:** a growth strategy built on young players is sound, but its value will swing. Smaller clubs following it
should not borrow against squad value or count on a single sale to balance the books.

---

## What this analysis cannot tell you

- **Wages.** The dataset has no salaries, so this is asset value, not total squad cost. A free signing on high wages
  looks cheap here.
- **Causation.** Value predicting points does not prove value causes points; good coaching raises both values and
  results.
- **Fees.** Transfermarkt fees are reported figures; add-ons are not separated, and about 1 in 9 incoming deals has
  no fee, so spend is a lower bound.
- **Loans.** The source cannot tell a loan from a free transfer, so loanees count for the club they play for.

## Next steps worth taking

1. Add wage data (for example from a salary database) to measure total cost per point.
2. Separate loans from permanent moves, to value only the assets a club owns.
3. Re-run each summer: download the new Kaggle data, run steps 2 to 7, refresh the dashboard. The "latest" figures
   move forward automatically.
