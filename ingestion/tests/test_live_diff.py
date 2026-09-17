from pkp_ingestion.live_diff import _canon, diff_operations

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