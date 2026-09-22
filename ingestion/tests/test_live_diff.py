"""
test_live.py
------------
Testy jednostkowe warstwy LIVE (pseudo-streaming), bez sieci i bez bazy:

  * live_diff  - kanonikalizacja (_canon), diff operations (nowy/zmiana/finalny
                 zamrozony) i disruptions (changed + tombstony fresh/aged).
  * live_poller - _lag, bramkowanie STATE po uploadzie (_finalize), sklejanie
                 stron i STALE po generatedAt (_fetch_operations_all/_prep_operations).

Zaleznosci zewnetrzne (API, walidacja) sa monkeypatchowane; env DB stubowany w conftest.py.
Uruchomienie z katalogu 'ingestion':  python -m pytest tests/ -v
"""

import json
import pkp_ingestion.live_poller as lp
from pkp_ingestion.live_poller import _finalize, _lag
from pkp_ingestion.live_diff import _canon, diff_operations
from pkp_ingestion.live_diff import diff_disruptions
from pkp_ingestion.live_diff import _op_tracked

SID = 60103

def _train(status="R", planned="08:00", actual=None, confirmed=False):
    st = {"stationId": SID, "plannedArrival": planned, "actualArrival": actual}
    if confirmed:
        st["isConfirmed"] = True
    return {"trainOrderId": 1, "operatingDate": "2026-09-17",
            "trainStatus": status, "stations": [st]}

# --- _canon ---
def test_canon_kolejnosc_kluczy_bez_znaczenia():
    assert _canon({"a": 1, "b": 2}) == _canon({"b": 2, "a": 1})

def test_canon_wyrzuca_none_i_false_zostawia_zero():
    assert _canon({"x": 0, "y": None, "z": False}) == '{"x":0}'

# --- diff_operations ---
def test_nowy_klucz_leci():
    delta = diff_operations([], [_train()], SID)
    assert len(delta) == 1

def test_bez_zmian_pomijany():
    t = _train()
    assert diff_operations([t], [t], SID) == []

def test_finalny_zamrozony_mimo_zmiany():
    prev = _train(confirmed=True, actual="08:05")
    curr = _train(confirmed=True, actual="08:09")  # inny czas, ale prev finalny
    assert diff_operations([prev], [curr], SID) == []

def _disr(msg="awaria", route_date="2026-09-17"):
    return {"disruptionTypeCode": "TECH", "message": msg,
            "affectedRoutes": [{"scheduleId": 1, "orderId": 10, "trainOrderId": 5,
                                "operatingDate": route_date, "stationId": SID,
                                "sequenceNumber": 1}]}

def test_disr_nowy_leci_jako_changed():
    changed, ended = diff_disruptions([], [_disr()])
    assert len(changed) == 1 and ended == []

def test_disr_bez_zmian_pomijany():
    d = _disr()
    changed, ended = diff_disruptions([d], [d])
    assert changed == [] and ended == []

def test_disr_zmiana_message_leci():
    changed, _ = diff_disruptions([_disr("awaria")], [_disr("usunieto awarie")])
    assert len(changed) == 1

def test_disr_zniknal_swiezy_to_ended():
    # zniknął z API, a jego data == dzis (fresh) → tombstone
    changed, ended = diff_disruptions([_disr(route_date="2026-09-17")], [],
                                      ended_min_date="2026-09-17")
    assert changed == [] and len(ended) == 1

def test_disr_zniknal_stary_nie_ended():
    # zniknął, ale data < min → aged out, NIE deaktywujemy
    changed, ended = diff_disruptions([_disr(route_date="2026-09-10")], [],
                                      ended_min_date="2026-09-17")
    assert ended == []

# 1) zmiana niefinalnego rekordu -> leci (brakowało tej ścieżki)
def test_zmiana_niefinalny_leci():
    prev = _train(actual="08:05")
    curr = _train(actual="08:09")   # inny actual, niefinalny
    assert len(diff_operations([prev], [curr], SID)) == 1

# 2) pole nieobecne == false -> ten sam hash (ochrona przed fałszywym diffem)
def test_absent_false_ten_sam_hash():
    a = {"trainStatus": "R", "stations": [{"stationId": SID, "plannedArrival": "08:00"}]}
    b = {"trainStatus": "R", "stations": [{"stationId": SID, "plannedArrival": "08:00",
                                           "isConfirmed": False, "isCancelled": False}]}
    assert _canon(_op_tracked(a, SID)) == _canon(_op_tracked(b, SID))

# 3) disruptions: zmiana typu (nie tylko message) -> changed
def test_disr_zmiana_typu_leci():
    d1 = {"disruptionTypeCode": "TECH", "message": "x",
          "affectedRoutes": [{"scheduleId": 1, "orderId": 10, "trainOrderId": 5,
                              "operatingDate": "2026-09-17", "stationId": SID,
                              "sequenceNumber": 1}]}
    d2 = {**d1, "disruptionTypeCode": "STRAJK"}
    changed, _ = diff_disruptions([d1], [d2])
    assert len(changed) == 1

# --- _lag ---
def test_lag_none_gdy_brak():
    assert _lag(None) is None

def test_lag_none_gdy_zly_format():
    assert _lag("nie-data") is None

def test_lag_dodatni_dla_przeszlosci():
    assert _lag("2000-01-01T00:00:00Z") > 0


# --- _finalize: bramkowanie STATE po uploadzie (pkt 3) ---
def test_finalize_ok_upload_ok_zapisuje_state(tmp_path):
    sp = tmp_path / "state_operations.json"
    prep = {"outcome": "OK", "delta_file": "f.json",
            "curr": {"generatedAt": "x", "trains": []}, "state_path": sp}
    assert _finalize(prep, {"f.json"}) == "OK"
    assert sp.exists()                       # delta poszła -> STATE zapisany

def test_finalize_ok_upload_padl_nie_zapisuje_state(tmp_path):
    sp = tmp_path / "state_operations.json"
    prep = {"outcome": "OK", "delta_file": "f.json",
            "curr": {"generatedAt": "x"}, "state_path": sp}
    assert _finalize(prep, set()) == "ERR"   # delta NIE poszła -> ERR
    assert not sp.exists()                   # STATE nietknięty -> retry next tick

def test_finalize_empty_zawsze_zapisuje(tmp_path):
    sp = tmp_path / "state_operations.json"
    prep = {"outcome": "EMPTY", "curr": {"generatedAt": "x"}, "state_path": sp}
    assert _finalize(prep, set()) == "EMPTY"
    assert sp.exists()

def test_finalize_stale_nie_zapisuje():
    assert _finalize({"outcome": "STALE"}, set()) == "STALE"


# --- _fetch_operations_all: sklejanie stron + zła strona = None (pkt 2) ---
class _FakeClient:
    def __init__(self, pages):
        self.pages = pages
    def get(self, endpoint, params=None):
        return self.pages[params["page"] - 1]

def test_fetch_operations_skleja_strony(monkeypatch):
    monkeypatch.setattr(lp, "validate_or_quarantine", lambda *a, **k: True)
    p1 = json.dumps({"generatedAt": "G1", "trains": [{"id": 1}],
                     "pagination": {"hasNextPage": True}})
    p2 = json.dumps({"generatedAt": "G2", "trains": [{"id": 2}],
                     "pagination": {"hasNextPage": False}})
    curr = lp._fetch_operations_all(_FakeClient([p1, p2]), "20260101000000")
    assert curr["generatedAt"] == "G1"       # gen z pierwszej strony
    assert len(curr["trains"]) == 2          # strony sklejone

def test_fetch_operations_zla_strona_zwraca_none(monkeypatch):
    monkeypatch.setattr(lp, "validate_or_quarantine", lambda *a, **k: False)
    p1 = json.dumps({"generatedAt": "G1", "trains": [],
                     "pagination": {"hasNextPage": True}})
    assert lp._fetch_operations_all(_FakeClient([p1]), "20260101000000") is None


# --- _prep_operations: STALE po generatedAt (pkt 2) ---
def test_prep_operations_stale(monkeypatch):
    monkeypatch.setattr(lp, "_fetch_operations_all",
                        lambda c, r: {"generatedAt": "2026-01-01T00:00:00Z", "trains": []})
    monkeypatch.setattr(lp, "load_state",
                        lambda p: {"generatedAt": "2026-01-01T00:00:00Z", "trains": []})
    assert lp._prep_operations(None, "20260101000000")["outcome"] == "STALE"