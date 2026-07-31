"""
run_disruptions.py
------------------
Entrypoint: pobranie disruptions za wczoraj (D-1) do TODO/DAILY/DATA.
Uruchamiaj z katalogu 'ingestion':  python run_disruptions.py
(opcjonalnie run_disruptions("2026-07-30") dla konkretnego dnia)
"""

from pkp_ingestion.domains.disruptions import run_disruptions

if __name__ == "__main__":
    run_disruptions()