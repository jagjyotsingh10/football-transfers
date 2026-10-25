"""
Football Transfer ROI | Step 7: generate the Power BI project (.pbip)

Writes a Power BI Project next to this script:
    FootballPortfolio.pbip               open this in Power BI Desktop
    FootballPortfolio.SemanticModel/     tables (rpt views), relationships, DAX measures, as TMDL
    FootballPortfolio.Report/            theme, 5 report pages and a club drill-through page, as PBIR JSON

Columns are read from the rpt views in SQL Server, so the model always
matches the database. Re-run after changing the views or the pages below,
then reopen the .pbip and click Refresh.

Usage:
    .venv\\Scripts\\python.exe powerbi/build_pbip.py
    .venv\\Scripts\\python.exe powerbi/build_pbip.py --server "YOURPC\\SQLEXPRESS"
"""

import argparse
import json
import shutil
import uuid
from pathlib import Path

import pyodbc

HERE = Path(__file__).resolve().parent
NAME = "FootballPortfolio"
DATABASE = "FootballTransferROI"
BASE_THEME = "Fluent2-CY26SU10"  # newest base theme shipped with Power BI Desktop 2.159
BASE_THEME_DIR = Path(r"C:\Program Files\Microsoft Power BI Desktop\bin\WebView2Resources\minerva\sharedresources\BaseThemes")

SCHEMA = "https://developer.microsoft.com/json-schemas/fabric"
VERSIONS = {"report": "3.0.0", "page": "2.0.0", "visual": "2.4.0"}

EUR = "€#,0"              # cards and axes: Power BI scales it itself (€32.6bn, €1.4bn)
EUR_M1 = "€#,0,,.0\\m"     # tables: 55800000 -> €55.8m (commas left of the decimal point divide by 1,000 each)
PCT = "0.0%"               # fractions
PCT_COL = "0.0\\%"         # columns already in percent (45.8 -> 45.8%)

# ---------------------------------------------------------------------------
# Semantic model: tables = rpt views
# ---------------------------------------------------------------------------
TABLES = [
    ("League", "vw_dim_competition"),
    ("Club", "vw_dim_club"),
    ("Club Portfolio", "vw_club_portfolio"),
    ("Composition", "vw_portfolio_composition"),
    ("Club KPIs", "vw_club_kpis"),
    ("Club Volatility", "vw_club_volatility"),
    ("Signings", "vw_signing_appreciation"),
    ("Fee vs Value", "vw_fee_vs_value"),
    ("Transfer Balance", "vw_club_transfer_balance"),
    ("Value vs Points", "vw_value_vs_points"),
    ("Portfolio Players", "vw_portfolio_player"),
]

DRILL_CLUB = "Arsenal FC"  # club the drill-through page shows when opened directly

# (many side table, column) -> (one side table, column)
RELATIONSHIPS = [
    (("Club Portfolio", "competition_id"), ("League", "competition_id")),
    (("Composition", "competition_id"), ("League", "competition_id")),
    (("Club KPIs", "competition_id"), ("League", "competition_id")),
    (("Club Volatility", "competition_id"), ("League", "competition_id")),
    (("Signings", "competition_id"), ("League", "competition_id")),
    (("Fee vs Value", "buyer_competition_id"), ("League", "competition_id")),
    (("Transfer Balance", "competition_id"), ("League", "competition_id")),
    (("Value vs Points", "competition_id"), ("League", "competition_id")),
    (("Club Portfolio", "club_id"), ("Club", "club_id")),
    (("Composition", "club_id"), ("Club", "club_id")),
    (("Club KPIs", "club_id"), ("Club", "club_id")),
    (("Club Volatility", "club_id"), ("Club", "club_id")),
    (("Signings", "club_id"), ("Club", "club_id")),
    (("Fee vs Value", "to_club_id"), ("Club", "club_id")),
    (("Transfer Balance", "club_id"), ("Club", "club_id")),
    (("Value vs Points", "club_id"), ("Club", "club_id")),
    (("Portfolio Players", "club_id"), ("Club", "club_id")),
]

LATEST_CP = "VAR d = [Latest Snapshot] RETURN "
MEASURES = {
    "Club Portfolio": [
        ("Portfolio Value", "SUM('Club Portfolio'[total_value_eur])", EUR),
        ("Latest Snapshot", "CALCULATE(MAX('Club Portfolio'[snapshot_date]), ALL('Club Portfolio'))", "yyyy-mm-dd"),
        ("Portfolio Value (latest)", LATEST_CP + "CALCULATE([Portfolio Value], 'Club Portfolio'[snapshot_date] = d)", EUR),
        ("Portfolio Value (June 2020)", "CALCULATE([Portfolio Value], 'Club Portfolio'[snapshot_year] = 2020)", EUR),
        ("Growth since June 2020",
         "DIVIDE([Portfolio Value (latest)] - [Portfolio Value (June 2020)], [Portfolio Value (June 2020)])", PCT),
        ("Clubs (latest)", LATEST_CP + "CALCULATE(DISTINCTCOUNT('Club Portfolio'[club_id]), 'Club Portfolio'[snapshot_date] = d)", "0"),
        ("Avg Value per Player (latest)",
         LATEST_CP + "CALCULATE(DIVIDE(SUM('Club Portfolio'[total_value_eur]), SUM('Club Portfolio'[squad_size])), 'Club Portfolio'[snapshot_date] = d)",
         EUR),
        ("Top-5 Share (latest)",
         LATEST_CP + "CALCULATE(DIVIDE(SUM('Club Portfolio'[top5_value_eur]), SUM('Club Portfolio'[total_value_eur])), 'Club Portfolio'[snapshot_date] = d)",
         PCT),
        ("Declining Exposure", "DIVIDE(SUM('Club Portfolio'[declining_value_eur]), SUM('Club Portfolio'[value_with_history_eur]))", PCT),
        ("Declining Exposure (latest)", LATEST_CP + "CALCULATE([Declining Exposure], 'Club Portfolio'[snapshot_date] = d)", PCT),
        ("Value Lost (latest)", LATEST_CP + "CALCULATE(SUM('Club Portfolio'[value_lost_eur]), 'Club Portfolio'[snapshot_date] = d)", EUR),
        ("Value Rank in League (latest)", LATEST_CP + "CALCULATE(MIN('Club Portfolio'[value_rank_in_league]), 'Club Portfolio'[snapshot_date] = d)", "0"),
    ],
    "Club": [
        ("Selected Club", "SELECTEDVALUE(Club[club_name], \"All clubs\")", None),
    ],
    "Portfolio Players": [
        ("Player Value (latest)",
         "VAR d = CALCULATE(MAX('Portfolio Players'[snapshot_date]), ALL('Portfolio Players')) "
         "RETURN CALCULATE(SUM('Portfolio Players'[market_value_eur]), 'Portfolio Players'[snapshot_date] = d)", EUR_M1),
        ("Player Age (latest)",
         "VAR d = CALCULATE(MAX('Portfolio Players'[snapshot_date]), ALL('Portfolio Players')) "
         "RETURN IF(HASONEVALUE('Portfolio Players'[player_id]), "  # blank on total rows: a summed age means nothing
         "CALCULATE(MAX('Portfolio Players'[age_years]), 'Portfolio Players'[snapshot_date] = d))", "0.0"),
    ],
    "Club Volatility": [
        ("Portfolio Volatility (latest)",
         "VAR d = CALCULATE(MAX('Club Volatility'[snapshot_date]), ALL('Club Volatility')) "
         "RETURN CALCULATE(AVERAGE('Club Volatility'[portfolio_volatility_pct]), 'Club Volatility'[snapshot_date] = d) / 100", PCT),
    ],
    "Composition": [
        ("Age Band Value", "CALCULATE(SUM(Composition[value_eur]), Composition[dimension] = \"Age band\")", EUR),
    ],
    "Club KPIs": [
        ("KPI Portfolio Value", "SUM('Club KPIs'[total_value_eur])", EUR),
        ("Value-Weighted Age", "AVERAGE('Club KPIs'[value_weighted_age])", "0.0"),
    ],
    "Signings": [
        ("Paid Signings", "COUNTROWS(Signings)", "#,0"),
        ("Median Appreciation", "MEDIAN(Signings[appreciation_pct]) / 100", PCT),
        ("Share Gaining Value",
         "DIVIDE(CALCULATE(COUNTROWS(Signings), Signings[appreciation_eur] > 0), "
         "CALCULATE(COUNTROWS(Signings), NOT ISBLANK(Signings[appreciation_eur])))", PCT),
    ],
    "Fee vs Value": [
        ("Deals", "COUNTROWS('Fee vs Value')", "#,0"),
        ("Fee-to-Value Ratio",
         "DIVIDE(CALCULATE(SUM('Fee vs Value'[fee_eur]), 'Fee vs Value'[market_value_at_transfer_eur] > 0), "
         "CALCULATE(SUM('Fee vs Value'[market_value_at_transfer_eur]), 'Fee vs Value'[market_value_at_transfer_eur] > 0))", "0.00"),
        # by buying league: sales to clubs outside the top 5 have no buying league and would show as (Blank)
        ("Fee-to-Value Ratio (top 5 buyers)",
         "CALCULATE([Fee-to-Value Ratio], NOT ISBLANK('Fee vs Value'[buyer_competition_id]))", "0.00"),
    ],
    "Transfer Balance": [
        ("Fees Paid", "SUM('Transfer Balance'[fees_paid_eur])", EUR),
        ("Fees Received", "SUM('Transfer Balance'[fees_received_eur])", EUR),
        ("Net Spend", "[Fees Paid] - [Fees Received]", EUR),
    ],
    "Value vs Points": [
        ("Avg Points per Game", "AVERAGE('Value vs Points'[points_per_game])", "0.00"),
        ("Avg Value Index", "AVERAGE('Value vs Points'[value_index])", "0.00"),
        ("Title Rate (most valuable squad)",
         "DIVIDE(CALCULATE(COUNTROWS('Value vs Points'), 'Value vs Points'[value_rank] = 1, 'Value vs Points'[position] = 1), "
         "CALCULATE(COUNTROWS('Value vs Points'), 'Value vs Points'[value_rank] = 1))", PCT),
        ("Top-4 Rate (most valuable squad)",
         "DIVIDE(CALCULATE(COUNTROWS('Value vs Points'), 'Value vs Points'[value_rank] = 1, 'Value vs Points'[position] <= 4), "
         "CALCULATE(COUNTROWS('Value vs Points'), 'Value vs Points'[value_rank] = 1))", PCT),
    ],
}

SQL_TO_TMDL = {
    "bigint": "int64", "int": "int64", "smallint": "int64", "tinyint": "int64",
    "decimal": "double", "numeric": "double", "float": "double", "real": "double",
    "bit": "boolean", "date": "dateTime", "datetime": "dateTime", "datetime2": "dateTime",
    "char": "string", "varchar": "string", "nchar": "string", "nvarchar": "string",
}


def tag(*parts: str) -> str:
    """Stable lineage tag, so re-running the script doesn't churn the git diff."""
    return str(uuid.uuid5(uuid.NAMESPACE_URL, "football-portfolio/" + "/".join(parts)))


def q(name: str) -> str:
    """Quote a TMDL object name when it isn't a plain identifier."""
    return name if name.replace("_", "").isalnum() else "'" + name.replace("'", "''") + "'"


def column_format(col: str, dtype: str) -> str | None:
    if dtype == "dateTime":
        return "yyyy-mm-dd"
    if col.endswith("_eur"):
        return EUR_M1
    if col.endswith("_pct"):
        return PCT_COL
    return None


def read_columns(server: str, driver: str) -> dict[str, list[tuple[str, str]]]:
    conn = pyodbc.connect(
        f"DRIVER={{{driver}}};SERVER={server};DATABASE={DATABASE};Trusted_Connection=yes;TrustServerCertificate=yes;")
    out = {}
    for _, view in TABLES:
        rows = conn.execute(
            "SELECT COLUMN_NAME, DATA_TYPE FROM INFORMATION_SCHEMA.COLUMNS "
            "WHERE TABLE_SCHEMA = 'rpt' AND TABLE_NAME = ? ORDER BY ORDINAL_POSITION", view).fetchall()
        if not rows:
            raise SystemExit(f"rpt.{view} not found: run sql/05_portfolio_model.sql first")
        out[view] = [(r.COLUMN_NAME, SQL_TO_TMDL[r.DATA_TYPE]) for r in rows]
    return out


def table_tmdl(table: str, view: str, columns: list[tuple[str, str]]) -> str:
    lines = [f"table {q(table)}", f"\tlineageTag: {tag(table)}", ""]
    for name, expr, fmt in MEASURES.get(table, []):
        lines.append(f"\tmeasure {q(name)} = {expr}")
        if fmt:
            lines.append(f"\t\tformatString: {fmt}")
        lines += [f"\t\tlineageTag: {tag(table, 'm', name)}", ""]
    for col, dtype in columns:
        lines += [f"\tcolumn {q(col)}", f"\t\tdataType: {dtype}"]
        fmt = column_format(col, dtype)
        if fmt:
            lines.append(f"\t\tformatString: {fmt}")
        if col.endswith("_id"):
            lines.append("\t\tisHidden")
        lines += [f"\t\tlineageTag: {tag(table, 'c', col)}", "\t\tsummarizeBy: none", f"\t\tsourceColumn: {col}", "",
                  "\t\tannotation SummarizationSetBy = User", ""]
    lines += [
        f"\tpartition {q(table)} = m",
        "\t\tmode: import",
        "\t\tsource =",
        "\t\t\t\tlet",
        "\t\t\t\t    Source = Sql.Database(SqlServer, SqlDatabase),",
        f"\t\t\t\t    Data = Source{{[Schema = \"rpt\", Item = \"{view}\"]}}[Data]",
        "\t\t\t\tin",
        "\t\t\t\t    Data",
        "",
        "\tannotation PBI_ResultType = Table",
        "",
    ]
    return "\n".join(lines)


def write_semantic_model(root: Path, columns: dict, server: str) -> None:
    sm = root / f"{NAME}.SemanticModel"
    clear_keeping_local(sm)
    (sm / "definition" / "tables").mkdir(parents=True)
    write_json(sm / "definition.pbism", {
        "$schema": f"{SCHEMA}/item/semanticModel/definitionProperties/1.0.0/schema.json",
        "version": "4.2",
        "settings": {},
    })
    (sm / "definition" / "database.tmdl").write_text("database\n\tcompatibilityLevel: 1600\n\n", encoding="utf-8")
    model = [
        "model Model",
        "\tculture: en-US",
        "\tdefaultPowerBIDataSourceVersion: powerBI_V3",
        "\tsourceQueryCulture: en-US",
        "\tdataAccessOptions",
        "\t\tlegacyRedirects",
        "\t\treturnErrorValuesAsNull",
        "",
        "annotation __PBI_TimeIntelligenceEnabled = 0",  # no hidden auto date tables
        "",
    ] + [f"ref table {q(t)}" for t, _ in TABLES] + [""]
    (sm / "definition" / "model.tmdl").write_text("\n".join(model), encoding="utf-8")
    expressions = [
        f'expression SqlServer = "{server}" meta [IsParameterQuery=true, Type="Text", IsParameterQueryRequired=true]',
        f"\tlineageTag: {tag('param', 'SqlServer')}",
        "",
        "\tannotation PBI_ResultType = Text",
        "",
        f'expression SqlDatabase = "{DATABASE}" meta [IsParameterQuery=true, Type="Text", IsParameterQueryRequired=true]',
        f"\tlineageTag: {tag('param', 'SqlDatabase')}",
        "",
        "\tannotation PBI_ResultType = Text",
        "",
    ]
    (sm / "definition" / "expressions.tmdl").write_text("\n".join(expressions), encoding="utf-8")
    rels = []
    for (ft, fc), (tt, tc) in RELATIONSHIPS:
        rels += [f"relationship {tag('rel', ft, fc, tt, tc)}", f"\tfromColumn: {q(ft)}.{q(fc)}", f"\ttoColumn: {q(tt)}.{q(tc)}", ""]
    (sm / "definition" / "relationships.tmdl").write_text("\n".join(rels), encoding="utf-8")
    for table, view in TABLES:
        (sm / "definition" / "tables" / f"{table}.tmdl").write_text(table_tmdl(table, view, columns[view]), encoding="utf-8")


# ---------------------------------------------------------------------------
# Report: pages and visuals (canvas 1280 x 720)
# ---------------------------------------------------------------------------
def lit(value) -> dict:
    if isinstance(value, bool):
        v = "true" if value else "false"
    elif isinstance(value, (int, float)):
        v = f"{value}D"
    else:
        v = "'" + str(value).replace("'", "''") + "'"
    return {"expr": {"Literal": {"Value": v}}}


# cards scale euros automatically; one decimal keeps €32.6bn from rounding to €33bn
ONE_DECIMAL = {"labels": [{"properties": {"labelPrecision": {"expr": {"Literal": {"Value": "1L"}}}}}]}


def col(entity: str, prop: str) -> dict:
    return {"Column": {"Expression": {"SourceRef": {"Entity": entity}}, "Property": prop}}


def meas(entity: str, prop: str) -> dict:
    return {"Measure": {"Expression": {"SourceRef": {"Entity": entity}}, "Property": prop}}


def proj(field: dict, display: str | None = None) -> dict:
    kind = "Column" if "Column" in field else "Measure"
    entity = field[kind]["Expression"]["SourceRef"]["Entity"]
    prop = field[kind]["Property"]
    p = {"field": field, "queryRef": f"{entity}.{prop}", "nativeQueryRef": prop}
    if display:
        p["displayName"] = display
    return p


class Page:
    def __init__(self, key: str, tab: str, title: str, subtitle: str, league_slicer: bool = True, header_x: int = 20):
        self.name = tag("page", key).replace("-", "")[:20]
        self.tab = tab  # page tab name
        self.extra: dict = {}  # extra page.json properties (drill-through binding)
        self.visuals: list[dict] = []
        self.textbox(key + "-header", header_x, 10, 960 - header_x, 64, title, subtitle)
        if league_slicer:  # no container title: the slicer's own header already says "League"
            self.visual(key + "-league", "slicer", (980, 10, 280, 64), {"Values": [proj(col("League", "competition_name"), "League")]},
                        objects={"data": [{"properties": {"mode": lit("Dropdown")}}]})

    def drillthrough(self, field: dict, value: str) -> None:
        """Make this a drill-through page on `field`, opened on `value` by default."""
        filter_name = tag("filter", self.name).replace("-", "")[:20]
        entity, prop = field["Column"]["Expression"]["SourceRef"]["Entity"], field["Column"]["Property"]
        self.extra = {
            "type": "Drillthrough",
            "pageBinding": {"name": tag("binding", self.name).replace("-", "")[:20], "type": "Drillthrough",
                            "parameters": [{"name": tag("param", self.name).replace("-", "")[:20],
                                            "boundFilter": filter_name, "fieldExpr": field}]},
            "filterConfig": {"filters": [{
                "name": filter_name,
                "field": field,
                "type": "Categorical",
                "filter": {"Version": 2, "From": [{"Name": "c", "Entity": entity, "Type": 0}],
                           "Where": [{"Condition": {"In": {
                               "Expressions": [{"Column": {"Expression": {"SourceRef": {"Source": "c"}}, "Property": prop}}],
                               "Values": [[{"Literal": {"Value": "'" + value.replace("'", "''") + "'"}}]]}}}]},
                "howCreated": "Drillthrough",
            }]},
        }

    def back_button(self, key: str, pos: tuple) -> None:
        self._container(key, pos, {
            "visualType": "actionButton",
            "objects": {"icon": [{"properties": {"shapeType": lit("back")}, "selector": {"id": "default"}}]},
            "visualContainerObjects": {"visualLink": [{"properties": {"show": lit(True), "type": lit("Back")}}]},
        })

    def _container(self, key: str, pos: tuple, visual: dict) -> None:
        x, y, w, h = pos
        n = len(self.visuals)
        self.visuals.append({
            "$schema": f"{SCHEMA}/item/report/definition/visualContainer/{VERSIONS['visual']}/schema.json",
            "name": tag("visual", key).replace("-", "")[:20],
            "position": {"x": x, "y": y, "z": n * 1000, "width": w, "height": h, "tabOrder": n * 1000},
            "visual": visual,
        })

    def textbox(self, key: str, x, y, w, h, title: str, subtitle: str) -> None:
        paragraphs = [
            {"textRuns": [{"value": title, "textStyle": {"fontWeight": "bold", "fontSize": "18pt", "color": "#0b0b0b"}}]},
            {"textRuns": [{"value": subtitle, "textStyle": {"fontSize": "10pt", "color": "#52514e"}}]},
        ]
        self._container(key, (x, y, w, h), {"visualType": "textbox", "objects": {"general": [{"properties": {"paragraphs": paragraphs}}]}})

    def visual(self, key: str, vtype: str, pos: tuple, roles: dict, sort: tuple | None = None,
               title: str | None = None, objects: dict | None = None) -> None:
        query = {"queryState": {role: {"projections": ps} for role, ps in roles.items()}}
        if sort:
            field, direction = sort
            query["sortDefinition"] = {"sort": [{"field": field, "direction": direction}], "isDefaultSort": False}
        visual = {"visualType": vtype, "query": query, "drillFilterOtherVisuals": True}
        if objects:
            visual["objects"] = objects
        if title:
            visual["visualContainerObjects"] = {"title": [{"properties": {"show": lit(True), "text": lit(title)}}]}
        self._container(key, pos, visual)


def build_pages() -> list[Page]:
    # Club names always come from the Club table, so drill-through to the Club page works from any visual
    CP, SG, FV, TB, VP, KP, VO, CO = ("Club Portfolio", "Signings", "Fee vs Value", "Transfer Balance",
                                      "Value vs Points", "Club KPIs", "Club Volatility", "Composition")
    pages = []

    # 1. Overview (Q1, Q5)
    p = Page("overview", "Overview", "Squad portfolios across Europe's top 5 leagues",
             "Market value of each club's 25 most valuable players, every 30 June from 2020 to 2026 (Transfermarkt estimates)")
    for i, (m, label) in enumerate([("Portfolio Value (latest)", "Portfolio value, June 2026"),
                                    ("Growth since June 2020", "Growth since June 2020"),
                                    ("Avg Value per Player (latest)", "Average value per player"),
                                    ("Clubs (latest)", "Clubs")]):
        p.visual(f"overview-card{i}", "card", (20 + i * 310, 84, 300, 100), {"Values": [proj(meas(CP, m), label)]},
                 objects=ONE_DECIMAL if m.startswith(("Portfolio Value", "Avg Value")) else None)
    p.visual("overview-line", "lineChart", (20, 196, 760, 504),
             {"Category": [proj(col(CP, "closes_season_label"), "Season ending")],
              "Series": [proj(col(CP, "competition_name"), "League")],
              "Y": [proj(meas(CP, "Portfolio Value"), "Portfolio value")]},
             sort=(col(CP, "closes_season_label"), "Ascending"), title="Total portfolio value by league (Q1)")
    p.visual("overview-bar", "clusteredBarChart", (790, 196, 470, 504),
             {"Category": [proj(col("Club", "club_name"), "Club")], "Y": [proj(meas(CP, "Portfolio Value (latest)"), "Portfolio value")]},
             sort=(meas(CP, "Portfolio Value (latest)"), "Descending"), title="Most valuable portfolios, June 2026 (Q5)")
    pages.append(p)

    # 2. Club benchmark (Q5, Q6, Q10)
    p = Page("benchmark", "Club benchmark", "Club benchmark", "Value, growth, concentration and age at 30 June 2026, clubs in 2025/26")
    p.visual("benchmark-table", "tableEx", (20, 84, 1240, 316),
             {"Values": [proj(col("Club", "club_name"), "Club"), proj(col(KP, "competition_name"), "League"),
                         proj(col(KP, "total_value_eur"), "Value"), proj(col(KP, "value_rank_in_league"), "Rank in league"),
                         proj(col(KP, "cagr_2020_2026_pct"), "Growth per year since 2020"),
                         proj(col(KP, "growth_last_year_pct"), "Growth last year"),
                         proj(col(KP, "top5_share_pct"), "Top-5 share"), proj(col(KP, "value_weighted_age"), "Value-weighted age"),
                         proj(col(KP, "avg_value_eur"), "Avg value per player"),
                         proj(col(KP, "avg_value_index_league"), "Avg value vs league (100 = avg)")]},
             sort=(col(KP, "total_value_eur"), "Descending"), title="Club benchmark (Q5)")
    p.visual("benchmark-scatter", "scatterChart", (20, 410, 400, 290),
             {"Category": [proj(col("Club", "club_name"), "Club")],
              "X": [proj(meas(KP, "Value-Weighted Age"), "Value-weighted age")],
              "Y": [proj(meas(KP, "KPI Portfolio Value"), "Portfolio value")]},
             title="Age profile vs portfolio value (Q6)")
    p.visual("benchmark-age", "hundredPercentStackedColumnChart", (430, 410, 410, 290),
             {"Category": [proj(col(CO, "closes_season_label"), "Season ending")],
              "Series": [proj(col(CO, "category"), "Age band")],
              "Y": [proj(meas(CO, "Age Band Value"), "Value")]},
             sort=(col(CO, "closes_season_label"), "Ascending"), title="Share of value by age band (Q6)")
    p.visual("benchmark-avg", "clusteredBarChart", (850, 410, 410, 290),
             {"Category": [proj(col("Club", "club_name"), "Club")],
              "Y": [proj(meas(CP, "Avg Value per Player (latest)"), "Avg value per player")]},
             sort=(meas(CP, "Avg Value per Player (latest)"), "Descending"), title="Average value per player, June 2026 (Q10)")
    pages.append(p)

    # 3. Risk (Q2, Q4, Q9)
    p = Page("risk", "Risk", "Portfolio risk", "Concentration, exposure to falling values and valuation volatility")
    p.visual("risk-conc", "clusteredBarChart", (20, 84, 400, 616),
             {"Category": [proj(col("Club", "club_name"), "Club")], "Y": [proj(meas(CP, "Top-5 Share (latest)"), "Top-5 share")]},
             sort=(meas(CP, "Top-5 Share (latest)"), "Descending"), title="Value held by top 5 players, June 2026 (Q2)")
    p.visual("risk-exposure-trend", "lineChart", (430, 84, 420, 300),
             {"Category": [proj(col(CP, "closes_season_label"), "Season ending")],
              "Series": [proj(col(CP, "competition_name"), "League")],
              "Y": [proj(meas(CP, "Declining Exposure"), "Declining exposure")]},
             sort=(col(CP, "closes_season_label"), "Ascending"), title="Share of value in declining players (Q4)")
    p.visual("risk-exposure", "clusteredBarChart", (430, 394, 420, 306),
             {"Category": [proj(col("Club", "club_name"), "Club")], "Y": [proj(meas(CP, "Declining Exposure (latest)"), "Declining exposure")]},
             sort=(meas(CP, "Declining Exposure (latest)"), "Descending"), title="Most exposed to declining values, June 2026 (Q4)")
    p.visual("risk-vol", "clusteredBarChart", (860, 84, 400, 616),
             {"Category": [proj(col("Club", "club_name"), "Club")], "Y": [proj(meas(VO, "Portfolio Volatility (latest)"), "Volatility")]},
             sort=(meas(VO, "Portfolio Volatility (latest)"), "Descending"), title="Portfolio volatility per revaluation (Q9)")
    pages.append(p)

    # 4. Transfers (Q3, Q7, Q8)
    p = Page("transfers", "Transfers", "Transfers", "Paid signings 2020/21 to 2025/26: value gained, fees vs market value, net spend")
    p.visual("transfers-signings", "tableEx", (20, 84, 760, 316),
             {"Values": [proj(col(SG, "player_name"), "Player"), proj(col("Club", "club_name"), "Signed by"),
                         proj(col(SG, "season_label"), "Season"), proj(col(SG, "fee_eur"), "Fee"),
                         proj(col(SG, "value_at_transfer_eur"), "Value at signing"),
                         proj(col(SG, "latest_value_eur"), "Latest value at club"),
                         proj(col(SG, "appreciation_eur"), "Gain")]},
             sort=(col(SG, "appreciation_eur"), "Descending"), title="Biggest value gains after signing (Q3)")
    p.visual("transfers-net", "clusteredBarChart", (790, 84, 470, 616),
             {"Category": [proj(col("Club", "club_name"), "Club")], "Y": [proj(meas(TB, "Net Spend"), "Net spend")]},
             sort=(meas(TB, "Net Spend"), "Descending"), title="Fees paid minus received, 2020/21-2025/26 (Q7)")
    p.visual("transfers-bands", "clusteredColumnChart", (20, 410, 370, 290),
             {"Category": [proj(col(FV, "price_band"), "Fee vs market value")], "Y": [proj(meas(FV, "Deals"), "Deals")]},
             sort=(meas(FV, "Deals"), "Descending"), title="Fee vs market value at transfer (Q8)")
    p.visual("transfers-ratio", "clusteredBarChart", (400, 410, 380, 290),
             {"Category": [proj(col("League", "competition_name"), "Buying league")],
              "Y": [proj(meas(FV, "Fee-to-Value Ratio (top 5 buyers)"), "Fee ÷ market value")]},
             sort=(meas(FV, "Fee-to-Value Ratio (top 5 buyers)"), "Descending"), title="Fee paid per €1 of market value (Q8)")
    pages.append(p)

    # 5. Value vs points (Q11)
    p = Page("points", "Value vs points", "Does portfolio value buy league points?",
             "Portfolio value on 1 September vs on-pitch points that season, 2020/21 to 2025/26")
    for i, (m, label) in enumerate([("Title Rate (most valuable squad)", "Most valuable squad won the league"),
                                    ("Top-4 Rate (most valuable squad)", "Most valuable squad finished top 4")]):
        p.visual(f"points-card{i}", "card", (20 + i * 315, 84, 305, 100), {"Values": [proj(meas(VP, m), label)]})
    p.visual("points-scatter", "scatterChart", (20, 196, 620, 504),
             {"Category": [proj(col(VP, "club_season"), "Club-season")],
              "X": [proj(meas(VP, "Avg Value Index"), "Value vs league average (1 = average)")],
              "Y": [proj(meas(VP, "Avg Points per Game"), "Points per game")]},
             title="Season-start value vs points per game (Q11)")
    p.visual("points-rank", "clusteredColumnChart", (650, 84, 610, 290),
             {"Category": [proj(col(VP, "value_rank"), "Value rank in league at season start")],
              "Y": [proj(meas(VP, "Avg Points per Game"), "Points per game")]},
             sort=(col(VP, "value_rank"), "Ascending"), title="Points per game by value rank (Q11)")
    p.visual("points-table", "tableEx", (650, 384, 610, 316),
             {"Values": [proj(col("Club", "club_name"), "Club"), proj(col(VP, "season_label"), "Season"),
                         proj(col(VP, "value_rank"), "Value rank"), proj(col(VP, "position"), "Finished"),
                         proj(col(VP, "points"), "Points"), proj(col(VP, "expected_points"), "Expected"),
                         proj(col(VP, "points_vs_expected"), "vs expected")]},
             sort=(col(VP, "points_vs_expected"), "Descending"), title="Points above or below what value predicts (Q11)")
    pages.append(p)

    # 6. Club drill-through: right-click a club on any page -> Drill through -> Club
    PP = "Portfolio Players"
    p = Page("club", "Club", "Club drill-through",
             "Right-click a club on any page and choose Drill through > Club. Ctrl+click the arrow to go back.",
             league_slicer=False, header_x=70)
    p.drillthrough(col("Club", "club_name"), DRILL_CLUB)
    p.back_button("club-back", (20, 22, 40, 40))
    for i, (table, m, label, x, w) in enumerate([
            ("Club", "Selected Club", "Club", 20, 300),
            (CP, "Portfolio Value (latest)", "Portfolio value, June 2026", 330, 230),
            (CP, "Value Rank in League (latest)", "Value rank in league", 570, 230),
            (CP, "Growth since June 2020", "Growth since June 2020", 810, 230),
            (CP, "Top-5 Share (latest)", "Top-5 share", 1050, 210)]):
        p.visual(f"club-card{i}", "card", (x, 84, w, 100), {"Values": [proj(meas(table, m), label)]},
                 objects=ONE_DECIMAL if m.startswith("Portfolio Value") else None)
    p.visual("club-trend", "lineChart", (20, 196, 620, 250),
             {"Category": [proj(col(CP, "closes_season_label"), "Season ending")],
              "Y": [proj(meas(CP, "Portfolio Value"), "Portfolio value")]},
             sort=(col(CP, "closes_season_label"), "Ascending"), title="Portfolio value over time")
    p.visual("club-seasons", "tableEx", (650, 196, 610, 250),
             {"Values": [proj(col(VP, "season_label"), "Season"), proj(col(VP, "value_rank"), "Value rank"),
                         proj(col(VP, "position"), "Finished"), proj(col(VP, "points"), "Points"),
                         proj(col(VP, "expected_points"), "Expected"), proj(col(VP, "points_vs_expected"), "vs expected")]},
             sort=(col(VP, "season_label"), "Ascending"), title="Season by season: value rank vs finish")
    p.visual("club-squad", "tableEx", (20, 456, 620, 244),
             {"Values": [proj(col(PP, "player_name"), "Player"), proj(col(PP, "position"), "Position"),
                         proj(meas(PP, "Player Age (latest)"), "Age"), proj(meas(PP, "Player Value (latest)"), "Value")]},
             sort=(meas(PP, "Player Value (latest)"), "Descending"), title="Squad portfolio, June 2026")
    p.visual("club-signings", "tableEx", (650, 456, 610, 244),
             {"Values": [proj(col(SG, "player_name"), "Player"), proj(col(SG, "season_label"), "Season"),
                         proj(col(SG, "fee_eur"), "Fee"), proj(col(SG, "value_at_transfer_eur"), "Value at signing"),
                         proj(col(SG, "latest_value_eur"), "Latest value"), proj(col(SG, "appreciation_eur"), "Gain")]},
             sort=(col(SG, "appreciation_eur"), "Descending"), title="Paid signings and value gained")
    pages.append(p)
    return pages


THEME = {
    "name": "Football Portfolio",
    # first slots of the validated reference palette: leagues and age bands use slots in order
    "dataColors": ["#2a78d6", "#eb6834", "#1baf7a", "#eda100", "#e87ba4", "#008300", "#6250d6", "#e34948"],
    "background": "#FFFFFF",
    "foreground": "#0b0b0b",
    "tableAccent": "#2a78d6",
    "good": "#008300", "neutral": "#eda100", "bad": "#e34948",
    "textClasses": {
        "title": {"fontSize": 12, "color": "#0b0b0b"},
        "label": {"fontSize": 10, "color": "#52514e"},
        "callout": {"fontSize": 28, "color": "#0b0b0b"},
    },
}


def write_report(root: Path) -> None:
    rp = root / f"{NAME}.Report"
    clear_keeping_local(rp)
    d = rp / "definition"
    (d / "pages").mkdir(parents=True)
    write_json(rp / "definition.pbir", {
        "$schema": f"{SCHEMA}/item/report/definitionProperties/2.0.0/schema.json",
        "version": "4.0",
        "datasetReference": {"byPath": {"path": f"../{NAME}.SemanticModel"}},
    })
    write_json(d / "version.json", {"$schema": f"{SCHEMA}/item/report/definition/versionMetadata/1.0.0/schema.json", "version": "2.0.0"})
    theme_version = dict(VERSIONS)
    write_json(d / "report.json", {
        "$schema": f"{SCHEMA}/item/report/definition/report/{VERSIONS['report']}/schema.json",
        "themeCollection": {
            "baseTheme": {"name": BASE_THEME, "reportVersionAtImport": theme_version, "type": "SharedResources"},
            "customTheme": {"name": "FootballPortfolioTheme.json", "reportVersionAtImport": theme_version, "type": "RegisteredResources"},
        },
        "resourcePackages": [
            {"name": "SharedResources", "type": "SharedResources",
             "items": [{"name": BASE_THEME, "path": f"BaseThemes/{BASE_THEME}.json", "type": "BaseTheme"}]},
            {"name": "RegisteredResources", "type": "RegisteredResources",
             "items": [{"name": "FootballPortfolioTheme.json", "path": "FootballPortfolioTheme.json", "type": "CustomTheme"}]},
        ],
    })
    shared = rp / "StaticResources" / "SharedResources" / "BaseThemes"
    shared.mkdir(parents=True)
    shutil.copy(BASE_THEME_DIR / f"{BASE_THEME}.json", shared / f"{BASE_THEME}.json")
    registered = rp / "StaticResources" / "RegisteredResources"
    registered.mkdir(parents=True)
    write_json(registered / "FootballPortfolioTheme.json", THEME)

    pages = build_pages()
    write_json(d / "pages" / "pages.json", {
        "$schema": f"{SCHEMA}/item/report/definition/pagesMetadata/1.0.0/schema.json",
        "pageOrder": [p.name for p in pages],
        "activePageName": pages[0].name,
    })
    for p in pages:
        pd = d / "pages" / p.name
        (pd / "visuals").mkdir(parents=True)
        write_json(pd / "page.json", {
            "$schema": f"{SCHEMA}/item/report/definition/page/{VERSIONS['page']}/schema.json",
            "name": p.name, "displayName": p.tab,
            "displayOption": "FitToPage", "height": 720, "width": 1280,
            **p.extra,
        })
        for v in p.visuals:
            vd = pd / "visuals" / v["name"]
            vd.mkdir()
            write_json(vd / "visual.json", v)


def clear_keeping_local(folder: Path) -> None:
    """Delete a generated folder's contents, but keep .pbi (Power BI's data cache and local settings)."""
    if not folder.exists():
        return
    for child in folder.iterdir():
        if child.name == ".pbi":
            continue
        shutil.rmtree(child) if child.is_dir() else child.unlink()


def write_json(path: Path, obj) -> None:
    path.write_text(json.dumps(obj, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")


def main():
    parser = argparse.ArgumentParser(description="Generate the Power BI project from the rpt views")
    parser.add_argument("--server", default=r"localhost\SQLEXPRESS")
    parser.add_argument("--driver", default="ODBC Driver 18 for SQL Server")
    args = parser.parse_args()

    columns = read_columns(args.server, args.driver)
    write_semantic_model(HERE, columns, args.server)
    write_report(HERE)
    write_json(HERE / f"{NAME}.pbip", {
        "$schema": f"{SCHEMA}/pbip/pbipProperties/1.0.0/schema.json",
        "version": "1.0",
        "artifacts": [{"report": {"path": f"{NAME}.Report"}}],
        "settings": {"enableAutoRecovery": True},
    })
    n_measures = sum(len(m) for m in MEASURES.values())
    print(f"Wrote {NAME}.pbip: {len(TABLES)} tables, {len(RELATIONSHIPS)} relationships, {n_measures} measures, "
          f"{len(build_pages())} pages (including the club drill-through)")


if __name__ == "__main__":
    main()
