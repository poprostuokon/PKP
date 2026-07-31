"""
params.py
---------
Resolver parametrow endpointow danych dziennych.
Bierze KOMPLETNY szablon parametrow z config.DATA_ENDPOINTS i podstawia realna
date w miejsce tokenu DATE_TOKEN ("{day}").

Dzieki temu wszystkie parametry (lacznie z data) sa deklarowane w jednym miejscu
(config), a tutaj dzieje sie tylko rozwiniecie tokenu.
"""

from datetime import date, timedelta

from .client.config import DATA_ENDPOINTS, DATE_TOKEN


def resolve_day(default_day: str | None, override: str | None) -> str | None:
    """
    Zwraca date w formacie YYYY-MM-DD.
    override ma pierwszenstwo; inaczej wg default_day (today/yesterday/None).
    """
    if override:
        return override
    if default_day == "D":
        return date.today().isoformat()
    if default_day == "D-1":
        return (date.today() - timedelta(days=1)).isoformat()
    return None


def build_params(name: str, day: str | None = None) -> dict:
    """
    Buduje slownik parametrow dla endpointu <name>, podstawiajac date za DATE_TOKEN.
    Szablon w configu nie jest mutowany (tworzymy nowy slownik).
    """
    cfg = DATA_ENDPOINTS[name]
    resolved_day = resolve_day(cfg.get("default_day"), day)

    params = {}
    for key, value in cfg["params"].items():
        if value == DATE_TOKEN:
            if resolved_day is None:
                raise ValueError(f"Endpoint '{name}' ma token daty, ale brak default_day/day.")
            params[key] = resolved_day
        else:
            params[key] = value
    return params


def business_date(name: str, day: str | None = None) -> str | None:
    """Data biznesowa (YYYY-MM-DD) uzyta dla endpointu - do nazwy pliku itp."""
    cfg = DATA_ENDPOINTS[name]
    return resolve_day(cfg.get("default_day"), day)