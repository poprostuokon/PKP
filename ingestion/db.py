import os
from pathlib import Path
import oracledb
from dotenv import load_dotenv

load_dotenv()

def get_connection():
    # TNS_ADMIN ustawiany TYLKO w tym procesie - zero konfliktu z globalnym (CR)
    os.environ["TNS_ADMIN"] = os.environ["PKP_WALLET_DIR"]
    return oracledb.connect(
        user=os.environ["PKP_DB_USER"],
        password=os.environ["PKP_DB_PASSWORD"],
        dsn=os.environ["PKP_DB_DSN"],
    )