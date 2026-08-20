"""
stg_load.py
-----------
prepare_stg: zapelnia tabele landing STG danymi z bucketu.

Dla kazdego feedu:
  1. TRUNCATE stg.land_<feed>           (scratch - czyscimy przed ladowaniem)
  2. listuje pliki w buckecie pod prefiksem dnia
  3. pobiera KAZDY plik i wstawia CALY dokument JSON jako 1 wiersz (payload)

Polaczenie do bazy jest wstrzykiwane z zewnatrz (db.get_connection()),
zeby ten modul nie byl zwiazany z konkretnym zrodlem polaczenia.
"""

from datetime import date

import oracledb

from .storage.oci_reader import OciReader
from .paths import bucket_prefix
from .client.config import DICTIONARY_ENDPOINTS, SPECIAL_DICTIONARIES, DATA_ENDPOINTS

# Feedy = (kategoria w buckecie, nazwa feedu == czlon nazwy tabeli land_<name>)
DICT_FEEDS = list(DICTIONARY_ENDPOINTS) + list(SPECIAL_DICTIONARIES)
DATA_FEEDS = list(DATA_ENDPOINTS)


def _iter_feeds():
    for name in DICT_FEEDS:
        yield "dict", name
    for name in DATA_FEEDS:
        yield "data", name


def prepare_stg(connection, day: str | None = None) -> None:
    """
    Zapelnia wszystkie landing z bucketu.
    day - YYYYMMDD; domyslnie dzis (pliki nazwane data ingestii).
    connection - otwarte polaczenie oracledb (np. z db.get_connection()).
    """
    part_date = day or date.today().strftime("%Y%m%d")
    reader = OciReader()
    cur = connection.cursor()

    for category, name in _iter_feeds():
        table = f"land_{name}"
        prefix = bucket_prefix(category, name, part_date)

        # 1) listujemy pliki - jesli brak, POMIJAMY feed (bez TRUNCATE, landing nietkniety)
        objects = reader.list_objects(prefix)
        if not objects:
            print(f"--  stg.{table:26} pominieto (brak pliku)  [{prefix}]")
            continue

        # wyczysc ewentualny bind ':doc' z poprzedniej iteracji
        # (setinputsizes utrzymuje sie na kursorze -> TRUNCATE bez :doc rzucilby DPY-4008)
        cur.setinputsizes()

        # 2) czyscimy landing (scratch) - tylko gdy sa pliki do zaladowania
        cur.execute(f"TRUNCATE TABLE stg.{table}")

        # 3) pobieramy i wstawiamy caly dokument jako 1 wiersz
        # duze dokumenty JSON (np. stations) przekraczaja limit VARCHAR2 -> bind jako CLOB
        cur.setinputsizes(doc=oracledb.DB_TYPE_CLOB)
        for object_name in objects:
            doc = reader.download_text(object_name)
            cur.execute(
                f"INSERT INTO stg.{table} (payload) VALUES (JSON(:doc))",
                doc=doc,
            )
        connection.commit()
        print(f"OK  stg.{table:26} <- {len(objects):>3} plik(ow)  [{prefix}]")

    cur.close()