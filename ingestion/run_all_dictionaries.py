"""
run_all_dictionaries.py
-----------------------
Entrypoint: pobranie wszystkich slownikow DEF do TODO
(5 z bezposrednim endpointem + 2 specjalne).
Uruchamiaj z katalogu 'ingestion':  python run_all_dictionaries.py
"""

from pkp_ingestion.domains.dictionaries import run_all_dictionaries

if __name__ == "__main__":
    run_all_dictionaries()