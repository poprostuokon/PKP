"""
validation.py
-------------
Walidacja struktury surowej odpowiedzi API PRZED zapisem do TODO (fail-fast na wejsciu).
Kazdy feed ma swoj plik schematu w schemas/schema_<feed>.json.

Uzycie w domenie (jedna linijka zamiast bloku try/except):

    raw = client.get(cfg["endpoint"], params=params)
    if not validate_or_quarantine("schedules", raw, f"schedules_{biz_day}", run_ts):
        return None          # zly payload -> w kwarantannie, feed pominiety
    # ... payload OK -> write_raw(...)
"""

import json
from datetime import date
from functools import lru_cache
from pathlib import Path

from jsonschema import validate as _js_validate
from jsonschema import ValidationError

from .paths import ingest_err_dir

SCHEMA_DIR = Path(__file__).resolve().parent / "schemas"

# feed (czlon nazwy pliku / tabeli) -> plik schematu
SCHEMA_MAP = {
    "schedules":             "schema_schedules.json",
    "operations":            "schema_operations.json",
    "disruptions":           "schema_disruptions.json",
    "carriers":              "schema_carriers.json",
    "cities":                "schema_cities.json",
    "stations":              "schema_stations.json",
    "commercial_categories": "schema_commercial_categories.json",
    "stop_types":            "schema_stop_types.json",
    "disruption_types":      "schema_disruption_types.json",
    "train_statuses":        "schema_train_statuses.json",
}


@lru_cache(maxsize=None)
def _load_schema(feed: str) -> dict:
    fname = SCHEMA_MAP.get(feed)
    if fname is None:
        raise KeyError(f"Brak schematu dla feedu '{feed}' w SCHEMA_MAP")
    return json.loads((SCHEMA_DIR / fname).read_text(encoding="utf-8"))


def validate_payload(feed: str, raw_text: str) -> None:
    """
    Waliduje surowy JSON (tekst) wg schematu feedu.
    Rzuca ValidationError (struktura) lub ValueError (niepoprawny JSON).
    """
    try:
        data = json.loads(raw_text)
    except json.JSONDecodeError as exc:
        raise ValueError(f"Feed '{feed}': niepoprawny JSON - {exc}") from exc
    _js_validate(instance=data, schema=_load_schema(feed))


def validate_or_quarantine(feed: str, raw_text: str, name_base: str, run_ts: str) -> bool:
    """
    Waliduje payload. Zwraca:
      True  -> OK, mozna zapisywac do TODO.
      False -> zly payload; surowy JSON + powod zapisane do ERR/INGEST/<data>,
               feed nalezy pominac (return None u wolajacego).

    name_base - baza nazwy pliku bez rozszerzenia, np. 'schedules_2026-08-20'
                lub 'operations_20260820_p001' (dla paginacji dodaj numer strony).
    """
    try:
        validate_payload(feed, raw_text)
        return True
    except (ValidationError, ValueError) as exc:
        part_date = date.today().strftime("%Y%m%d")
        qdir = ingest_err_dir(part_date)
        qdir.mkdir(parents=True, exist_ok=True)
        safe = name_base.replace(":", "").replace("/", "_")
        (qdir / f"{safe}_{run_ts}.bad.json").write_text(raw_text, encoding="utf-8")
        (qdir / f"{safe}_{run_ts}.err.txt").write_text(
            f"{exc.__class__.__name__}: {exc}", encoding="utf-8"
        )
        print(f"ERR  {feed} walidacja: {exc.__class__.__name__} -> kwarantanna [{qdir}]")
        return False
