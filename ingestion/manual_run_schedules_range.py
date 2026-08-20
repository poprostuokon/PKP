"""
run_schedules_range.py
----------------------
Przyklad: pobranie schedules dla ZAKRESU dat (dateFrom..dateTo) do TODO/DAILY/DATA.
Standardowy run_schedules bierze jeden dzien; ten skrypt pozwala podac zakres.
Uruchamiaj z katalogu 'ingestion':  python run_schedules_range.py
"""

from datetime import datetime

from pkp_ingestion.client.api_client import PkpApiClient
from pkp_ingestion.client.config import DATA_ENDPOINTS, DATE_TOKEN
from pkp_ingestion.storage.local_writer import write_raw
from pkp_ingestion.paths import todo_data_dir, data_filename

# --- USTAW ZAKRES ---
DATE_FROM = "2026-08-19"      # YYYY-MM-DD
DATE_TO   = "2026-08-20"      # YYYY-MM-DD


def main() -> None:
    cfg = DATA_ENDPOINTS["schedules"]

    # stale parametry z configu (stations, fullRoute, dictionaries),
    # pomijamy tokeny dat, bo podajemy je jawnie:
    params = {k: v for k, v in cfg["params"].items() if v != DATE_TOKEN}
    params["dateFrom"] = DATE_FROM
    params["dateTo"]   = DATE_TO

    run_ts = datetime.now().strftime("%Y%m%d%H%M%S")
    raw = PkpApiClient().get(cfg["endpoint"], params=params)

    # nazwa pliku: data poczatkowa zakresu jako biz_date
    filename = data_filename("schedules", DATE_FROM.replace("-", ""), run_ts)
    out = write_raw(todo_data_dir(), filename, raw)
    print(f"OK  schedules {DATE_FROM}..{DATE_TO} -> {out}")


if __name__ == "__main__":
    main()
