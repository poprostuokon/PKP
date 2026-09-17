from pkp_ingestion.live_diff import _canon, diff_operations
from pkp_ingestion.live_diff import diff_disruptions

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
                                "operatingDate": route_date, "stationId": 60103,
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