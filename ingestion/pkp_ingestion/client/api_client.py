"""
api_client.py
-------------
Cienki klient HTTP do PKP PLK API.
Trzyma jedna sesje z naglowkiem X-API-Key i udostepnia metode get().
Zwraca surowy tekst odpowiedzi (bronze = bez modyfikacji tresci).

Happy-path: raise_for_status przy bledzie HTTP. Retry/backoff dokladamy pozniej.
"""

import requests

from ..settings import API_KEY
from .config import BASE_URL, DEFAULT_TIMEOUT


class PkpApiClient:
    def __init__(self, api_key: str = API_KEY, base_url: str = BASE_URL):
        self.base_url = base_url.rstrip("/")
        self.session = requests.Session()
        self.session.headers.update({"X-API-Key": api_key})

    def get(self, endpoint: str, params: dict | None = None,
            timeout: int = DEFAULT_TIMEOUT) -> str:
        """
        Wykonuje GET na <base_url><endpoint> i zwraca surowy tekst odpowiedzi.
        params - opcjonalne parametry query (np. dictionaries=true).
        """
        url = f"{self.base_url}{endpoint}"
        response = self.session.get(url, params=params, timeout=timeout)
        response.raise_for_status()
        return response.text