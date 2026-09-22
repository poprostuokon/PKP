"""
live_heartbeat.py
-----------------
Heartbeat co tick: dopisz do lokalnego spoola (.jsonl), potem best-effort
wgraj caly spool do maintenance.poller_heartbeat w JEDNEJ transakcji,
po COMMIT wyczysc spool. Idempotencja: PK (run_ts, feed) - duplikaty (ORA-00001) pomijane per wiersz.
"""

import json
from datetime import datetime, timezone
from pathlib import Path

from .paths import state_live_dir

SPOOL_MAX_LINES = 10_000


def _spool_path() -> Path:
    return state_live_dir() / "heartbeat_spool.jsonl"


def _last_path() -> Path:
    return state_live_dir() / "heartbeat_last.json"


def write_heartbeat(run_ts, feed, outcome, delta_count, lag_seconds,
                    cycle_ms, err_msg=None) -> None:
    entry = {
        "run_ts": run_ts, "feed": feed, "outcome": outcome,
        "delta_count": delta_count, "lag_seconds": lag_seconds,
        "cycle_ms": cycle_ms, "err_msg": err_msg,
        "created_at": datetime.now(timezone.utc).isoformat(),
    }
    d = state_live_dir()
    d.mkdir(parents=True, exist_ok=True)

    # 1) zawsze: biezacy stan (nadpisywany) + dopis do spoola PRZED wysylka
    (d / "heartbeat_last.json").write_text(json.dumps(entry, ensure_ascii=False),
                                           encoding="utf-8")
    with open(_spool_path(), "a", encoding="utf-8") as f:
        f.write(json.dumps(entry, ensure_ascii=False) + "\n")

    # 2) best-effort: wypchnij caly spool do DB
    try:
        _flush_spool()
    except Exception:
        pass                                  # spool zostaje, retry nastepnym tickiem


def _read_spool() -> list[dict]:
    p = _spool_path()
    if not p.exists():
        return []
    lines = [ln for ln in p.read_text(encoding="utf-8").splitlines() if ln.strip()]
    if len(lines) > SPOOL_MAX_LINES:          # bezpiecznik: GUBI najstarsze heartbeaty (DB dlugo padnieta)
        lines = lines[-SPOOL_MAX_LINES:]
    return [json.loads(ln) for ln in lines]


def _flush_spool() -> None:
    rows = _read_spool()
    if not rows:
        return

    from db import get_connection

    sql = """
        INSERT INTO maintenance.poller_heartbeat
            (run_ts, feed, outcome, delta_count, generated_at,
             lag_seconds, cycle_ms, err_msg, created_at)
        VALUES
            (TO_TIMESTAMP(:run_ts,'YYYYMMDDHH24MISS'), :feed, :outcome, :delta_count,
             NULL, :lag_seconds, :cycle_ms, :err_msg,
             TO_TIMESTAMP_TZ(:created_at,'YYYY-MM-DD"T"HH24:MI:SS.FF6TZH:TZM'))
    """
    with get_connection() as conn:
        cur = conn.cursor()
        for r in rows:
            try:
                cur.execute(sql, run_ts=r["run_ts"], feed=r["feed"],
                            outcome=r["outcome"], delta_count=r["delta_count"],
                            lag_seconds=r["lag_seconds"], cycle_ms=r["cycle_ms"],
                            err_msg=r["err_msg"], created_at=r["created_at"])
            except Exception as exc:
                if "ORA-00001" not in str(exc):      # duplikat (PK) = idempotencja, ignoruj
                    raise
        conn.commit()
    _spool_path().unlink(missing_ok=True)            # dopiero po COMMIT