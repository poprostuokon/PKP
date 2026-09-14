"""
live_poller.py
--------------
Serwis LIVE. Cykl: prep obu feedow (fetch->validate->stale->RAW->diff->delta do TODO/LIVE/DATA)
-> jeden upload -> STATE zapisywany DOPIERO po udanym sinku (pkt 1) + heartbeat.
Uruchomienie: python -m pkp_ingestion.live_poller
"""

import json
import time
import traceback
from datetime import datetime, timezone, date

from .client.api_client import PkpApiClient
from .client.config import DATA_ENDPOINTS_LIVE
from .params import build_params
from .validation import validate_or_quarantine
from .storage.local_writer import write_raw
from .paths import (
    todo_live_raw_dir, todo_live_data_dir, state_live_dir,
    raw_filename, state_filename, data_filename, err_live_dir,
)
from .live_diff import load_state, save_state, diff_operations, diff_disruptions
from .live_heartbeat import write_heartbeat
from .upload_live import run_upload_live

STATION_ID   = 60103
TICK_SECONDS = 180
FEEDS        = ("operations", "disruptions")


def _lag(gen):
    if not gen:
        return None
    try:
        g = datetime.fromisoformat(gen.replace("Z", "+00:00"))
        return (datetime.now(timezone.utc) - g).total_seconds()
    except ValueError:
        return None


def _prep_operations(client, run_ts) -> dict:
    cfg = DATA_ENDPOINTS_LIVE["operations"]
    raw = client.get(cfg["endpoint"], params=build_params("operations"))
    if not validate_or_quarantine("operations_live", raw, f"operations_{date.today()}",
                                  run_ts, err_dir_fn=err_live_dir):
        return {"outcome": "ERR", "n": 0, "lag": None}

    curr = json.loads(raw)
    gen  = curr.get("generatedAt")
    state_path = state_live_dir() / state_filename("operations")
    prev = load_state(state_path)

    if prev.get("generatedAt") and gen and gen <= prev["generatedAt"]:
        return {"outcome": "STALE", "n": 0, "lag": _lag(gen)}

    write_raw(todo_live_raw_dir(), raw_filename("operations"), raw)  # scratch/debug
    delta = diff_operations(prev.get("trains", []), curr.get("trains", []), STATION_ID)

    if not delta:
        return {"outcome": "EMPTY", "n": 0, "lag": _lag(gen),
                "curr": curr, "state_path": state_path}

    fname = data_filename("operations", date.today().strftime("%Y%m%d"), run_ts)
    write_raw(todo_live_data_dir(), fname,
              json.dumps({"generatedAt": gen, "trains": delta}, ensure_ascii=False))
    return {"outcome": "OK", "n": len(delta), "lag": _lag(gen),
            "curr": curr, "state_path": state_path, "delta_file": fname}


def _prep_disruptions(client, run_ts) -> dict:
    cfg = DATA_ENDPOINTS_LIVE["disruptions"]
    raw = client.get(cfg["endpoint"], params=build_params("disruptions"))
    if not validate_or_quarantine("disruptions_live", raw, f"disruptions_{date.today()}",
                                  run_ts, err_dir_fn=err_live_dir):
        return {"outcome": "ERR", "n": 0, "lag": None}

    curr = json.loads(raw)
    gen  = curr.get("generatedAt")
    state_path = state_live_dir() / state_filename("disruptions")
    prev = load_state(state_path)

    if prev.get("generatedAt") and gen and gen <= prev["generatedAt"]:
        return {"outcome": "STALE", "n": 0, "lag": _lag(gen)}

    write_raw(todo_live_raw_dir(), raw_filename("disruptions"), raw)
    today = date.today().strftime("%Y-%m-%d")
    changed, ended = diff_disruptions(prev.get("disruptions", []),
                                      curr.get("disruptions", []), ended_min_date=today)

    if not changed and not ended:
        return {"outcome": "EMPTY", "n": 0, "lag": _lag(gen),
                "curr": curr, "state_path": state_path}

    fname = data_filename("disruptions", date.today().strftime("%Y%m%d"), run_ts)
    write_raw(todo_live_data_dir(), fname,
              json.dumps({"generatedAt": gen, "changed": changed, "ended": ended},
                         ensure_ascii=False))
    return {"outcome": "OK", "n": len(changed) + len(ended), "lag": _lag(gen),
            "curr": curr, "state_path": state_path, "delta_file": fname}


_PREP = {"operations": _prep_operations, "disruptions": _prep_disruptions}


def _finalize(prep: dict, ok_files: set[str]) -> str:
    """Zapis STATE zgodnie z pkt 1: EMPTY -> zawsze; OK -> tylko po udanym uploadzie."""
    outcome = prep["outcome"]
    if outcome == "EMPTY":
        save_state(prep["state_path"], prep["curr"])
        return "EMPTY"
    if outcome in ("STALE", "ERR"):
        return outcome
    # OK: STATE tylko jesli delta faktycznie poszla do bucketu
    if prep.get("delta_file") in ok_files:
        save_state(prep["state_path"], prep["curr"])
        return "OK"
    return "ERR"          # upload delty nie powiodl sie -> STATE nietkniety, retry nastepny tick


def run_cycle() -> None:
    client  = PkpApiClient()
    run_ts  = datetime.now().strftime("%Y%m%d%H%M%S")
    preps: dict[str, dict] = {}

    # 1) prep obu feedow (izolacja bledu per feed) - BEZ zapisu STATE
    for feed in FEEDS:
        started = time.monotonic()
        try:
            prep = _PREP[feed](client, run_ts)
        except Exception as exc:
            prep = {"outcome": "ERR", "n": 0, "lag": None,
                    "err": f"{exc.__class__.__name__}: {exc}"}
            traceback.print_exc()
        prep["started"] = started
        preps[feed] = prep

    # 2) jeden sink
    try:
        ok_files = run_upload_live()
    except Exception:
        ok_files = set()
        traceback.print_exc()

    # 3) STATE + heartbeat DOPIERO po sinku
    for feed, prep in preps.items():
        final = _finalize(prep, ok_files)
        write_heartbeat(
            run_ts=run_ts, feed=feed, outcome=final, delta_count=prep["n"],
            lag_seconds=prep["lag"],
            cycle_ms=int((time.monotonic() - prep["started"]) * 1000),
            err_msg=prep.get("err"),
        )
        print(f"{final:5} {feed:12} n={prep['n']} lag={prep['lag']}")


def main() -> None:
    print(f"LIVE poller start (tick={TICK_SECONDS}s, station={STATION_ID})")
    while True:
        start = time.monotonic()
        try:
            run_cycle()
        except Exception:
            traceback.print_exc()
        time.sleep(max(0, TICK_SECONDS - (time.monotonic() - start)))


if __name__ == "__main__":
    main()