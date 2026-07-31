"""
run_schedules.py
----------------
Entrypoint: pobranie schedules na dzisiaj do TODO/DAILY/DATA.
Uruchamiaj z katalogu 'ingestion':  python run_schedules.py
(opcjonalnie mozna wywolac run_schedules("2026-07-31") dla konkretnego dnia)
"""

from pkp_ingestion.domains.schedules import run_schedules

if __name__ == "__main__":
    run_schedules()