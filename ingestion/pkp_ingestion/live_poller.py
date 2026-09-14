"""
live_poller.py
--------------
Serwis LIVE (pseudo-streaming). Petla while True: pull -> stale-guard ->
diff vs STATE -> delta do TODO/LIVE/DATA -> upload -> STATE atomowo + ARCHIVE.
Heartbeat co tick (finally) -> lokalny spool -> DB best-effort.
Uruchomienie: python -m pkp_ingestion.live_poller
"""

import json
import time
import traceback
from datetime import datetime, timezone, date
from pathlib import Path

from .client.api_client import PkpApiClient
from .client.config import DATA_ENDPOINTS
from .params import build_params
from .validation import validate_or_quarantine
from .storage.local_writer import write_raw
from .paths import (
    todo_live_raw_dir, todo_live_data_dir, state_live_dir,
    raw_filename, state_filename, data_filename,
    err_live_dir,
)
from .live_diff import (
    load_state, save_state, diff_operations, diff_disruptions,
)
from .live_heartbeat import write_heartbeat

STATION_ID   = 60103
TICK_SECONDS = 180
FEEDS        = ("operations", "disruptions")


def _now_ts() -> str:
    return datetime.now().strftime("%Y%m%d%H%M%S")


def _process_operations(client, run_ts) -> tuple[str, int, float | None]:
    cfg    = DATA_ENDPOINTS["operations"]
    params = build_params("operations")                 # flaga szczegolow off w config
    raw    = client.get(cfg["endpoint"], params=params)

    if not validate_or_quarantine("operations_live", raw,
                                  f"operations_{date.today()}", run_ts,
                                  err_dir_fn=err_live_dir):
        return "ERR", 0, None

    curr = json.loads(raw)
    gen  = curr.get("generatedAt")

    state_path = state_live_dir() / state_filename("operations")
    prev = load_state(state_path)

    # stale-guard: odrzuc jesli generatedAt nie nowszy
    if prev.get("generatedAt") and gen and gen <= prev["generatedAt"]:
        return "STALE", 0, _lag(gen)

    # scratch RAW (nadpisywany)
    write_raw(todo_live_raw_dir(), raw_filename("operations"), raw)

    delta = diff_operations(prev.get("trains", []), curr.get("trains", []), STATION_ID)
    if not delta:
        save_state(state_path, curr)                   # brak zmian: STATE i tak = najswiezszy
        return "EMPTY", 0, _lag(gen)

    payload = {"generatedAt": gen, "trains": delta}
    fname   = data_filename("operations", date.today().strftime("%Y%m%d"), run_ts)
    write_raw(todo_live_data_dir(), fname, json.dumps(payload, ensure_ascii=False))

    save_state(state_path, curr)                        # checkpoint po zapisaniu delty do TODO
    return "OK", len(delta), _lag(gen)


def _process_disruptions(client, run_ts) -> tuple[str, int, float | None]:
    cfg    = DATA_ENDPOINTS["disruptions"]
    params = build_params("disruptions")               # 2 dni + stacja w config
    raw    = client.get(cfg["endpoint"], params=params)

    if not validate_or_quarantine("disruptions_live", raw,
                                  f"disruptions_{date.today()}", run_ts,
                                  err_dir_fn=err_live_dir):
        return "ERR", 0, None

    curr = json.loads(raw)
    gen  = curr.get("generatedAt")

    state_path = state_live_dir() / state_filename("disruptions")
    prev = load_state(state_path)

    if prev.get("generatedAt") and gen and gen <= prev["generatedAt"]:
        return "STALE", 0, _lag(gen)

    write_raw(todo_live_raw_dir(), raw_filename("disruptions"), raw)

    today = date.today().strftime("%Y-%m-%d")
    changed, ended = diff_disruptions(prev.get("disruptions", []),
                                      curr.get("disruptions", []),
                                      ended_min_date=today)   # tombstony tylko dla dzisiejszych
    if not changed and not ended:
        save_state(state_path, curr)
        return "EMPTY", 0, _lag(gen)

    payload = {"generatedAt": gen, "changed": changed, "ended": ended}
    fname   = data_filename("disruptions", date.today().strftime("%Y%m%d"), run_ts)
    write_raw(todo_live_data_dir(), fname, json.dumps(payload, ensure_ascii=False))

    save_state(state_path, curr)
    return "OK", len(changed) + len(ended), _lag(gen)


def _lag(gen: str | None) -> float | None:
    if not gen:
        return None
    try:
        g = datetime.fromisoformat(gen.replace("Z", "+00:00"))
        return (datetime.now(timezone.utc) - g).total_seconds()
    except ValueError:
        return None


_PROC = {"operations": _process_operations, "disruptions": _process_disruptions}


def run_cycle() -> None:
    client = PkpApiClient()
    for feed in FEEDS:
        run_ts  = _now_ts()
        started = time.monotonic()
        outcome, n, lag = "ERR", 0, None
        err_msg = None
        try:
            outcome, n, lag = _PROC[feed](client, run_ts)
        except Exception as exc:
            err_msg = f"{exc.__class__.__name__}: {exc}"
            traceback.print_exc()
        finally:
            write_heartbeat(
                run_ts=run_ts, feed=feed, outcome=outcome, delta_count=n,
                lag_seconds=lag, cycle_ms=int((time.monotonic() - started) * 1000),
                err_msg=err_msg,
            )
        print(f"{outcome:5} {feed:12} n={n} lag={lag}")


def main() -> None:
    print(f"LIVE poller start (tick={TICK_SECONDS}s, station={STATION_ID})")
    while True:
        start = time.monotonic()
        try:
            run_cycle()
        except Exception:
            traceback.print_exc()          # nie ubijaj petli
        time.sleep(max(0, TICK_SECONDS - (time.monotonic() - start)))


if __name__ == "__main__":
    main()