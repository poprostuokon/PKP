"""
paths.py
--------
Jedyne zrodlo prawdy dla lokalnych sciezek i nazw plikow w strukturze Data.
Odwzorowuje architektura_repo.drawio.

TODO trzyma pliki luzno (bez folderu YYYYMMDD) - partycja po dacie nadawana
dopiero przy przenoszeniu do ARCHIVE/ERR (osobny skrypt).
"""

import re
from pathlib import Path

from .settings import DATA_ROOT, ENV

# Run timestamp (14 cyfr) jest w KAZDEJ nazwie pliku - z niego bierzemy date partycji.
_TS_RE = re.compile(r"(\d{14})")


def todo_dict_dir() -> Path:
    """Katalog na swiezo pobrane slowniki: Data/<ENV>/TODO/DAILY/DICT."""
    return DATA_ROOT / ENV / "TODO" / "DAILY" / "DICT"


def dict_filename(name: str, run_ts: str) -> str:
    """Nazwa pliku slownika: dict_<name>_<YYYYMMDDHH24MISS>.json."""
    return f"dict_{name}_{run_ts}.json"


def todo_data_dir() -> Path:
    """Katalog na swiezo pobrane dane dzienne: Data/<ENV>/TODO/DAILY/DATA."""
    return DATA_ROOT / ENV / "TODO" / "DAILY" / "DATA"


def data_filename(name: str, biz_date: str, run_ts: str, page: int | None = None) -> str:
    """
    Nazwa pliku danych dziennych.
      <name>_<biz_date>_<run_ts>.json                (bez paginacji)
      <name>_<biz_date>_<run_ts>_p<NNN>.json         (jedna strona z paginacji)
    biz_date - data biznesowa w formacie YYYYMMDD (widoczna w nazwie dla czytelnosci).
    """
    base = f"{name}_{biz_date}_{run_ts}"
    if page is not None:
        base += f"_p{page:03d}"
    return base + ".json"


# --- Upload: mapowanie pliku TODO -> sciezka w buckecie + lokalne ARCHIVE/ERR ---

def parse_filename(filename: str) -> tuple[str, str, str]:
    """
    Wyciaga (kategoria, podtyp, data_YYYYMMDD) z nazwy pliku.
      dict_<name>_<ts>.json                 -> ("dict", <name>, ts[:8])
      <type>_<date>_<ts>[_pNNN].json        -> ("data", <type>, ts[:8])
    data partycji = pierwsze 8 cyfr run_ts (data ingestii).
    """
    stem = filename[:-5] if filename.endswith(".json") else filename
    m = _TS_RE.search(stem)
    if not m:
        raise ValueError(f"Brak run_ts w nazwie pliku: {filename}")
    ts = m.group(1)
    part_date = ts[:8]

    if stem.startswith("dict_"):
        # nazwa slownika = to co miedzy 'dict_' a '_<ts>' (moze zawierac '_')
        name = stem[len("dict_"):].rsplit(f"_{ts}", 1)[0]
        return "dict", name, part_date

    subtype = stem.split("_", 1)[0]   # schedules / operations / disruptions
    return "data", subtype, part_date


def bucket_object_name(filename: str) -> str:
    """
    Sciezka obiektu w buckecie:
      daily/dict/<name>/date=YYYYMMDD/<plik>
      daily/data/<type>/date=YYYYMMDD/<plik>
    """
    category, subtype, part_date = parse_filename(filename)
    return f"daily/{category}/{subtype}/date={part_date}/{filename}"


def bucket_prefix(category: str, name: str, part_date: str) -> str:
    """
    Prefiks folderu w buckecie dla danego feedu i dnia (do listowania obiektow):
      daily/<category>/<name>/date=YYYYMMDD/
    """
    return f"daily/{category}/{name}/date={part_date}/"


def archive_dir(part_date: str) -> Path:
    """Lokalny katalog na pliki wgrane pomyslnie: Data/<ENV>/ARCHIVE/DAILY/<YYYYMMDD>."""
    return DATA_ROOT / ENV / "ARCHIVE" / "DAILY" / part_date


def err_dir(part_date: str) -> Path:
    """Lokalny katalog na pliki nieudane: Data/<ENV>/ERR/DAILY/<YYYYMMDD>."""
    return DATA_ROOT / ENV / "ERR" / "DAILY" / part_date


def err_filename(run_ts: str) -> str:
    """Plik sladu bledow danego przebiegu uploadu: err_<YYYYMMDDHH24MISS>.txt."""
    return f"err_{run_ts}.txt"

def ingest_err_dir(part_date: str) -> Path:
    """Payloady odrzucone przez walidacje: Data/<ENV>/ERR/INGEST/<YYYYMMDD>."""
    return DATA_ROOT / ENV / "ERR" / "INGEST" / part_date