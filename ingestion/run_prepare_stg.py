"""
run_prepare_stg.py
------------------
Entrypoint: zapelnia tabele landing STG danymi z bucketu (truncate + load).
Uruchamiaj z katalogu 'ingestion':  python run_prepare_stg.py
(opcjonalnie prepare_stg(conn, "20260731") dla konkretnego dnia)
"""

import db
from pkp_ingestion.stg_load import prepare_stg

if __name__ == "__main__":
    with db.get_connection() as conn:
        prepare_stg(conn)