# CI/CD — Dokumentacja pipeline'u PKP

Dokument opisuje proces Continuous Integration (CI) i Continuous Deployment (CD)
dla projektu PKP, zaimplementowany w GitHub Actions. Obejmuje architekturę obu
procesów, podział odpowiedzialności, zarządzanie sekretami oraz udokumentowane
decyzje projektowe i rozwiązania problemów napotkanych podczas wdrożenia.

Stack: GitHub Actions · Flyway (wersjonowanie schematu) · Oracle Autonomous Database
(DEV/PROD) · Docker · self-hosted runner (Windows).

---

## 1. Architektura — podział odpowiedzialności

Pipeline realizuje rozdział walidacji od wdrożenia. CI weryfikuje jakość kodu i
poprawność migracji bez modyfikacji środowisk. CD wykonuje wdrożenie schematu na
środowiska docelowe, z obowiązkową akceptacją przed produkcją.

| Aspekt | CI (`ci.yml`) | CD (`cd.yml`) |
|---|---|---|
| Wyzwalacz | `push` / `pull_request` (automatyczny) | `workflow_dispatch` (ręczny) |
| Środowisko wykonania | GitHub-hosted (`ubuntu-latest`) | self-hosted runner (label `optiplex`) |
| Zakres | testy jednostkowe, lint, `flyway validate` | `flyway migrate` na DEV, następnie PROD |
| Baza danych | PKPDEV | PKPDEV → PKPPROD |
| Dostęp do wallet | z sekretu (base64) | z lokalnego dysku runnera |
| Modyfikacja bazy | nie (walidacja read-only) | tak (migracja schematu) |

Założenie projektowe: CI stanowi bramę jakości niewprowadzającą zmian w środowiskach;
CD wykonuje wdrożenie, przy czym każde wdrożenie na produkcję wymaga ręcznej akceptacji.

---

## 2. Continuous Integration — `ci.yml`

Proces CI składa się z trzech niezależnych zadań:

- **test** — instalacja zależności, audyt bezpieczeństwa pakietów (`pip-audit`),
  analiza statyczna (`ruff`), testy jednostkowe (`pytest`).
- **gitleaks** — skanowanie repozytorium pod kątem przypadkowo ujawnionych sekretów.
- **flyway-validate** — walidacja migracji dla pięciu projektów Flyway
  (`admin`, `stg`, `maintenance`, `silver`, `gold`) względem instancji PKPDEV.

### Sekrety (środowisko DEV)

| Sekret | Przeznaczenie |
|---|---|
| `PKP_WALLET_PKPDEV_ZIP_B64` | Wallet PKPDEV spakowany i zakodowany w base64; dekodowany na runnerze |
| `PKP_DB_PASSWORD` | Hasło użytkownika `DEV_APP` używane przy walidacji |

### Uwagi implementacyjne

- Polecenie `validate` weryfikuje sumy kontrolne (checksum) zastosowanych migracji.
  Modyfikacja treści już zastosowanego pliku `V` powoduje niezgodność sumy kontrolnej
  i błąd walidacji. Procedurę naprawczą opisano w sekcji 6.
- Parametr `-ignoreMigrationPatterns="*:pending"` zapewnia, że zmodyfikowany plik
  repeatable (`R__`) w stanie *pending* nie jest traktowany jako błąd.
- Runner GitHub-hosted jest efemeryczny i nie posiada dostępu do lokalnego systemu
  plików Optiplexa, dlatego wallet dostarczany jest w formie zakodowanego sekretu.

---

## 3. Continuous Deployment — architektura

### Self-hosted runner

Wdrożenie realizowane jest przez self-hosted runner GitHub Actions uruchomiony na
serwerze Optiplex. Rozwiązanie jest podyktowane topologią infrastruktury:

- środowisko uruchomieniowe (poller, Airflow, produkcyjna instancja ADB) znajduje się
  za translacją adresów (NAT), co wymusza model *pull-based*;
- runner działa na maszynie posiadającej lokalnie walletty, konfigurację OCI, katalog
  danych oraz środowisko Docker.

Konsekwencją tej architektury jest istotne uproszczenie względem CI: ponieważ runner
posiada wallet lokalnie, Flyway korzysta z katalogu na dysku (`TNS_ADMIN` wskazujący
lokalną ścieżkę), eliminując konieczność kodowania walletu w base64. Z repozytorium
GitHub pobierane są wyłącznie hasła do bazy danych.

Konfiguracja runnera:

- lokalizacja `C:\actions-runner`, platforma Windows x64, etykieta `optiplex`;
- w fazie rozwojowej uruchamiany interaktywnie (`./run.cmd`);
- docelowo instalowany jako usługa systemowa (`./svc.cmd install` / `start`),
  co zapewnia automatyczne uruchomienie po restarcie systemu;
- musi działać na koncie systemowym posiadającym dostęp do walletów, konfiguracji OCI,
  katalogu danych oraz Dockera.

### Sekrety

| Sekret | Zakres | Przeznaczenie |
|---|---|---|
| `PKP_ADMIN_PASSWORD_DEV` | repozytorium | Hasło `ADMIN` na PKPDEV (migracje wykonywane jako ADMIN) |
| `PKP_ADMIN_PASSWORD_PROD` | environment `prod` | Hasło `ADMIN` na PKPPROD |
| `PKP_WALLET_PKPPROD_ZIP_B64` | environment `prod` | Wallet PROD (rezerwowo) |

Zakres danych utrzymywanych w GitHub jest celowo ograniczony do sekretów niezbędnych
dla Flyway. Klucz API, konfiguracja OCI, nazwy bucketów oraz pliki `.env.docker.*`
pozostają wyłącznie w środowisku uruchomieniowym na serwerze Optiplex — GitHub Actions
operuje jedynie na warstwie schematu bazy danych.

---

## 4. Continuous Deployment — przepływ `cd.yml`

```
workflow_dispatch  (Actions → CD → Run workflow)
  │
  ├─ migrate-dev    flyway migrate → PKPDEV   (lokalny wallet Wallet_PKPDEV)
  │
  ├─ migrate-prod   needs: migrate-dev
  │                 environment: prod          (wymaga akceptacji)
  │                 flyway migrate → PKPPROD   (lokalny wallet Wallet_PKPPROD)
  │
  └─ [deploy]       opcjonalnie: przebudowa obrazu i restart kontenerów (sekcja 7)
```

### Bramka akceptacji (GitHub Environment `prod`)

Konfiguracja w `Settings → Environments → prod`:

- **Required reviewers** — wskazane konto zatwierdzające; zadanie `migrate-prod`
  wstrzymuje się do momentu ręcznej akceptacji w interfejsie Actions.
- **Prevent self-review** — wyłączone. W konfiguracji jednoosobowej włączenie tej opcji
  uniemożliwiłoby zatwierdzenie własnego wdrożenia.

Zależność `needs: migrate-dev` gwarantuje, że produkcja migrowana jest wyłącznie po
pomyślnej migracji środowiska DEV.

---

## 5. Rozwiązane problemy — warstwa GitHub Actions / PowerShell

Poniższe przypadki zostały zidentyfikowane i rozwiązane podczas wdrożenia.

### Interpretacja argumentów przez PowerShell

Argumenty zawierające kropkę (np. ścieżka do `flyway.conf`) są dzielone przez
PowerShell, co skutkuje błędem `Invalid flag: .conf`. Rozwiązaniem jest ujęcie
argumentów w cudzysłowy:

```yaml
"-configFiles=/repo/migrations/$p/conf/flyway.conf"
"-locations=filesystem:/repo/migrations/$p/sql"
```

### Formatowanie bloku YAML

Blok `run: |` wymaga jednolitego wcięcia wszystkich linii (wyłącznie spacje).
Niespójne wcięcie skutkuje błędem `Invalid workflow file`.

### Niedostarczenie sekretu do zmiennej środowiskowej

Pusta lub błędnie nazwana zmienna `FLYWAY_PASSWORD` (długość 0) powoduje odrzucenie
logowania (`ORA-01005: invalid password`) mimo poprawnego hasła. Najczęstsze przyczyny:
błąd w nazwie sekretu (rozróżnialna wielkość liter) lub umieszczenie bloku `env:` na
niewłaściwym poziomie (pod `steps:` zamiast pod zadaniem). Diagnostyka bez ujawniania
wartości:

```yaml
- name: debug
  shell: powershell
  run: Write-Host "len=$($env:FLYWAY_PASSWORD.Length)"
```

### Znaki specjalne w haśle

Przekazanie hasła flagą `-password="$env:..."` może prowadzić do zniekształcenia znaków
specjalnych przez PowerShell. Rekomendowanym rozwiązaniem jest przekazanie zmiennej
bezpośrednio do kontenera; Flyway odczytuje `FLYWAY_PASSWORD` samodzielnie:

```yaml
docker run --rm -e FLYWAY_PASSWORD ... redgate/flyway:11 -url=... -user=... migrate
```

---

## 6. Rozwiązane problemy — warstwa Flyway / Oracle

Poniższe przypadki zostały zidentyfikowane i rozwiązane podczas wdrożenia.


### Niezgodność sum kontrolnych

Objaw: `Migration checksum mismatch for migration version N`. Przyczyną była modyfikacja
treści plików `V` już po ich zastosowaniu na produkcji.
Polecenie `repair` synchronizuje sumy kontrolne w historii z aktualną treścią plików;
nie wykonuje kodu SQL ani nie modyfikuje danych i struktury:

```powershell
$env:TNS_ADMIN       = "C:\BAOK\python\stream_mpk\OCI\Wallet_PKPPROD"
$env:FLYWAY_URL      = "jdbc:oracle:thin:@pkpprod_high"
$env:FLYWAY_USER     = "ADMIN"
$env:FLYWAY_PASSWORD = "<haslo ADMIN PROD>"
$flyway = "C:\flyway\flyway.cmd"; $root = "C:\BAOK\python\stream_mpk"
foreach ($p in "admin","stg","maintenance","silver","gold") {
  & $flyway "-configFiles=$root\migrations\$p\conf\flyway.conf" `
            "-locations=filesystem:$root\migrations\$p\sql" `
            "-url=$env:FLYWAY_URL" "-user=$env:FLYWAY_USER" "-password=$env:FLYWAY_PASSWORD" repair
}
```


---

## 7. Wdrożenie kontenerów — zakres przeładowania (Opcjonalne)

Migracja schematu nie wymaga restartu kontenerów. Ponowne uruchomienie jest konieczne
wyłącznie przy zmianie kodu aplikacji:

| Zakres zmiany | Wymagane działanie |
|---|---|
| Migracja schematu (Flyway) | brak — kontenery pozostają uruchomione |
| Kod DAG / pluginów / ingestion (Airflow) | repozytorium montowane jako wolumen — bez przebudowy; restart schedulera lub reserializacja |
| Kod pollera | kod kopiowany do obrazu — wymagana przebudowa obrazu i odtworzenie kontenera |

Przykład (poller):

```powershell
docker build -t pkp-poller:latest ingestion
docker compose --env-file ingestion\.env.docker.prod -p pkp-poller-prod-live up -d --force-recreate poller-prod
```

---

## 8. Utrzymanie dostępności środowiska DEV

Instancje Oracle Autonomous Database w warstwie Always Free podlegają automatycznemu
zatrzymaniu po 7 dniach bez połączenia oraz odzyskaniu zasobów po 3 miesiącach
zatrzymania. Aby zapobiec zatrzymaniu DEV — które skutkowałoby niepowodzeniem CI —
zaimplementowano mechanizm podtrzymania aktywności w ramach codziennego procesu Airflow.

Zadanie `keepalive_dev` (węzeł końcowy DAG-a `pkp_daily`, `trigger_rule=all_done`)
wykonuje pojedyncze zapytanie `SELECT 1 FROM dual` do instancji DEV przy każdym
uruchomieniu procesu dziennego. Ponieważ proces dzienny operuje na produkcji, to on
utrzymuje aktywność środowiska DEV.

Uwagi implementacyjne:

- kontener produkcyjny Airflow udostępnia dwa walletty — produkcyjny (`/wallet`) oraz
  deweloperski (`/wallet_dev`) — wraz z odpowiednim zestawem zmiennych konfiguracyjnych;
- sterownik `oracledb` w trybie *thin* wymaga hasła walletu (wallet DEV zawiera
  zaszyfrowany `ewallet.pem`; jego brak skutkuje błędem inicjalizacji SSL);
- weryfikacja aktywności wymaga uprawnień `ADMIN` (użytkownik `DEV_APP` nie posiada
  dostępu do `v$session` ani `unified_audit_trail`). Podstawowym potwierdzeniem
  aktywności jest status `Available` instancji w konsoli OCI.

---

## 9. Procedura wprowadzania zmian w schemacie

1. Zmiana struktury — nowy plik `V` (modyfikacja zastosowanego pliku prowadzi do
   niezgodności sumy kontrolnej).
2. Zmiana logiki (pakiet, widok) — modyfikacja pliku `R__`.
3. `git push` — proces CI musi zakończyć się powodzeniem.
4. CD — uruchomienie `workflow_dispatch`: `migrate-dev` → akceptacja → `migrate-prod`.
5. W przypadku niezgodności sum kontrolnych — `repair` przed `migrate`.
6. Zmiana kodu pollera — przebudowa i odtworzenie kontenera; zmiana kodu Airflow —
   restart schedulera.
