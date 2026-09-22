"""
schedules.py
------------
Pobieranie rozkladu (schedules) na dany dzien i zapis surowego JSON do TODO/DAILY/DATA.

Wszystkie parametry (lacznie z data) deklarowane sa w config.DATA_ENDPOINTS.
params.build_params() podstawia realna date za token {day}. Schedules nie jest
paginowany - jedna odpowiedz = jeden plik.
"""

from datetime import datetime, date

from ..client.api_client import PkpApiClient
from ..client.config import DATA_ENDPOINTS
from ..params import build_params, business_date
from ..paths import data_filename, todo_data_dir
from ..prune import keep_latest_todo
from ..storage.local_writer import write_raw
from ..validation import validate_or_quarantine


def fetch_schedules(client, run_ts, day=None, date_from=None, date_to=None):
    cfg = DATA_ENDPOINTS["schedules"]
    params  = build_params("schedules", day, date_from, date_to)
    biz_day = business_date("schedules", day, date_from) or date.today().isoformat()

    filename = data_filename("schedules", biz_day.replace("-", ""), run_ts)
    raw = client.get(cfg["endpoint"], params=params)
    if not validate_or_quarantine("schedules", raw, f"schedules_{biz_day}", run_ts):
        return None
    
    out_path = write_raw(todo_data_dir(), filename, raw)
    keep_latest_todo(todo_data_dir(), "schedules")
    print(f"OK  schedules {biz_day} ({params['dateFrom']}..{params['dateTo']}) -> {out_path}")
    return out_path

def run_schedules(day=None, date_from=None, date_to=None):
    run_ts = datetime.now().strftime("%Y%m%d%H%M%S")
    fetch_schedules(PkpApiClient(), run_ts, day, date_from, date_to)


if __name__ == "__main__":
    run_schedules()