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
                              "operatingDate": "2026-09-17", "stationId": 60103,
                              "sequenceNumber": 1}]}
    d2 = {**d1, "disruptionTypeCode": "STRAJK"}
    changed, _ = diff_disruptions([d1], [d2])
    assert len(changed) == 1