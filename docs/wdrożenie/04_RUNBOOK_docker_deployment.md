# Runbook — wdrożenie Docker

Dokument opisuje procedury uruchamiania i przebudowy kontenerów projektu PKP: serwisu
**poller (live)** oraz środowiska **Airflow (daily)**.

---

## 0. Architektura kontenerów

| Komponent | Funkcja | Model dostarczenia kodu | Rejestr |
|---|---|---|---|
| `pkp-poller` | Serwis LIVE działający ciągle (micro-batch, cykl co ~3 min) | Kod w obrazie (`COPY`) — zmiana kodu wymaga `docker build` | lokalny |
| `airflow` | Orkiestracja batch DAILY (scheduler, webserver, metadata Postgres) | Repozytorium montowane jako wolumen — zmiana kodu bez przebudowy | lokalny |

---

## 1. Zasada nadrzędna: obraz zawiera wyłącznie kod

Obraz nie zawiera sekretów. Wallet, konfiguracja OCI, pliki `.env` oraz katalog `Data/`
dostarczane są dopiero na etapie `docker run` / `docker compose` — poprzez bind mount
oraz `--env-file`.

---

## 2. Pliki konfiguracyjne — środowisko lokalne a kontener

Ścieżki systemu Windows są rozłączne ze ścieżkami wewnątrz kontenera:

| Plik | Przeznaczenie | Rodzaj ścieżek |
|---|---|---|
| `ingestion\.env.<env>` | Uruchomienie lokalne | Windows (`C:\...`) |
| `ingestion\.env.docker.<env>` | Kontener poller | Kontenerowe (`/wallet`, `/app/ingestion/Data`) |
| `~/.oci/config` | OCI — środowisko lokalne | Windows (`key_file`) |
| `~/.oci/config.docker` | OCI — kontener | `key_file=/oci/<nazwa>.pem` |
| `orchestration\airflow_prod\.env.docker.<env>` | Airflow | Sekrety oraz ścieżki kontenerowe |

**Zasada:** ścieżki (`PKP_WALLET_DIR`, `PKP_DATA_ROOT`, `PKP_OCI_CONFIG_FILE`)
modyfikowane są wyłącznie w pliku właściwym dla danego kontenera — ścieżki Windows
w `.env.<env>`, ścieżki kontenerowe w `.env.docker.<env>`.

Oznaczenie `.<env>` odpowiada nazwie instancji (PROD lub DEV).

Wymagane w obrazie: `TZ=Europe/Warsaw` (spójność stref czasowych).

---

## 3. Poller — przebudowa i uruchomienie

Katalog roboczy:

```powershell
cd C:\<ścieżka>\<katalog projektu>\ingestion
```

### Przebudowa obrazu

```powershell
# Po zmianie kodu:
docker build -t pkp-poller:latest .

# Po zmianie wersji zależności (pyproject.toml) — bez cache, wymusza świeżą instalację:
docker build --no-cache -t pkp-poller:latest .
```

### Uruchomienie, zatrzymanie, podgląd

Zarządzanie realizowane jest przez `docker compose`, nie `docker run`:

```powershell
# Start (w tle; restart: unless-stopped):
docker compose --env-file .env.docker.prod -p pkp-poller-prod-live up -d poller-prod

# Po zmianie compose lub obrazu:
docker compose --env-file .env.docker.prod -p pkp-poller-prod-live up -d --force-recreate poller-prod

# Zatrzymanie:
docker compose -p pkp-poller-prod-live down

# Status (Up / healthy):
docker compose ps
```

### Diagnostyka

```powershell
docker exec pkp-poller-prod-live python -c "import oracledb; print(oracledb.__version__)"
docker exec pkp-poller-prod-live printenv | findstr PKP
docker exec pkp-poller-prod-live ls -la /app/ingestion/Data/PROD/STATE/LIVE
docker exec pkp-poller-prod-live ls -la /oci      # config.docker + klucz .pem
```

---

## 4. Airflow — przebudowa i uruchomienie

Katalog roboczy:

```powershell
cd C:\<ścieżka>\<katalog projektu>\orchestration\airflow_prod
```

### Zmiana kodu (DAG, `audit.py`, taski) — bez przebudowy

```powershell
docker exec pkp-airflow-daily-prod-airflow-scheduler-1 airflow dags reserialize
# alternatywnie: odczekać ~30 s (scheduler skanuje automatycznie) i wykonać Clear tasku w UI
```

### Zmiana wersji zależności (`requirements.txt`) lub Dockerfile — wymaga przebudowy

```powershell
docker compose --env-file .env.docker.prod -p pkp-airflow-daily-prod build --no-cache
docker compose --env-file .env.docker.prod -p pkp-airflow-daily-prod up -d
```

### Pierwsze uruchomienie (nowe środowisko)

```powershell
docker compose --env-file .env.docker.prod -p pkp-airflow-daily-prod build
docker compose --env-file .env.docker.prod -p pkp-airflow-daily-prod up airflow-init   # jednorazowo: migracja metadata + użytkownik admin (Exit 0)
docker compose --env-file .env.docker.prod -p pkp-airflow-daily-prod up -d             # scheduler + webserver + postgres
```

Interfejs: **http://localhost:8081** (dane logowania z `.env.docker.<env>`,
zmienne `AIRFLOW_ADMIN_*`). Oznaczenie `.<env>` odpowiada nazwie instancji (PROD lub DEV).

### Uruchomienie, zatrzymanie, podgląd

```powershell
docker compose --env-file .env.docker.prod -p pkp-airflow-daily-prod up -d
docker compose --env-file .env.docker.prod -p pkp-airflow-daily-prod down
docker compose --env-file .env.docker.prod -p pkp-airflow-daily-prod logs -f airflow-scheduler
docker compose --env-file .env.docker.prod -p pkp-airflow-daily-prod ps
```

### Diagnostyka

```powershell
docker exec pkp-airflow-daily-prod-airflow-scheduler-1 python -c "import oracledb; print(oracledb.__version__)"
docker exec pkp-airflow-daily-prod-airflow-scheduler-1 airflow dags list
docker exec pkp-airflow-daily-prod-airflow-scheduler-1 ls /opt/airflow/dags
```
