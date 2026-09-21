"""
settings.py
-----------
Centralne wczytanie konfiguracji ze srodowiska (.env).
Jedno miejsce, z ktorego reszta paczki bierze klucz API, srodowisko i katalog Data.
"""

import os
from pathlib import Path

from dotenv import load_dotenv

#load_dotenv(find_dotenv())  # wczytuje .env
app_env = os.getenv("APP_ENV", "prod")          # 'dev' albo 'prod'
env_file = Path(__file__).resolve().parent.parent / f".env.{app_env}"
load_dotenv(env_file, override=False)

# --- Sekrety / srodowisko ---
API_KEY                 = os.environ["PKP_API_KEY"]          # wymagany; brak -> KeyError na starcie

# Srodowisko (DEV/PROD) - decyduje o galezi w strukturze Data.
# Docelowo podstawiane przez Airflow; domyslnie DEV.
ENV                     = os.getenv("PKP_ENV")

# Katalog bazowy struktury Data (domyslnie 'Data' w biezacym katalogu).
DATA_ROOT               = Path(os.getenv("PKP_DATA_ROOT"))

# --- OCI Object Storage (upload bronze) ---
OCI_PROFILE             = os.getenv("PKP_OCI_PROFILE", "DEFAULT")   # profil z ~/.oci/config
OCI_CONFIG_FILE         = os.getenv("PKP_OCI_CONFIG_FILE")  # None lokalnie -> domyslny ~/.oci/config; /oci/config.docker w kontenerze
OCI_BUCKET              = os.getenv("PKP_OCI_BUCKET")  # bucketu daily
OCI_BUCKET_LIVE         = os.getenv("PKP_OCI_BUCKET_LIVE")   # bucketu live

# --- OCI: timeout + retry uploadu ---
OCI_CONNECT_TIMEOUT     = int(os.getenv("PKP_OCI_CONNECT_TIMEOUT", "10"))
OCI_READ_TIMEOUT        = int(os.getenv("PKP_OCI_READ_TIMEOUT", "120"))
OCI_UPLOAD_TIMEOUT      = int(os.getenv("PKP_OCI_UPLOAD_TIMEOUT", "300"))
OCI_RETRY_MAX_ATTEMPTS  = int(os.getenv("PKP_OCI_RETRY_MAX_ATTEMPTS", "5"))
OCI_RETRY_TOTAL_SECONDS = int(os.getenv("PKP_OCI_RETRY_TOTAL_SECONDS", "600"))
