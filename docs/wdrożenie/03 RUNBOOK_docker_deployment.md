# PKP — Instrukcja wdrożenia Docker

Dokument opisuje uruchamianie i przebudowę kontenerów projektu PKP:
**poller (live)** oraz **Airflow (daily)**.

---

## 0. Architektura kontenerów

| Komponent   | Co robi                          | Kod w obrazie czy montowany? | Rejestr |
|-------------|----------------------------------|------------------------------|---------|
| `pkp-poller`| serwis LIVE 24/7 (pseudo-streaming, tick co ~3 min) | **W OBRAZIE** (`COPY`) → zmiana kodu = `docker build` | lokalny |
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
| `ingestion\.env`                  | uruchomienie LOKALNE | Windows (`C:\...`)  |
| `ingestion\.env.docker`           | kontener poller     | kontenerowe (`/wallet`, `/app/ingestion/Data`) |
| `~/.oci/config`                   | OCI lokalnie        | Windows key_file    |
| `~/.oci/config.docker`            | OCI w kontenerze    | `key_file=/oci/<nazwa>.pem` |
| `orchestration\airflow_prod\.env` | Airflow             | sekrety + kontenerowe |

**Reguła:** ścieżki (`PKP_WALLET_DIR`, `PKP_DATA_ROOT`, `PKP_OCI_CONFIG_FILE`)
edytujesz WYŁĄCZNIE w pliku właściwym dla danego kontenera. Windows tylko w `.env`,
kontenerowe tylko w `.env.docker`.

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
docker compose up -d poller-prod          # start (w tle, restart: unless-stopped)
docker compose up -d --force-recreate poller-prod   # po zmianie compose/obrazu
docker compose down                      # stop
docker compose ps                        # status (Up / healthy)
```

### Diagnostyka
```powershell
docker exec pkp-poller-prod python -c "import oracledb; print(oracledb.__version__)"
docker exec pkp-poller-prod printenv | findstr PKP
docker exec pkp-poller-prod ls -la /app/ingestion/Data/PROD/STATE/LIVE
docker exec pkp-poller-prod ls -la /oci      # config.docker + klucz .pem
```

---

## 4. AIRFLOW — build i uruchomienie

Katalog roboczy:
```powershell
cd C:\<ściezka>\<katalog projektu>\orchestration\airflow_prod
```

### Zmiana KODU (DAG, audit.py, taski) — BEZ build
```powershell
docker exec pkp-airflow-daily-airflow-scheduler-1 airflow dags reserialize
# ...albo poczekaj ~30s (scheduler sam skanuje) i zrób Clear tasku w UI
```

### Zmiana WERSJI (requirements.txt) lub Dockerfile — WYMAGA build
```powershell
docker compose build --no-cache
docker compose up -d
```

### Pierwsze uruchomienie (nowe środowisko)
```powershell
docker compose build
docker compose up airflow-init     # raz: migracja metadata + user admin (Exit 0)
docker compose up -d               # scheduler + webserver + postgres
```
UI: **http://localhost:8081** (login/hasło z `.env`: `AIRFLOW_ADMIN_*`).

### Start / stop / podgląd
```powershell
docker compose up -d
docker compose down
docker compose logs -f airflow-scheduler
docker compose ps
```

### Diagnostyka
```powershell
docker exec pkp-airflow-daily-airflow-scheduler-1 python -c "import oracledb; print(oracledb.__version__)"
docker exec pkp-airflow-daily-airflow-scheduler-1 airflow dags list
docker exec pkp-airflow-daily-airflow-scheduler-1 ls /opt/airflow/dags
```

---
