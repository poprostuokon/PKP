"""
schedules.py
------------
Pobieranie rozkladu (schedules) na dany dzien i zapis surowego JSON do TODO/DAILY/DATA.

Wszystkie parametry (lacznie z data) deklarowane sa w config.DATA_ENDPOINTS.
params.build_params() podstawia realna date za token {day}. Schedules nie jest
paginowany - jedna odpowiedz = jeden plik.
"""

from datetime import datetime
from pathlib import Path

from ..client.api_client import PkpApiClient
from ..client.config import DATA_ENDPOINTS
from ..params import build_params, business_date
from ..storage.local_writer import write_raw
from ..paths import todo_data_dir, data_filename


def fetch_schedules(client: PkpApiClient, run_ts: str, day: str | None = None) -> Path:
    """
    Pobiera schedules dla dnia (domyslnie dzis wg config.default_day) i zapisuje surowo.
    day - YYYY-MM-DD; None => wartosc z configu.
    """
    cfg = DATA_ENDPOINTS["schedules"]
    params = build_params("schedules", day)
    biz_day = business_date("schedules", day)          # YYYY-MM-DD

    raw = client.get(cfg["endpoint"], params=params)

    filename = data_filename("schedules", biz_day.replace("-", ""), run_ts)
    out_path = write_raw(todo_data_dir(), filename, raw)
    print(f"OK  schedules {biz_day} -> {out_path}")
    return out_path


def run_schedules(day: str | None = None) -> None:
    """Pojedynczy przebieg schedules. day - YYYY-MM-DD; domyslnie wg configu (dzis)."""
    run_ts = datetime.now().strftime("%Y%m%d%H%M%S")
    client = PkpApiClient()
    fetch_schedules(client, run_ts, day)


if __name__ == "__main__":
    run_schedules()