"""
run_gold_load.py
----------------
Ladowanie wymiarow warstwy GOLD przez pakiet PL/SQL GOLD.PKG_GOLD_LOAD.
Domyslnie wola LOAD_DIMENSIONS (route budowany DZIENNIE - tylko kursy z dzis).

Opcjonalnie (--route-full) robi JEDNORAZOWY pelny load tras: wola
LOAD_D_ROUTE(p_full_load => TRUE), ktory skanuje caly rozklad (bez limitu daty).

Polaczenie reuzywane z ingestion/db.py (wspolna infra + jeden .env).
Uruchamiaj z katalogu 'load':
    python run_gold_load.py                # codzienne wymiary (route dzienny)
    python run_gold_load.py --route-full   # jednorazowy pelny load tras
"""

import sys
import argparse
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


def main(route_full: bool) -> None:
    with db.get_connection() as conn:
        with conn.cursor() as cur:
            cur.callproc("dbms_output.enable", (None,))   # None = bufor bez limitu

            # Zawsze pelny komplet wymiarow; flaga steruje tylko trybem d_route
            # (FALSE = dzienny, TRUE = cala historia). LOAD_DIMENSIONS commituje sam.
            cur.callproc("gold.pkg_gold_load.load_dimensions", [route_full])

            _drain_dbms_output(cur)

    print("Gold load: zakonczono" + (" (route FULL)." if route_full else "."))


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="Ladowanie wymiarow GOLD.")
    parser.add_argument(
        "--route-full",
        action="store_true",
        help="Jednorazowy pelny load d_route (caly rozklad, bez limitu daty).",
    )
    args = parser.parse_args()
    main(route_full=args.route_full)