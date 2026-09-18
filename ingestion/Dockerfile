FROM python:3.12-slim

# Klient nie potrzebuje Oracle Instant Client — python-oracledb thin mode
# gada z ADB po TLS bez natywnych bibliotek. Wallet wystarczy.

WORKDIR /app/ingestion

# 1) najpierw zaleznosci (lepszy cache warstw)
COPY pyproject.toml ./
RUN pip install --no-cache-dir .

# 2) potem kod (db.py + pakiet)
COPY db.py ./
COPY pkp_ingestion ./pkp_ingestion

# poller jako modul: CWD=/app/ingestion -> `import db` znajduje ./db.py
CMD ["python", "-m", "pkp_ingestion.live_poller"]