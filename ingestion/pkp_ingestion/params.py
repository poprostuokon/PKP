"""
params.py
---------
Resolver parametrow endpointow dziennych.
Config deklaruje date jako token DATE_TOKEN ("{day}") + pola:
  - default_day: kotwica zakresu (= dateTo):  "D" | "D-1" | None
  - range_days:  dlugosc okna wstecz od kotwicy (brak => 1 = pojedynczy dzien)
Runtime rozwija to na konkretne dateFrom/dateTo.
"""

from datetime import date, timedelta

from .client.config import DATA_ENDPOINTS, DATE_TOKEN


def resolve_day(default_day: str | None, override: str | None) -> str | None:
    """Kotwica (YYYY-MM-DD). override ma pierwszenstwo; inaczej wg default_day."""
    if override:
        return override
    if default_day == "D":
        return date.today().isoformat()
    if default_day == "D-1":
        return (date.today() - timedelta(days=1)).isoformat()
    return None


def resolve_range(name: str,
                  day: str | None = None,
                  date_from: str | None = None,
                  date_to: str | None = None) -> tuple[str | None, str | None]:
    """
    Zwraca (dateFrom, dateTo) w formacie YYYY-MM-DD.
    Priorytet:
      1) jawne date_from/date_to (backfill ad-hoc) - wygrywaja,
      2) config: kotwica = resolve_day(default_day, day) = dateTo,
         dateFrom = kotwica - (range_days - 1).
    Endpoint bez daty (default_day=None, brak override) -> (None, None).
    """
    cfg = DATA_ENDPOINTS[name]

    # 1) pelny override zakresu
    if date_from or date_to:
        # gdy podano tylko jeden koniec, drugim jest kotwica z configu
        anchor = resolve_day(cfg.get("default_day"), day)
        return (date_from or anchor), (date_to or anchor)

    # 2) zakres liczony z configu
    anchor = resolve_day(cfg.get("default_day"), day)
    if anchor is None:
        return None, None

    range_days = int(cfg.get("range_days", 1))
    if range_days < 1:
        raise ValueError(f"Endpoint '{name}': range_days musi byc >= 1 (jest {range_days}).")

    d_to = date.fromisoformat(anchor)
    d_from = d_to - timedelta(days=range_days - 1)
    return d_from.isoformat(), d_to.isoformat()


def build_params(name: str,
                 day: str | None = None,
                 date_from: str | None = None,
                 date_to: str | None = None) -> dict:
    """Buduje parametry endpointu; dateFrom/dateTo z resolve_range. Config nie jest mutowany."""
    cfg = DATA_ENDPOINTS[name]
    r_from, r_to = resolve_range(name, day, date_from, date_to)

    params = {}
    for key, value in cfg["params"].items():
        if value == DATE_TOKEN:
            if key == "dateFrom":
                target = r_from
            elif key == "dateTo":
                target = r_to
            else:
                # token daty pod niestandardowym kluczem -> uzyj konca zakresu (dateTo)
                target = r_to
            if target is None:
                raise ValueError(f"Endpoint '{name}' ma token daty, ale brak default_day/day/zakresu.")
            params[key] = target
        else:
            params[key] = value
    return params


def business_date(name: str, day: str | None = None,
                  date_from: str | None = None) -> str | None:
    """
    Data do NAZWY pliku (YYYY-MM-DD). Dla zakresu bierzemy POCZATEK okna (dateFrom),
    zeby nazwa jednoznacznie wskazywala pierwszy dzien danych w pliku.
    """
    r_from, _ = resolve_range(name, day, date_from)
    return r_from