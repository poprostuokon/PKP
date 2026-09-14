"""
run_live.py
-----------
Entrypoint serwisu LIVE (pseudo-streaming). Odpala nieskonczona petle pollera:
pull -> validate -> diff vs STATE -> delta -> upload -> STATE -> DB-load, co TICK_SECONDS.
Uruchamiaj z katalogu 'ingestion':  python run_live.py
(albo jako modul:  python -m pkp_ingestion.live_poller)
"""

from pkp_ingestion.live_poller import main

if __name__ == "__main__":
    main()