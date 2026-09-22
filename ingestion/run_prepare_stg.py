"""
run_prepare_stg.py
------------------
Entrypoint: zapelnia landing STG danymi z bucketu - tylko NOWE pliki dnia
(gate przez stg_load_log; feed z nowa delta: truncate + load, bez nowych: pominiety).
Uruchamiaj z katalogu 'ingestion':  python run_prepare_stg.py
(opcjonalnie prepare_stg(conn, "20260731") dla konkretnego dnia)
"""

import db
from pkp_ingestion.stg_load import prepare_stg

if __name__ == "__main__":
    with db.get_connection() as conn:
        prepare_stg(conn)