"""
apikey.py
---------
Sprawdzanie limitu i zuzycia klucza API (endpointy administracyjne).
Nie zapisuje do bronze - to dane operacyjne (do raportu / monitoringu w Airflow).

  usage -> biezace zuzycie z limitu
  info  -> info o kluczu (tier, limity)
"""

import json

from ..client.api_client import PkpApiClient
from ..client.config import APIKEY_ENDPOINTS


def get_usage() -> dict:
    """Pobiera i zwraca statystyki zuzycia klucza API (oraz wypisuje na stdout)."""
    return _get_and_print("usage")


def get_info() -> dict:
    """Pobiera i zwraca informacje o kluczu API (tier, limity)."""
    return _get_and_print("info")


def _get_and_print(name: str) -> dict:
    client = PkpApiClient()
    raw = client.get(APIKEY_ENDPOINTS[name])
    data = json.loads(raw)
    print(f"=== apikey/{name} ===")
    print(json.dumps(data, indent=2, ensure_ascii=False))
    return data


if __name__ == "__main__":
    get_info()
    get_usage()