"""
Football Transfer ROI | Step 2 of 4: load the Kaggle CSVs into SQL Server

Loads the Transfermarkt CSVs into the `stg` schema. Every column lands as
text (NVARCHAR) exactly as it appears in the file; all typing and cleaning
happens in SQL in step 3. Columns are matched by header name, so the load
does not break if the dataset's column order changes in a future refresh.

Setup (once):
    pip install pandas sqlalchemy pyodbc

Usage:
    python 02_load_staging.py --data-dir "C:\\Users\\you\\Downloads\\player-scores"
    python 02_load_staging.py --data-dir ... --server "localhost\\SQLEXPRESS" --driver "ODBC Driver 17 for SQL Server"
"""

import argparse
import sys
import time
import urllib.parse
from pathlib import Path

import pandas as pd
from sqlalchemy import create_engine, text
from sqlalchemy.types import NVARCHAR

DATABASE = "FootballTransferROI"
CHUNK_ROWS = 100_000

# table name -> columns step 3 relies on (the load stops early if any are missing)
TABLES = {
    "competitions": ["competition_id", "name"],
    "clubs": ["club_id", "name", "domestic_competition_id", "stadium_name", "stadium_seats"],
    "games": [
        "game_id", "competition_id", "season", "round", "date",
        "home_club_id", "away_club_id", "home_club_goals", "away_club_goals",
        "home_club_name", "away_club_name", "attendance",
    ],
    "players": [
        "player_id", "name", "position", "sub_position", "date_of_birth",
        "country_of_citizenship", "current_club_id",
        "market_value_in_eur", "highest_market_value_in_eur",
    ],
    "player_valuations": ["player_id", "date", "market_value_in_eur", "current_club_id"],
    "transfers": [
        "player_id", "transfer_date", "transfer_season", "from_club_id", "to_club_id",
        "from_club_name", "to_club_name", "transfer_fee", "market_value_in_eur",
    ],
    "appearances": [
        "appearance_id", "game_id", "player_id", "player_club_id",
        "yellow_cards", "red_cards", "goals", "assists", "minutes_played",
    ],
}


def find_file(data_dir: Path, table: str) -> Path:
    for name in (f"{table}.csv", f"{table}.csv.gz"):
        path = data_dir / name
        if path.exists():
            return path
    sys.exit(f"Missing file: {table}.csv in {data_dir}. Unzip the Kaggle download there first.")


def make_engine(server: str, driver: str):
    odbc = (
        f"DRIVER={{{driver}}};SERVER={server};DATABASE={DATABASE};"
        "Trusted_Connection=yes;TrustServerCertificate=yes;"
    )
    return create_engine(
        "mssql+pyodbc:///?odbc_connect=" + urllib.parse.quote_plus(odbc),
        fast_executemany=True,
    )


def load_table(engine, table: str, path: Path) -> int:
    header = pd.read_csv(path, nrows=0).columns.tolist()
    missing = [c for c in TABLES[table] if c not in header]
    if missing:
        sys.exit(f"{path.name} is missing expected columns {missing}. Found: {header}")

    rows = 0
    reader = pd.read_csv(
        path,
        dtype=str,              # keep raw text; SQL does the typing
        keep_default_na=False,  # don't turn strings like "NA" into NULL...
        na_values=[""],         # ...only truly empty cells
        chunksize=CHUNK_ROWS,
    )
    for i, chunk in enumerate(reader):
        chunk.to_sql(
            table,
            engine,
            schema="stg",
            if_exists="replace" if i == 0 else "append",
            index=False,
            dtype={col: NVARCHAR(1000) for col in chunk.columns},
        )
        rows += len(chunk)
        print(f"  {table}: {rows:,} rows", end="\r")
    print()
    return rows


def main():
    parser = argparse.ArgumentParser(description="Load Transfermarkt CSVs into stg schema")
    parser.add_argument("--data-dir", required=True, type=Path, help="folder with the unzipped Kaggle CSVs")
    parser.add_argument("--server", default=r"localhost\SQLEXPRESS")
    parser.add_argument("--driver", default="ODBC Driver 18 for SQL Server")
    args = parser.parse_args()

    files = {t: find_file(args.data_dir, t) for t in TABLES}  # fail fast before loading anything
    engine = make_engine(args.server, args.driver)

    summary = {}
    for table, path in files.items():
        start = time.time()
        print(f"Loading {path.name} -> stg.{table}")
        file_rows = load_table(engine, table, path)
        with engine.connect() as conn:
            db_rows = conn.execute(text(f"SELECT COUNT(*) FROM stg.{table}")).scalar()
        if db_rows != file_rows:
            sys.exit(f"Row mismatch for {table}: file {file_rows:,} vs database {db_rows:,}")
        summary[table] = (db_rows, time.time() - start)

    print("\nStaging load complete:")
    for table, (count, secs) in summary.items():
        print(f"  stg.{table:<18} {count:>12,} rows  ({secs:,.0f}s)")


if __name__ == "__main__":
    main()
