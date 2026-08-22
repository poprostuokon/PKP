"""
run_silver_load.py
------------------
Ladowanie warstwy SILVER przez pakiet PL/SQL (odpowiednik dbt run dla silver).
Wola SILVER.PKG_SILVER_LOAD.LOAD_ALL (dostepny jako DEV_APP) i wypisuje log DBMS_OUTPUT.

Polaczenie reuzywane z ingestion/db.py (wspolna infra + jeden .env).
Uruchamiaj z katalogu 'load':  python run_silver_load.py
"""

import sys
from pathlib import Path

# reuzycie db.py z ingestion (wspolne polaczenie + .env)
INGESTION_DIR = Path(__file__).resolve().parents[1] / "ingestion"
sys.path.insert(0, str(INGESTION_DIR))

import db  # noqa: E402  (db.py z ingestion)


def _drain_dbms_output(cursor) -> None:
    """Wypisuje bufor DBMS_OUTPUT (log z procedur load_*)."""
    line = cursor.var(str)
    status = cursor.var(int)
    while True:
        cursor.callproc("dbms_output.get_line", (line, status))
        if status.getvalue() != 0:
            break
        print(line.getvalue())


def main() -> None:
    with db.get_connection() as conn:
        with conn.cursor() as cur:
            cur.callproc("dbms_output.enable", (None,))   # None = bufor bez limitu
            # load_all robi COMMIT / ROLLBACK po swojej stronie
            cur.callproc("silver.pkg_silver_load.load_all")
            _drain_dbms_output(cur)
    print("Silver load: zakonczono.")


if __name__ == "__main__":
    main()