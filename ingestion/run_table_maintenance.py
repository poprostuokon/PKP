"""
run_table_maintenance.py
------------------------
Reorganizacja (MOVE) zwyklych tabel, ktore sie rozlazly (niski % pelnych blokow).
Odzyskuje miejsce jak reczne ALTER TABLE ... MOVE (np. stg_load_log 47MB -> 0.2MB).

Wola MAINTENANCE.PKG_MAINTENANCE. Polaczenie z ingestion/db.py.

    python run_table_maintenance.py                       # SILVER GOLD MAINTENANCE, progi 8/50
    python run_table_maintenance.py --schemas MAINTENANCE
    python run_table_maintenance.py --min-mb 4 --max-full 40
"""

import argparse
import sys
from pathlib import Path

INGESTION_DIR = Path(__file__).resolve().parents[1] / "ingestion"
sys.path.insert(0, str(INGESTION_DIR))

import db # noqa: E402


def _drain_dbms_output(cursor) -> None:
    line = cursor.var(str)
    status = cursor.var(int)
    while True:
        cursor.callproc("dbms_output.get_line", (line, status))
        if status.getvalue() != 0:
            break
        print(line.getvalue())


def main(schemas: list[str], min_mb: int, max_full: int) -> None:
    with db.get_connection() as conn, conn.cursor() as cur:
        cur.callproc("dbms_output.enable", (None,))

        cur.callproc("maintenance.pkg_maintenance.p_clear_queue")

        for sch in schemas:
            cur.callproc(
                "maintenance.pkg_maintenance.p_gen_table_move_schema",
                [sch, min_mb, max_full],
            )

        try:
            cur.callproc("maintenance.pkg_maintenance.p_run_compress_queue")
        finally:
            _drain_dbms_output(cur)

    print(f"Table maintenance: zakonczono (schemas={schemas}, "
          f"min_mb={min_mb}, max_full={max_full}).")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(
        description="Reorganizacja (MOVE) rozlazlych tabel wg progow."
    )
    parser.add_argument("--schemas", nargs="+",
                        default=["SILVER", "GOLD", "MAINTENANCE"],
                        help="Schematy. Domyslnie: SILVER GOLD MAINTENANCE.")
    parser.add_argument("--min-mb", type=int, default=8,
                        help="Pomijaj tabele mniejsze niz tyle MB. Domyslnie 8.")
    parser.add_argument("--max-full", type=int, default=50,
                        help="MOVE gdy %% pelnych blokow < tego. Domyslnie 50.")
    args = parser.parse_args()
    main(schemas=[s.upper() for s in args.schemas],
         min_mb=args.min_mb, max_full=args.max_full)