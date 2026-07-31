"""
paths.py
--------
Jedyne zrodlo prawdy dla lokalnych sciezek i nazw plikow w strukturze Data.

TODO trzyma pliki luzno (bez folderu YYYYMMDD) - partycja po dacie nadawana
dopiero przy przenoszeniu do ARCHIVE/ERR (osobny skrypt).
"""

from pathlib import Path

from .settings import DATA_ROOT, ENV


def todo_dict_dir() -> Path:
    """Katalog na swiezo pobrane slowniki: Data/<ENV>/TODO/DAILY/DICT."""
    return DATA_ROOT / ENV / "TODO" / "DAILY" / "DICT"


def dict_filename(name: str, run_ts: str) -> str:
    """Nazwa pliku slownika: dict_<name>_<YYYYMMDDHH24MISS>.json."""
    return f"dict_{name}_{run_ts}.json"