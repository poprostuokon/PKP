"""
live_diff.py
------------
Diff rekordowy LIVE: swiezy snapshot vs baseline (STATE). Zwraca tylko
nowe/zmienione rekordy. Hash = SHA-256 skanonikalizowanych pol sledzonych.
"""

import hashlib
import json
import os
from pathlib import Path


# --- kanonikalizacja + hash ---
def _canon(obj: dict) -> str:
    # truthy-only -> jedna postac: usuwamy TYLKO None/False (nie 0!)
    clean = {k: v for k, v in obj.items() if v is not None and v is not False}
    return json.dumps(clean, sort_keys=True, separators=(",", ":"), ensure_ascii=False)


def _sha256(text: str) -> str:
    return hashlib.sha256(text.encode("utf-8")).hexdigest()


# --- STATE (baseline) atomowo ---
def load_state(path: Path) -> dict:
    if not path.exists():                       # cold start
        return {"generatedAt": None, "trains": [], "disruptions": []}
    return json.loads(path.read_text(encoding="utf-8"))


def save_state(path: Path, snapshot: dict) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    tmp = path.with_suffix(path.suffix + ".tmp")
    tmp.write_text(json.dumps(snapshot, ensure_ascii=False), encoding="utf-8")
    os.replace(tmp, path)                        # atomowo: caly stary albo caly nowy


# --- OPERATIONS ---
def _op_station(train: dict, station_id: int) -> dict:
    for s in train.get("stations", []):
        if s.get("stationId") == station_id:
            return s
    return train.get("stations", [{}])[0] if train.get("stations") else {}


def _op_key(train: dict):
    return (train.get("trainOrderId"), train.get("operatingDate"))


def _op_tracked(train: dict, station_id: int) -> dict:
    st = _op_station(train, station_id)
    return {
        "trainStatus":          train.get("trainStatus"),
        "plannedArrival":       st.get("plannedArrival"),
        "plannedDeparture":     st.get("plannedDeparture"),
        "actualArrival":        st.get("actualArrival"),
        "actualDeparture":      st.get("actualDeparture"),
        "actualSequenceNumber": st.get("actualSequenceNumber"),
        "isConfirmed":          st.get("isConfirmed", False),
        "isCancelled":          st.get("isCancelled", False),
    }


def _op_final(train: dict, station_id: int) -> bool:
    st = _op_station(train, station_id)
    return bool(st.get("isConfirmed", False) or st.get("isCancelled", False))


def diff_operations(prev_trains, curr_trains, station_id: int) -> list[dict]:
    """Nowy klucz LUB (poprzedni NIE finalny i hash sie zmienil). Finalny -> zamrozony."""
    prev = {_op_key(t): t for t in prev_trains}
    out = []
    for t in curr_trains:
        p = prev.get(_op_key(t))
        h = _sha256(_canon(_op_tracked(t, station_id)))
        if p is None:
            pass                                              # nowy
        elif _op_final(p, station_id):
            continue                                          # zamrozony
        elif _sha256(_canon(_op_tracked(p, station_id))) == h:
            continue                                          # bez zmian
        rec = dict(t)
        rec["changeHash"] = h
        out.append(rec)
    return out


# --- DISRUPTIONS ---
def _flatten(disruptions) -> dict:
    rows = {}
    for d in disruptions or []:
        tc, msg = d.get("disruptionTypeCode"), d.get("message")
        for r in d.get("affectedRoutes", []):
            bk = (r.get("scheduleId"), r.get("orderId"), r.get("trainOrderId"),
                  r.get("operatingDate"), r.get("stationId"), r.get("sequenceNumber"))
            rows[bk] = {**{k: r.get(k) for k in
                          ("scheduleId", "orderId", "trainOrderId",
                           "operatingDate", "stationId", "sequenceNumber")},
                        "disruptionTypeCode": tc, "message": msg}
    return rows


def diff_disruptions(prev_disruptions, curr_disruptions, ended_min_date=None):
    """Zwraca (changed, ended). ended = trasy ktore zniknely; ended_min_date
    ogranicza tombstony do operatingDate >= daty (ochrona przed 'wypadlo ze starosci')."""
    prev, curr = _flatten(prev_disruptions), _flatten(curr_disruptions)

    def h(row):
        return _sha256(_canon({"disruptionTypeCode": row["disruptionTypeCode"],
                               "message": row["message"]}))

    changed = []
    for bk, row in curr.items():
        p = prev.get(bk)
        hh = h(row)
        if p is not None and h(p) == hh:
            continue
        rec = dict(row)
        rec["changeHash"] = hh
        changed.append(rec)

    ended = [row for bk, row in prev.items()
             if bk not in curr
             and not (ended_min_date and (row["operatingDate"] or "") < ended_min_date)]
    return changed, ended