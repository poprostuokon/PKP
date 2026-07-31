"""
api_client.py
-------------
Cienki klient HTTP do PKP PLK API.
Trzyma jedna sesje z naglowkiem X-API-Key i udostepnia metode get().
Zwraca surowy tekst odpowiedzi (bronze = bez modyfikacji tresci).

Retry: bledy przejsciowe (429 + 5xx) oraz bledy sieciowe sa ponawiane
z wykladniczym backoffem. Na 429/503 uszanowany jest naglowek Retry-After.
Bledy 4xx (poza 429) i wyczerpanie prob -> wyjatek.
"""

import time

import requests

from ..settings import API_KEY
from .config import (
    BASE_URL,
    DEFAULT_TIMEOUT,
    RETRY_MAX_ATTEMPTS,
    RETRY_BACKOFF_BASE,
    RETRYABLE_STATUS,
)


class PkpApiClient:
    def __init__(self, api_key: str = API_KEY, base_url: str = BASE_URL):
        self.base_url = base_url.rstrip("/")
        self.session = requests.Session()
        self.session.headers.update({"X-API-Key": api_key})

    def get(self, endpoint: str, params: dict | None = None,
            timeout: int = DEFAULT_TIMEOUT) -> str:
        """
        GET na <base_url><endpoint> z retry. Zwraca surowy tekst odpowiedzi.
        """
        url = f"{self.base_url}{endpoint}"
        last_exc: Exception | None = None

        for attempt in range(1, RETRY_MAX_ATTEMPTS + 1):
            try:
                response = self.session.get(url, params=params, timeout=timeout)

                # Sukces -> zwracamy surowy tekst
                if response.status_code < 400:
                    return response.text

                # Blad przejsciowy -> ponawiamy (jesli zostaly proby)
                if response.status_code in RETRYABLE_STATUS and attempt < RETRY_MAX_ATTEMPTS:
                    delay = self._retry_delay(attempt, response)
                    print(f"WARN {endpoint} status {response.status_code}, "
                          f"proba {attempt}/{RETRY_MAX_ATTEMPTS}, ponawiam za {delay:.1f}s")
                    time.sleep(delay)
                    continue

                # Blad nieponawialny (4xx poza 429) lub wyczerpane proby -> wyjatek
                response.raise_for_status()

            except (requests.ConnectionError, requests.Timeout) as exc:
                # Bledy sieciowe traktujemy jak przejsciowe
                last_exc = exc
                if attempt < RETRY_MAX_ATTEMPTS:
                    delay = RETRY_BACKOFF_BASE * (2 ** (attempt - 1))
                    print(f"WARN {endpoint} blad sieci ({exc.__class__.__name__}), "
                          f"proba {attempt}/{RETRY_MAX_ATTEMPTS}, ponawiam za {delay:.1f}s")
                    time.sleep(delay)
                    continue
                raise

        # Nie powinno tu dojsc, ale dla pewnosci:
        if last_exc:
            raise last_exc
        raise RuntimeError(f"GET {endpoint} nieudany po {RETRY_MAX_ATTEMPTS} probach")

    def _retry_delay(self, attempt: int, response: requests.Response) -> float:
        """
        Opoznienie przed kolejna proba.
        Preferuje naglowek Retry-After (sekundy); inaczej wykladniczy backoff.
        """
        retry_after = response.headers.get("Retry-After")
        if retry_after:
            try:
                return float(retry_after)
            except ValueError:
                pass  # Retry-After moze byc data HTTP - pomijamy, backoff nizej
        return RETRY_BACKOFF_BASE * (2 ** (attempt - 1))