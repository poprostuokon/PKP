"""
disruptions.py
--------------
Pobieranie utrudnien (disruptions) za dany dzien i zapis surowego JSON do TODO/DAILY/DATA.

Wszystkie parametry (lacznie z data) deklarowane sa w config.DATA_ENDPOINTS.
Domyslnie D-1 (default_day="yesterday") - skrypt uruchamiany w nocy po.
Bez paginacji: jedna odpowiedz = jeden plik.
"""

from datetime import date, datetime
from pathlib import Path

from ..client.api_client import PkpApiClient
from ..client.config import DATA_ENDPOINTS
from ..params import build_params, business_date
from ..storage.local_writer import write_raw
from ..paths import todo_data_dir, data_filename


def fetch_disruptions(client: PkpApiClient, run_ts: str, day: str | None = None) -> Path:
    """
    Pobiera disruptions dla dnia zapytania (domyslnie wczoraj wg config.default_day),
    ale NAZWA pliku uzywa daty INGESTII (dzis) - bo skrypt odpalamy w nocy po.
    day - YYYY-MM-DD; None => wartosc z configu.
    """
    cfg = DATA_ENDPOINTS["disruptions"]
    params = build_params("disruptions", day)
    query_day = business_date("disruptions", day)     # dzien danych (wczoraj)
    ingest_date = date.today().strftime("%Y%m%d")      # dzien runu (nazwa pliku)

    raw = client.get(cfg["endpoint"], params=params)

    filename = data_filename("disruptions", ingest_date, run_ts)
    out_path = write_raw(todo_data_dir(), filename, raw)
    print(f"OK  disruptions dane={query_day} nazwa={ingest_date} -> {out_path}")
    return out_path


def run_disruptions(day: str | None = None) -> None:
    """Pojedynczy przebieg disruptions. day - YYYY-MM-DD; domyslnie wg configu (wczoraj)."""
    run_ts = datetime.now().strftime("%Y%m%d%H%M%S")
    client = PkpApiClient()
    fetch_disruptions(client, run_ts, day)


if __name__ == "__main__":
    run_disruptions()