import sqlite3
from pathlib import Path

db = Path(__file__).resolve().parents[1] / "fuel_station.db"
conn = sqlite3.connect(db)
cur = conn.cursor()
for (name,) in cur.execute("SELECT name FROM sqlite_master WHERE type='table' ORDER BY 1"):
    cols = [row[1] for row in cur.execute(f"PRAGMA table_info({name})")]
    print(f"{name}: {cols}")
