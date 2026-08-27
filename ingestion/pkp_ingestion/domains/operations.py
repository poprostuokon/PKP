"""
operations.py
-------------
Pobieranie stanu wykonania (operations) i zapis surowego JSON do TODO/DAILY/DATA.

Operations jest PAGINOWANY i nie ma parametru daty - zwraca aktualny snapshot
("na teraz"), a operating date siedzi w danych. Pobieramy strona po stronie
i KAZDA strone zapisujemy jako osobny surowy plik (bronze bit w bit, bez sklejania).

Sterowanie petla: pole pagination.hasNextPage w odpowiedzi.
Struktura odpowiedzi (pola pelne): generatedAt, pagination, trains, stations.
"""

import json
from datetime import date, datetime
from pathlib import Path

from ..client.api_client import PkpApiClient
from ..client.config import DATA_ENDPOINTS
from ..params import build_params
from ..storage.local_writer import write_raw
from ..validation import validate_or_quarantine
from ..paths import todo_data_dir, data_filename


def fetch_operations(client: PkpApiClient, run_ts: str, ingest_date: str) -> list[Path]:
    """
    Pobiera wszystkie strony operations i zapisuje kazda jako osobny plik.
    ingest_date - YYYYMMDD do nazwy pliku = data INGESTII (dzis).
    Operations to snapshot "na teraz" (brak parametru daty w API); odpalany w nocy
    zawiera wczorajsze ukonczone kursy, ale plik nazywamy data runu.
    Zwraca liste zapisanych sciezek.
    """
    cfg = DATA_ENDPOINTS["operations"]
    base_params = build_params("operations")   # komplet parametrow z configu
    saved: list[Path] = []
    page = 1

    while True:
        params = {**base_params, "page": page}  # page = mechanika paginacji
        raw = client.get(cfg["endpoint"], params=params)

        # zapis surowy (bit w bit) - jedna strona = jeden plik
        filename = data_filename("operations", ingest_date, run_ts, page=page)
        raw = client.get(cfg["endpoint"], params=params)
        if not validate_or_quarantine("operations", raw, f"operations_{ingest_date}_p{page:03d}", run_ts):
            # zla strona -> pomijamy ja, ale petla leci dalej po nastepne strony
            pagination = json.loads(raw).get("pagination", {}) if raw else {}
            if not pagination.get("hasNextPage"): break
            page += 1; continue
        out_path = write_raw(todo_data_dir(), filename, raw)
        saved.append(out_path)

        # parsujemy WYLACZNIE do sterowania petla (zapisany plik pozostaje surowy)
        pagination = json.loads(raw).get("pagination", {})
        has_next = pagination.get("hasNextPage", False)
        print(f"OK  operations page {page}/{pagination.get('totalPages','?')} -> {out_path}")

        if not has_next:
            break
        page += 1

    return saved


def run_operations(ingest_date: str | None = None) -> None:
    """
    Pojedynczy przebieg operations (snapshot).
    ingest_date - YYYYMMDD do nazwy pliku; domyslnie dzisiaj (data runu).
    """
    ingest_date = ingest_date or date.today().strftime("%Y%m%d")
    run_ts = datetime.now().strftime("%Y%m%d%H%M%S")
    client = PkpApiClient()
    fetch_operations(client, run_ts, ingest_date)


if __name__ == "__main__":
    run_operations()