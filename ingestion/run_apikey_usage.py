"""
run_apikey_usage.py
-------------------
Entrypoint: wypisuje info o kluczu API i biezace zuzycie limitu.
Uruchamiaj z katalogu 'ingestion':  python run_apikey_usage.py
"""

from pkp_ingestion.domains.apikey import get_info, get_usage

if __name__ == "__main__":
    get_info()
    get_usage()