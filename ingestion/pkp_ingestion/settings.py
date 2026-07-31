"""
settings.py
-----------
Centralne wczytanie konfiguracji ze srodowiska (.env).
Jedno miejsce, z ktorego reszta paczki bierze klucz API, srodowisko i katalog Data.
"""

import os
from pathlib import Path

from dotenv import load_dotenv

load_dotenv()  # wczytuje .env z biezacego katalogu roboczego

# --- Sekrety / srodowisko ---
API_KEY = os.environ["PKP_API_KEY"]          # wymagany; brak -> KeyError na starcie

# Srodowisko (DEV/PROD) - decyduje o galezi w strukturze Data.
# Docelowo podstawiane przez Airflow; domyslnie DEV.
ENV = os.getenv("PKP_ENV", "DEV")

# Katalog bazowy struktury Data (domyslnie 'Data' w biezacym katalogu).
DATA_ROOT = Path(os.getenv("PKP_DATA_ROOT", "Data"))

# --- OCI Object Storage (upload bronze) ---
OCI_PROFILE = os.getenv("PKP_OCI_PROFILE", "DEFAULT")   # profil z ~/.oci/config
OCI_BUCKET = os.getenv("PKP_OCI_BUCKET", "bronze-pkp")  # nazwa bucketu
