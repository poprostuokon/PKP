"""
run_index_maintenance.py
------------------------
Konserwacja indeksow: czysci kolejke, generuje ALTER INDEX ... REBUILD COMPRESS
ADVANCED LOW dla indeksow SILVER i GOLD, ktore przekroczyly prog PCTSAVE lub
del_pct, po czym wykonuje kolejke.

Wola MAINTENANCE.PKG_MAINTENANCE (dostepny jako DEV_APP).
Polaczenie reuzywane z ingestion/db.py (wspolna infra + jeden .env).

Uruchamiaj z katalogu 'load':
    python run_index_maintenance.py                      # silver + gold, progi domyslne (15/15)
    python run_index_maintenance.py --schemas SILVER     # tylko silver
    python run_index_maintenance.py --min-pct 10 --min-del 25
"""

import argparse
import sys
from pathlib import Path

# reuzycie db.py z ingestion (wspolne polaczenie + .env)
INGESTION_DIR = Path(__file__).resolve().parents[1] / "ingestion"
sys.path.insert(0, str(INGESTION_DIR))

import db


def _drain_dbms_output(cursor) -> None:
    """Wypisuje bufor DBMS_OUTPUT (log z procedur p_gen_/p_run_)."""
    line = cursor.var(str)
    status = cursor.var(int)
    while True:
        cursor.callproc("dbms_output.get_line", (line, status))
        if status.getvalue() != 0:
            break
        print(line.getvalue())


def main(schemas: list[str], min_pct: int, min_del: int) -> None:
    with db.get_connection() as conn, conn.cursor() as cur:
        cur.callproc("dbms_output.enable", (None,))   # None = bufor bez limitu

        # 1) czyscimy kolejke exec (tymczasowa tabela sql_exec_queue)
        cur.callproc("maintenance.pkg_maintenance.p_clear_queue")

        # 2) generujemy kandydatow per schemat (dopisuja do tej samej kolejki)
        for sch in schemas:
            cur.callproc(
                "maintenance.pkg_maintenance.p_gen_index_rebuild_schema",
                [sch, min_pct, min_del],
            )

        # 3) wykonujemy kolejke (rebuild + log do sql_exec_queue_log).
        #    p_run_compress_queue rzuca blad gdy cokolwiek padlo -> drain w finally,
        #    zeby log DBMS_OUTPUT wypisal sie ZAWSZE, a wyjatek i tak wyleci po nim.
        try:
            cur.callproc("maintenance.pkg_maintenance.p_run_compress_queue")
        finally:
            _drain_dbms_output(cur)

    print(f"Index maintenance: zakonczono (schemas={schemas}, "
          f"min_pct={min_pct}, min_del={min_del}).")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(
        description="Konserwacja indeksow SILVER/GOLD (rebuild + kompresja wg progow)."
    )
    parser.add_argument(
        "--schemas",
        nargs="+",
        default=["SILVER", "GOLD", 'MAINTENANCE'],
        help="Schematy do przeszukania. Domyslnie: SILVER GOLD.",
    )
    parser.add_argument(
        "--min-pct",
        type=int,
        default=15,
        help="Prog PCTSAVE (%% oszczednosci z kompresji). Domyslnie 15.",
    )
    parser.add_argument(
        "--min-del",
        type=int,
        default=15,
        help="Prog del_pct (%% pustych wpisow po DELETE). Domyslnie 15.",
    )
    args = parser.parse_args()
    main(
        schemas=[s.upper() for s in args.schemas],
        min_pct=args.min_pct,
        min_del=args.min_del,
    )