"""
run_gold_load.py
----------------
Ladowanie warstwy GOLD przez pakiet PL/SQL GOLD.PKG_GOLD_LOAD.

Jeden runner na caly gold - etapami sterowanymi flaga --what:
  * dims   -> LOAD_DIMENSIONS  (wszystkie wymiary; --route-full = pelny d_route)
  * facts  -> LOAD_FACTS_DAILY (recompute okna --days ostatnich dni)
  * all    -> dims, potem facts (fakty zaleza od wymiarow)

Kazdy master PL/SQL robi COMMIT / ROLLBACK po swojej stronie.
Polaczenie reuzywane z ingestion/db.py (wspolna infra + jeden .env).

Uruchamiaj z katalogu 'load':
    python run_gold_load.py                          # wymiary + fakty (route dzienny, okno 3 dni)
    python run_gold_load.py --what dims --route-full # tylko wymiary, pelny load tras (jednorazowo)
    python run_gold_load.py --what facts --days 7    # tylko fakty, okno 7 dni
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


# --- etapy: kazdy wola swoj master PL/SQL (master commituje sam) ---

def _load_dims(cur, route_full: bool) -> None:
    # flaga steruje tylko trybem d_route (FALSE = dzienny, TRUE = cala historia)
    cur.callproc("gold.pkg_gold_load.load_dimensions", [route_full])


def _load_facts(cur, days: int) -> None:
    # recompute okna ostatnich 'days' dni (DELETE + INSERT per doba)
    cur.callproc("gold.pkg_gold_load.load_facts_daily", [days])


def main(what: str, route_full: bool, days: int) -> None:
    with db.get_connection() as conn:
        with conn.cursor() as cur:
            cur.callproc("dbms_output.enable", (None,))   # None = bufor bez limitu

            if what in ("all", "dims"):
                _load_dims(cur, route_full)
            if what in ("all", "facts"):
                _load_facts(cur, days)                     # po wymiarach (fakty od nich zaleza)

            _drain_dbms_output(cur)

    print(f"Gold load: zakonczono (what={what}, route_full={route_full}, days={days}).")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="Ladowanie warstwy GOLD (wymiary + fakty).")
    parser.add_argument(
        "--what",
        choices=["all", "dims", "facts"],
        default="all",
        help="Co zaladowac: all (domyslnie), dims, facts.",
    )
    parser.add_argument(
        "--route-full",
        action="store_true",
        help="Wymiary: jednorazowy pelny load d_route (caly rozklad, bez limitu daty).",
    )
    parser.add_argument(
        "--days",
        type=int,
        default=3,
        help="Fakty: ile ostatnich dni przeliczyc (recompute). Domyslnie 3.",
    )
    args = parser.parse_args()
    main(what=args.what, route_full=args.route_full, days=args.days)