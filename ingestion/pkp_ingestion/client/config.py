"""
config.py
---------
Statyczna konfiguracja polaczenia z PKP PLK API:
- base_url,
- mapa endpointow slownikow (DICT),
- domyslny timeout.

Docelowo dojda tu endpointy schedules/operations/disruptions.
"""

BASE_URL = "https://pdp-api.plk-sa.pl"

# Domyslny timeout requestu (sekundy).
DEFAULT_TIMEOUT = 30

# Slowniki DEF majace bezposredni endpoint (GET).
# Klucz  = krotka nazwa uzywana w nazwie pliku (dict_<nazwa>_<ts>.json),
# wartosc = {"endpoint": sciezka, "params": staly slownik parametrow query lub None}.
# Ujednolicony ksztalt: kazdy endpoint deklaratywnie niesie swoje parametry.
DICTIONARY_ENDPOINTS = {
    "carriers":              {"endpoint": "/api/v1/dictionaries/carriers",              "params": None},
    "cities":                {"endpoint": "/api/v1/dictionaries/cities",                "params": None},
    # stations: default zwraca 500; pageSize=10000 (max) -> wszystkie stacje.
    "stations":              {"endpoint": "/api/v1/dictionaries/stations",              "params": {"pageSize": 10000}},
    "commercial_categories": {"endpoint": "/api/v1/dictionaries/commercial-categories", "params": None},
    "stop_types":            {"endpoint": "/api/v1/dictionaries/stop-types",            "params": None},
}

# Slowniki bez wlasnego endpointu - wyciagane "przy okazji" innego zapytania.
# disruption_types: endpoint disruptions z filtrem dajacym PUSTA liste utrudnien
#                   (carriersInclude=BRAK -> nieistniejacy przewoznik) + slownikiem.
# train_statuses:   slownik opisu pol endpointu operations (/api/v1/fields/operations).
SPECIAL_DICTIONARIES = {
    "disruption_types": {
        "endpoint": "/api/v1/disruptions",
        "params": {"stations": [99999999999], "carriersInclude": "BRAK", "dictionaries": "true", },
    },
    "train_statuses": {
        "endpoint": "/api/v1/fields/operations",
        "params": None,
    },
}