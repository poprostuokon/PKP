"""
run_operations.py
-----------------
Entrypoint: pobranie snapshotu operations (wszystkie strony) do TODO/DAILY/DATA.
Uruchamiaj z katalogu 'ingestion':  python run_operations.py
"""

from pkp_ingestion.domains.operations import run_operations

if __name__ == "__main__":
    run_operations()