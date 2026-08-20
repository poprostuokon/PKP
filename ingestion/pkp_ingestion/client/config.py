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
DEFAULT_TIMEOUT = 10

# --- Retry / backoff ---
# Ponawiamy tylko bledy przejsciowe: 429 (rate limit) + 5xx oraz bledy sieciowe.
# Bledy 4xx (poza 429) NIE sa ponawiane - nie naprawia sie samo.
RETRY_MAX_ATTEMPTS = 4              # laczna liczba prob (1 pierwsza + 3 ponowienia)
RETRY_BACKOFF_BASE = 1.0           # sekundy; opoznienie = base * 2**(proba-1) -> 1,2,4
RETRYABLE_STATUS = {429, 500, 502, 503, 504}

# --- Endpointy administracyjne klucza API (limity / zuzycie) ---
APIKEY_ENDPOINTS = {
    "usage": "/api/v1/apikey/usage",   # biezace zuzycie z limitu
    "info":  "/api/v1/apikey/info",    # info o kluczu (tier, limity)
}

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
        "params": {"carriersInclude": "BRAK", "dictionaries": "true"},
    },
    "train_statuses": {
        "endpoint": "/api/v1/fields/operations",
        "params": None,
    },
}

# --- Dane dzienne (DAILY DATA) ---
# Stacja bazowa projektu (Wroclaw Glowny). Docelowo mozna rozszerzyc o sasiednie ID.
BASE_STATIONS = "60103"

# KOMPLET parametrow kazdego endpointu trzymany jest tutaj - lacznie z datami.
# Daty jako token DATE_TOKEN ("{day}") - realna wartosc podstawiana w runtime
# przez params.build_params() na podstawie pola "default_day":
#   "today"     -> dzien biezacy
#   "yesterday" -> dzien poprzedni (D-1)
#   None        -> endpoint nie uzywa daty
# Boole jako stringi "true"/"false" - requests inaczej wysle "True"/"False".
DATE_TOKEN = "{day}"

DATA_ENDPOINTS = {
    "schedules": {
        "endpoint":  "/api/v1/schedules",
        "params": {
            "stations":     BASE_STATIONS,
            "fullRoute":    "true",    # pelne trasy pociagow przez stacje
            "dictionaries": "false",   # slowniki pobieramy osobno (DEF)
            "dateFrom":     DATE_TOKEN,
            "dateTo":       DATE_TOKEN,
        },
        "default_day": "D",
        "paginated": False,            # schedules zwraca wszystko w jednej odpowiedzi
    },
    "operations": {
        "endpoint":  "/api/v1/operations",
        "params": {
            "stations":    BASE_STATIONS,
            "fullRoutes":  "true",     # pelne trasy pociagow przez stacje
            "withPlanned": "true",     # planowe czasy + policzone opoznienia
            "pageSize":    5000,       # max -> mniej stron/calli
            # page wstrzykiwany w petli (runtime) - to mechanika paginacji, nie parametr uzytkownika
        },
        "default_day": "D-1",          # Dane z wczoraj (D-1) - snapshot "na teraz" w nocy po.
        "paginated": True,             # operations paginowany: petla po stronach
    },
    "disruptions": {
        "endpoint":  "/api/v1/disruptions",
        "params": {
            #"stations":     BASE_STATIONS,
            "dictionaries": "false",   # slownik disruption_types ciagniemy osobno (DEF)
            "dateFrom":     DATE_TOKEN,
            "dateTo":       DATE_TOKEN,
        },
        "default_day": "D-1",    # odpalane w nocy po -> pobieramy D-1
        "paginated": False,
    },
}

# Wielkosc strony operations (spojna z params powyzej; uzywana w petli).
OPERATIONS_PAGE_SIZE = 5000