# PKP — Instrukcja wdrożenia Docker

Dokument opisuje uruchamianie i przebudowę kontenerów projektu PKP:
**poller (live)** oraz **Airflow (daily)**.

---

## 0. Architektura kontenerów

| Komponent   | Co robi                          | Kod w obrazie czy montowany? | Rejestr |
|-------------|----------------------------------|------------------------------|---------|
| `pkp-poller`| serwis LIVE 24/7 ("streaming" micro-batch, tick co ~3 min) | **W OBRAZIE** (`COPY`) → zmiana kodu = `docker build` | lokalny |
| `airflow`   | orkiestracja batch DAILY (scheduler + webserver + metadata Postgres) | **MONTOWANY** (całe repo jako wolumen) → zmiana kodu bez build | lokalny |

---

## 1. Zasada nadrzędna: obraz = tylko kod, sekrety z hosta

Obraz **nigdy** nie zawiera sekretów. Wallet, `.oci`, `.env` i katalog `Data/`
są inicjowane dopiero przy `docker run` / `docker compose` jako **(bind mount)**
i `--env-file`.

---

## 2. Pliki konfiguracyjne (lokalny vs kontener)

Ścieżki Windows ≠ ścieżki kontenerowe:

| Plik                              | Do czego            | Ścieżki             |
|-----------------------------------|---------------------|---------------------|
| `ingestion\.env.<env>`                  | uruchomienie LOKALNE | Windows (`C:\...`)  |
| `ingestion\.env.docker.<env>`           | kontener poller     | kontenerowe (`/wallet`, `/app/ingestion/Data`) |
| `~/.oci/config`                   | OCI lokalnie        | Windows key_file    |
| `~/.oci/config.docker`            | OCI w kontenerze    | `key_file=/oci/<nazwa>.pem` |
| `orchestration\airflow_prod\.env.docker.<env>` | Airflow             | sekrety + kontenerowe |

**Reguła:** ścieżki (`PKP_WALLET_DIR`, `PKP_DATA_ROOT`, `PKP_OCI_CONFIG_FILE`)
edytujesz WYŁĄCZNIE w pliku właściwym dla danego kontenera. Windows tylko w `.env.<env>`,
kontenerowe tylko w `.env.docker.<env>`. 

`.<env>` - nazwa instancji (PROD lub DEV).

Wymagane w obrazie:
`TZ=Europe/Warsaw` (spójność stref).

---

## 3. POLLER — build i uruchomienie

Katalog roboczy:
```powershell
cd C:\<ściezka>\<katalog projektu>\ingestion
```

### Build
```powershell
# po zmianie KODU:
docker build -t pkp-poller:latest .

# po zmianie WERSJI zależności (pyproject.toml) — BEZ cache (wymusza świeżą instalację):
docker build --no-cache -t pkp-poller:latest .
```

### Start / stop / podgląd (zarządzaj przez compose, NIE `docker run`)
```powershell
docker compose --env-file .env.docker.prod -p pkp-poller-prod-live up -d poller-prod                    # start (w tle, restart: unless-stopped)
docker compose --env-file .env.docker.prod -p pkp-poller-prod-live up -d --force-recreate poller-prod   # po zmianie compose/obrazu
docker compose -p pkp-poller-prod-live down                                                             # stop
docker compose ps                                                                                       # status (Up / healthy)
```

### Diagnostyka
```powershell
docker exec pkp-poller-prod-live python -c "import oracledb; print(oracledb.__version__)"
docker exec pkp-poller-prod-live printenv | findstr PKP
docker exec pkp-poller-prod-live ls -la /app/ingestion/Data/PROD/STATE/LIVE
docker exec pkp-poller-prod-live ls -la /oci      # config.docker + klucz .pem
```

---

## 4. AIRFLOW — build i uruchomienie

Katalog roboczy:
```powershell
cd C:\<ściezka>\<katalog projektu>\orchestration\airflow_prod
```

### Zmiana KODU (DAG, audit.py, taski) — BEZ build
```powershell
docker exec pkp-airflow-daily-prod-airflow-scheduler-1 airflow dags reserialize
# ...albo poczekaj ~30s (scheduler sam skanuje) i zrób Clear tasku w UI
```

### Zmiana WERSJI (requirements.txt) lub Dockerfile — WYMAGA build
```powershell
docker compose --env-file .env.docker.prod -p pkp-airflow-daily-prod build --no-cache
docker compose --env-file .env.docker.prod -p pkp-airflow-daily-prod up -d
```

### Pierwsze uruchomienie (nowe środowisko)
```powershell
docker compose --env-file .env.docker.prod -p pkp-airflow-daily-prod build
docker compose --env-file .env.docker.prod -p pkp-airflow-daily-prod up airflow-init     # raz: migracja metadata + user admin (Exit 0)
docker compose --env-file .env.docker.prod -p pkp-airflow-daily-prod up -d               # scheduler + webserver + postgres
```
UI: **http://localhost:8081** (login/hasło z `.env.docker.<env>`: `AIRFLOW_ADMIN_*`).

`.<env>` - nazwa instancji (PROD lub DEV).

### Start / stop / podgląd
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

---
