"""
dictionaries.py
---------------
Pobieranie slownikow DEF i zapis surowego JSON do TODO.

Dwa rodzaje slownikow:
  1. z bezposrednim endpointem  -> config.DICTIONARY_ENDPOINTS (proste GET)
  2. specjalne, bez wlasnego endpointu -> config.SPECIAL_DICTIONARIES
     (disruption_types, train_statuses - wyciagane przy okazji innego zapytania)

Wzorzec jest generyczny: _fetch_and_save() robi GET + zapis surowego JSON do TODO.
Dodanie kolejnego prostego slownika = jedna pozycja w mapie endpointow.

Na start: run_carriers (tylko carriers). run_all_dictionaries obejmuje wszystkie.
"""

from datetime import datetime
from pathlib import Path

from ..client.api_client import PkpApiClient
from ..client.config import DICTIONARY_ENDPOINTS, SPECIAL_DICTIONARIES
from ..storage.local_writer import write_raw
from ..validation import validate_or_quarantine
from ..prune import keep_latest_todo
from ..paths import todo_dict_dir, dict_filename



def fetch_dictionary(name, cfg, client, run_ts):
    """
    Uniwersalny pobieracz: dziala dla kazdego wpisu o ksztalcie
    {"endpoint": ..., "params": ...} - niezaleznie czy to slownik prosty
    czy specjalny. GET -> surowy tekst -> zapis do TODO/DAILY/DICT.
    """
    raw = client.get(cfg["endpoint"], params=cfg["params"])

    # walidacja: 'name' to feed (carriers/cities/disruption_types/...) = klucz w SCHEMA_MAP
    if not validate_or_quarantine(name, raw, f"dict_{name}", run_ts):
        return None   # zly slownik -> w kwarantannie, pomijamy

    out_path = write_raw(todo_dict_dir(), dict_filename(name, run_ts), raw)
    keep_latest_todo(todo_dict_dir(), name)
    print(f"OK  {name:22} -> {out_path}")
    return out_path


def run_carriers() -> None:
    """Pojedynczy przebieg: tylko slownik carriers."""
    run_ts = datetime.now().strftime("%Y%m%d%H%M%S")
    client = PkpApiClient()
    fetch_dictionary("carriers", DICTIONARY_ENDPOINTS["carriers"], client, run_ts)


def run_all_dictionaries() -> None:
    """
    Pelny przebieg wszystkich slownikow DEF (proste + specjalne).
    Oba maps maja identyczny ksztalt wpisu, wiec obslugujemy je tak samo.
    Wszystkie pliki z jednego przebiegu dostaja ten sam run_ts.
    """
    run_ts = datetime.now().strftime("%Y%m%d%H%M%S")
    client = PkpApiClient()

    for name, cfg in {**DICTIONARY_ENDPOINTS, **SPECIAL_DICTIONARIES}.items():
        fetch_dictionary(name, cfg, client, run_ts)


if __name__ == "__main__":
    run_all_dictionaries()