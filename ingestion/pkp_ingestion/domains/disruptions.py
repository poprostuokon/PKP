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


def fetch_disruptions(client, run_ts, day=None, date_from=None, date_to=None):
    cfg = DATA_ENDPOINTS["disruptions"]
    params  = build_params("disruptions", day, date_from, date_to)
    biz_day = business_date("disruptions", day, date_from)   # poczatek okna

    # nazwa: dla backfillu/zakresu (day lub date_from podany) -> data DANYCH;
    #        dla zwyklego nocnego runu -> data ingestii (jak dotad)
    name_date = biz_day.replace("-", "") if (day or date_from) else date.today().strftime("%Y%m%d")

    raw = client.get(cfg["endpoint"], params=params)
    filename = data_filename("disruptions", name_date, run_ts)
    out_path = write_raw(todo_data_dir(), filename, raw)
    print(f"OK  disruptions {params['dateFrom']}..{params['dateTo']} nazwa={name_date} -> {out_path}")
    return out_path


def run_disruptions(day=None, date_from=None, date_to=None):
    run_ts = datetime.now().strftime("%Y%m%d%H%M%S")
    fetch_disruptions(PkpApiClient(), run_ts, day, date_from, date_to)


if __name__ == "__main__":
    run_disruptions()