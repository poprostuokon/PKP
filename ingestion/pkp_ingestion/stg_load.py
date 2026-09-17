"""
stg_load.py
-----------
prepare_stg: zapelnia tabele landing STG danymi z bucketu - TYLKO nowe pliki dnia.

Zasady:
  * Gate przez maintenance.stg_load_log (object_name = klucz). Plik juz LOADED -> pomijamy.
  * Landing = scratch: dla kazdego feedu TRUNCATE, potem ladujemy WYLACZNIE delte
    (pliki jeszcze nie LOADED). Feed bez nowych plikow -> pusty (delta = 0).
  * Commit PER plik (izolacja bledu): zly plik nie blokuje dobrych.
  * FAILED nie jest LOADED -> przy kolejnym przebiegu jest automatycznie retryowany.
  * Zapis do land_* i wpis LOADED sa w jednej transakcji (wspolny commit per plik).

Polaczenie do bazy jest wstrzykiwane z zewnatrz (db.get_connection()),
zeby ten modul nie byl zwiazany z konkretnym zrodlem polaczenia.
"""

from datetime import date, datetime, timedelta, timezone

import oracledb

from .client.config import DATA_ENDPOINTS, DICTIONARY_ENDPOINTS, SPECIAL_DICTIONARIES
from .paths import bucket_prefix, bucket_prefix_live
from .settings import OCI_BUCKET_LIVE
from .storage.oci_reader import OciReader

# Feedy = (kategoria w buckecie, nazwa feedu == czlon nazwy tabeli land_<name>)
DICT_FEEDS = list(DICTIONARY_ENDPOINTS) + list(SPECIAL_DICTIONARIES)
DATA_FEEDS = list(DATA_ENDPOINTS)

# feedy live = tylko dane operacyjne (bez slownikow)
LIVE_FEEDS = ("operations", "disruptions")


def _iter_feeds():
    for name in DICT_FEEDS:
        yield "dict", name
    for name in DATA_FEEDS:
        yield "data", name


def _loaded_objects(cur, prefix: str) -> set[str]:
    """object_name juz oznaczone LOADED dla danego prefiksu dnia/feedu."""
    cur.setinputsizes()  # bez bindu CLOB z ewentualnej poprzedniej iteracji
    cur.execute(
        "SELECT object_name FROM maintenance.stg_load_log "
        "WHERE status = 'LOADED' AND object_name LIKE :p",
        p=prefix + "%",
    )
    return {row[0] for row in cur.fetchall()}



def _log_manifest(cur, object_name, feed, load_mode, part_date, status, nbytes, err_msg):
    cur.setinputsizes()
    # najpierw UPDATE
    cur.execute(
        """UPDATE maintenance.stg_load_log
           SET status=:st, bytes=:b, err_msg=:em, loaded_at=:ts,
               feed=:fd, load_mode=:lm, part_date=:pd
           WHERE object_name=:obj""",
        obj=object_name, fd=feed, lm=load_mode,
        pd=datetime.strptime(part_date, "%Y%m%d").date(),
        st=status, b=nbytes, em=err_msg, ts=datetime.now(timezone.utc),
    )
    if cur.rowcount == 0:               # nie było — wstaw
        cur.execute(
            """INSERT INTO maintenance.stg_load_log
               (object_name, feed, load_mode, part_date, status, bytes, err_msg, loaded_at)
               VALUES (:obj,:fd,:lm,:pd,:st,:b,:em,:ts)""",
            obj=object_name, fd=feed, lm=load_mode,
            pd=datetime.strptime(part_date, "%Y%m%d").date(),
            st=status, b=nbytes, em=err_msg, ts=datetime.now(timezone.utc),
        )


def prepare_stg(connection, day: str | None = None, load_mode: str = "DAILY") -> None:
    """
    Zapelnia landing z bucketu tylko NOWYMI plikami dnia.
    day       - YYYYMMDD; domyslnie dzis (pliki nazwane data ingestii).
    load_mode - DAILY / LIVE (zapisywane w manifescie).
    connection - otwarte polaczenie oracledb (np. z db.get_connection()).
    """
    part_date = day or date.today().strftime("%Y%m%d")
    reader = OciReader()
    cur = connection.cursor()

    for category, name in _iter_feeds():
        table = f"land_{name}"
        prefix = bucket_prefix(category, name, part_date)

        # 1) listujemy pliki w buckecie - brak pliku => feed pomijamy (bez TRUNCATE)
        objects = reader.list_objects(prefix)
        if not objects:
            print(f"--  stg.{table:26} pominieto (brak pliku)  [{prefix}]")
            continue

        # 2) gate: bierzemy tylko to, czego jeszcze nie ma jako LOADED (FAILED tez retryujemy)
        already = _loaded_objects(cur, prefix)
        new_objects = [o for o in objects if o not in already]

        # 3) brak nowych -> landing tego feedu ma byc pusty (delta = 0)
        if not new_objects:
            print(f"==  stg.{table:26} pominieto (brak NOWYCH plikow)  [{prefix}]")
            continue

        # 4) sa nowe pliki -> czyscimy landing (scratch) i ladujemy WYLACZNIE delte
        cur.setinputsizes()
        cur.execute(f"TRUNCATE TABLE stg.{table}")
        connection.commit()

        ok = err = 0
        for object_name in new_objects:
            try:
                doc = reader.download_text(object_name)
                cur.setinputsizes(doc=oracledb.DB_TYPE_CLOB)  # duze JSON -> CLOB
                cur.execute(
                    f"INSERT INTO stg.{table} (payload) VALUES (JSON(:doc))",
                    doc=doc,
                )
                _log_manifest(cur, object_name, name, load_mode, part_date,
                              "LOADED", len(doc.encode("utf-8")), None)
                connection.commit()          # commit PER plik (sposob a): land + LOADED razem
                ok += 1
            except Exception as exc:         # izolacja bledu per plik
                connection.rollback()        # cofa tylko ten niepelny insert
                _log_manifest(cur, object_name, name, load_mode, part_date,
                              "FAILED", None, f"{exc.__class__.__name__}: {exc}"[:4000])
                connection.commit()          # FAILED zapisujemy osobno
                err += 1
                print(f"ERR stg.{table:26} <- {object_name} ({exc.__class__.__name__})")

        print(f"OK  stg.{table:26} <- {ok:>3} nowych (err={err})  [{prefix}]")

    cur.close()

def prepare_stg_live(connection, day: str | None = None) -> None:
    """
    Landing LIVE: laduje delty z bucketu live do stg.land_<feed>_live.
    - listuje DWIE partycje: dzis + wczoraj (przelom polnocy - delty z 23:5x
      siedza pod wczorajszym date=, a poller juz pisze pod dzisiejszym),
    - gate przez maintenance.stg_load_log (LOADED pomija, FAILED retry),
    - landing = scratch: TRUNCATE + wlanie WYLACZNIE delty,
    - commit per plik (izolacja bledu), manifest load_mode='LIVE'.
    """
    anchor = datetime.strptime(day, "%Y%m%d").date() if day else date.today()
    today_str = anchor.strftime("%Y%m%d")
    yday_str  = (anchor - timedelta(days=1)).strftime("%Y%m%d")

    reader = OciReader(bucket=OCI_BUCKET_LIVE)     # osobny bucket live
    cur = connection.cursor()

    for name in LIVE_FEEDS:
        table = f"land_{name}_live"

        # 1) listuj obie partycje (dzis + wczoraj); LOADED-gate i tak odsieje stare
        prefixes = [bucket_prefix_live("data", name, today_str),
                    bucket_prefix_live("data", name, yday_str)]
        objects: list[str] = []
        for p in prefixes:
            objects.extend(reader.list_objects(p))

        if not objects:
            print(f"--  stg.{table:28} pominieto (brak pliku)")
            continue

        # 2) gate: tylko jeszcze nie-LOADED (FAILED tez retryujemy) - sprawdzamy oba prefiksy
        already: set[str] = set()
        for p in prefixes:
            already |= _loaded_objects(cur, p)
        new_objects = [o for o in objects if o not in already]

        if not new_objects:
            print(f"==  stg.{table:28} pominieto (brak NOWYCH plikow)")
            continue

        # 3) scratch: czyscimy landing i ladujemy WYLACZNIE delte
        cur.setinputsizes()
        cur.execute(f"TRUNCATE TABLE stg.{table}")
        connection.commit()

        ok = err = 0
        for object_name in new_objects:
            # part_date do manifestu = data z prefiksu pliku (date=YYYYMMDD w object_name)
            obj_part = _part_date_from_object(object_name, today_str)
            try:
                doc = reader.download_text(object_name)
                cur.setinputsizes(doc=oracledb.DB_TYPE_CLOB)
                cur.execute(
                    f"INSERT INTO stg.{table} (payload) VALUES (JSON(:doc))",
                    doc=doc,
                )
                _log_manifest(cur, object_name, name, "LIVE", obj_part,
                              "LOADED", len(doc.encode("utf-8")), None)
                connection.commit()
                ok += 1
            except Exception as exc:
                connection.rollback()
                _log_manifest(cur, object_name, name, "LIVE", obj_part,
                              "FAILED", None, f"{exc.__class__.__name__}: {exc}"[:4000])
                connection.commit()
                err += 1
                print(f"ERR stg.{table:28} <- {object_name} ({exc.__class__.__name__})")

        print(f"OK  stg.{table:28} <- {ok:>3} nowych (err={err})")

    cur.close()


def _part_date_from_object(object_name: str, fallback: str) -> str:
    """Wyciaga YYYYMMDD z fragmentu 'date=YYYYMMDD/' w object_name (manifest part_date)."""
    import re
    m = re.search(r"date=(\d{8})/", object_name)
    return m.group(1) if m else fallback