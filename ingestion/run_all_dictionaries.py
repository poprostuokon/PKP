"""
run_all_dictionaries.py
-----------------------
Entrypoint: pobranie wszystkich slownikow DEF do TODO
(proste z DICTIONARY_ENDPOINTS + specjalne z SPECIAL_DICTIONARIES).
Uruchamiaj z katalogu 'ingestion':  python run_all_dictionaries.py
"""

from pkp_ingestion.domains.dictionaries import run_all_dictionaries

if __name__ == "__main__":
    run_all_dictionaries()