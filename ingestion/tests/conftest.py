"""
conftest.py
-----------
Stub srodowiska dla testow LIVE. Importowany PRZED testami, wiec ustawia
wymagane zmienne env (PKP_*), zanim live_poller zrobi `import db` na module-level
(bez nich settings/db rzucaja na etapie zbierania testow).

Uzywa setdefault -> nie nadpisuje prawdziwych env, jesli sa juz ustawione.
Wartosci sa atrapami (test/DEV) - testy nie lacza sie z API ani z baza.
"""

import os
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))  # -> ingestion/

for k, v in {
    "APP_ENV": "dev", "PKP_API_KEY": "test", "PKP_ENV": "DEV",
    "PKP_DATA_ROOT": "/tmp/pkp_test", "PKP_OCI_BUCKET": "b", "PKP_OCI_BUCKET_LIVE": "bl",
    "PKP_WALLET_DIR": "/tmp", "PKP_WALLET_PASSWORD": "x",
    "PKP_DB_USER": "x", "PKP_DB_PASSWORD": "x", "PKP_DB_DSN": "x",
    "PKP_STATION_ID": "60103",
}.items():
    os.environ.setdefault(k, v)