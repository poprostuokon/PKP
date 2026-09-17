"""
run_silver_live.py
------------------
Ladowanie trackingu LIVE ze stg.land_*_live przez SILVER.PKG_SILVER_LOAD_LIVE.
Wolane po prepare_stg_live w cyklu pollera (albo recznie).
Uruchamiaj z katalogu 'load':  python run_silver_live.py
"""

import sys
from pathlib import Path

INGESTION_DIR = Path(__file__).resolve().parents[1] / "ingestion"
sys.path.insert(0, str(INGESTION_DIR))

import db 


def _drain_dbms_output(cursor) -> None:
    line = cursor.var(str)
    status = cursor.var(int)
    while True:
        cursor.callproc("dbms_output.get_line", (line, status))
        if status.getvalue() != 0:
            break
        print(line.getvalue())


def run_silver_live() -> None:
    with db.get_connection() as conn:
        with conn.cursor() as cur:
            cur.callproc("dbms_output.enable", (None,))
            cur.callproc("silver.pkg_silver_load_live.p_load_all_live")  # master: COMMIT po swojej stronie
            _drain_dbms_output(cur)
    print("Silver LIVE load: zakonczono.")


if __name__ == "__main__":
    run_silver_live()