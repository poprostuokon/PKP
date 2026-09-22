"""
db.py
-----
Polaczenie do Oracle Autonomous DB (silver/gold) przez python-oracledb (thin mode).

Wallet podawany INLINE jako parametry (config_dir + wallet_location) - nie ruszamy
globalnego TNS_ADMIN, wiec zero kolizji z Crystal Reports.
Wszystkie wartosci sterowane z .env.
"""

import os
from pathlib import Path

import oracledb
from dotenv import load_dotenv

# APP_ENV = KTÓRY plik .env załadować (.env.dev / .env.prod). Tylko wybór pliku.
# PKP_ENV = nazwa instancji / gałąź w strukturze Data (DEV/PROD). Ustawiana W tym pliku .env.
app_env = os.getenv("APP_ENV", "prod")
env_file = Path(__file__).resolve().parent / f".env.{app_env}"
load_dotenv(env_file, override=False)

WALLET_DIR = os.environ["PKP_WALLET_DIR"]               # folder z rozpakowanym walletem (tnsnames/sqlnet/cwallet.sso)
WALLET_PASSWORD = os.environ["PKP_WALLET_PASSWORD"]     # None gdy SSO (cwallet.sso bez hasla)
DB_USER = os.environ["PKP_DB_USER"]
DB_PASSWORD = os.environ["PKP_DB_PASSWORD"]
DB_DSN = os.environ["PKP_DB_DSN"]                       # np. pkpdev_high (z tnsnames.ora)



def get_connection() -> oracledb.Connection:
    """
    Polaczenie do bazy; wallet podany inline (thin mode).
    Jesli wallet ma tylko cwallet.sso (SSO) - haslo walletu nie jest potrzebne.
    wallet_password przekazywany zawsze; dla SSO (cwallet.sso) jest None i ignorowany.
    """
    return oracledb.connect(
        user=DB_USER,
        password=DB_PASSWORD,
        dsn=DB_DSN,
        config_dir=WALLET_DIR,       # gdzie jest tnsnames.ora / sqlnet.ora
        wallet_location=WALLET_DIR,  # gdzie jest cwallet.sso (mTLS do ADB)
        wallet_password=WALLET_PASSWORD
    )


if __name__ == "__main__":
    # Szybki test polaczenia
    with get_connection() as conn, conn.cursor() as cur:
        cur.execute("SELECT USER, SYSTIMESTAMP FROM dual")
        print("Polaczono jako:", cur.fetchone())