# Runbook — CI/CD pipeline PKP (GitHub Actions)

Dokument opisuje CI i CD dla projektu PKP oraz **wszystkie myki/pułapki** napotkane
przy wdrożeniu — żeby przy następnej zmianie nie tracić na nie godzin.

---

## 1. Podział ról: CI vs CD

| | CI (`ci.yml`) | CD (`cd.yml`) |
|---|---|---|
| Trigger | `push` / `pull_request` (auto) | `workflow_dispatch` (ręczny przycisk) |
| Runner | GitHub-hosted (`ubuntu-latest`) | **self-hosted na Optiplexie** (label `optiplex`) |
| Co robi | test + lint + `flyway validate` (read-only) | `flyway migrate` DEV → PROD (za Approve) |
| Baza | PKPDEV | PKPDEV, potem PKPPROD |
| Wallet | z sekretu base64 (runner efemeryczny) | **lokalny z dysku** (runner = Optiplex) |
| Zmienia bazę? | NIE (tylko waliduje) | TAK (migruje schemat) |

**Zasada:** CI = brama jakości (nic nie wdraża, tylko sprawdza). CD = wdrożenie
schematu, prod zawsze za ręcznym zatwierdzeniem.

---

## 2. CI — `ci.yml`

Trzy joby:
- **test** — `pip install`, `pip-audit`, `ruff check`, `pytest`.
- **gitleaks** — skan sekretów w historii.
- **flyway-validate** — `validate` na PKPDEV dla 5 projektów (`admin, stg, maintenance, silver, gold`).

Sekrety (DEV):
- `PKP_WALLET_PKPDEV_ZIP_B64` — wallet DEV spakowany do zip → base64 (dekodowany w runnerze).
- `PKP_DB_PASSWORD` — hasło `DEV_APP` (validate łączy się jako DEV_APP).

Myki CI:
- `validate` **sprawdza checksumy** zaaplikowanych migracji. Edycja już zaaplikowanego
  `V` → mismatch → **czerwone CI**. Naprawa: `repair` (patrz §6).
- Flaga `-ignoreMigrationPatterns="*:pending"` sprawia, że zmieniony `R__` (pending)
  **nie jest błędem** — validate przechodzi.
- CI leci na **ubuntu**, więc wallet musi iść jako base64 (na dysku runnera go nie ma).

---

## 3. CD — architektura

**Self-hosted runner na Optiplexie** — konieczny, bo:
- runtime (poller + Airflow + prod ADB) jest za domowym NAT → CD musi być **pull-based**,
- runner = ta sama maszyna, która ma na dysku **walletty, `.oci`, `Data`, Dockera**.

**Kluczowy uproszczacz vs CI:** runner ma wallet **lokalnie**, więc:
- Flyway używa lokalnego folderu (`TNS_ADMIN` → ścieżka na dysku) — **ZERO base64**,
- z GitHuba potrzeba tylko **haseł DB** (Secrets); wallet jest lokalny.

Runner:
- katalog `C:\actions-runner`, Windows x64, label `optiplex`,
- na razie `./run.cmd` (trzyma się okna — zamknięcie = runner pada),
- docelowo usługa: `./svc.cmd install` + `./svc.cmd start` (wstaje z systemem),
- musi działać na koncie Windows, które ma dostęp do walletów/`.oci`/`Data`/Dockera.

Sekrety (PROD) — pod `Settings → Environments → prod` (za bramką Approve):
- `PKP_WALLET_PKPPROD_ZIP_B64` (na przyszłość / gdyby wallet szedł z sekretu),
- `PKP_ADMIN_PASSWORD_PROD` — migracje lecą jako **ADMIN**.

Dodatkowo (repo secrets):
- `PKP_ADMIN_PASSWORD_DEV` — migrate DEV też jako ADMIN.

**Do GitHuba NIE dajesz:** `PKP_API_KEY`, `.oci`/PEM, nazw bucketów, `.env.docker.*` —
to runtime na Optiplexie. GitHub tyka wyłącznie schemat (Flyway).

---

## 4. CD — przepływ `cd.yml`

```
workflow_dispatch (Actions → CD → Run workflow)
  migrate-dev   → flyway migrate PKPDEV  (lokalny wallet Wallet_PKPDEV)
  migrate-prod  → needs: migrate-dev
                  environment: prod  (czeka na Approve)
                  flyway migrate PKPPROD (lokalny wallet Wallet_PKPPROD)
  [deploy]      → opcjonalnie: rebuild pollera + up kontenerów (patrz §7)
```

Environment `prod` (Settings → Environments → prod):
- **Required reviewers = Twoje konto** (`poprostuokon`),
- **Prevent self-review = ODZNACZONE** — inaczej sam siebie nie zatwierdzisz (blokada na amen).

---

## 5. MYKI CD — składnia workflow (kosztowały najwięcej czasu)

**PowerShell tnie argument na kropce.**
`-configFiles=...flyway.conf` bez cudzysłowów → `ERROR: Invalid flag: .conf`.
Fix: ujmij w cudzysłów:
```yaml
"-configFiles=/repo/migrations/$p/conf/flyway.conf"
"-locations=filesystem:/repo/migrations/$p/sql"
```

**YAML block scalar `run: |` — spójne wcięcia.**
Rozjechane wcięcia w bloku `run: |` → `Invalid workflow file … line N`.
Wszystkie linie pod `run: |` z **równym** wcięciem, **spacje nie taby**.

**Sekret pusty / źle nazwany → `FLYWAY_PASSWORD` len=0 → `ORA-01005`.**
Objaw: „invalid password", choć hasło jest dobre. Przyczyny:
- literówka w nazwie sekretu (wielkość liter się liczy),
- blok `env:` wcięty pod `steps:` zamiast pod jobem.
Test (nie pokazuje hasła):
```yaml
- name: debug
  shell: powershell
  run: Write-Host "len=$($env:FLYWAY_PASSWORD.Length)"
```
`len=0` → sekret nie dochodzi. `len=<długość hasła>` → OK.

**Znaki specjalne w haśle przez `-password="$env:..."`.**
PowerShell może zepsuć `$`, `` ` ``, `"`, `#`. Alternatywa — przekaż env do kontenera
zamiast flagą; Flyway sam czyta `FLYWAY_PASSWORD`:
```yaml
docker run --rm -e FLYWAY_PASSWORD ... redgate/flyway:11 -url=... -user=... migrate
# (bez -password=...)
```

**Nazwa workflow na liście = `name:` z pliku, nie nazwa pliku.**
To kosmetyka, nie błąd. Workflow pojawia się w Actions dopiero, gdy plik jest na `main`.

---

## 6. MYKI CD — Flyway / Oracle (najważniejsze)

**`CREATE TABLE IF NOT EXISTS` jest NIEPOPRAWNE w Oracle.**
- Parser Flyway: `Incomplete statement` → cały projekt leży.
- SQL Developer po cichu tworzy tabelę o nazwie **`IF`** (bo parsuje `CREATE TABLE "IF"`),
  a właściwej tabeli nie robi — pułapka „u mnie działa".
- **Fix:** usuń `IF NOT EXISTS` ze wszystkich `V`. Idempotentność w Flyway daje **historia
  migracji**, nie składnia SQL — zaaplikowany `V` nigdy nie odpala się drugi raz.
- Grep: `Select-String -Path .\migrations\*\sql\*.sql -Pattern "IF NOT EXISTS"`.

**Baza niepusta + brak historii Flyway → potrzebny baseline.**
Objaw: `Found non-empty schema(s) "ADMIN" but no schema history table`.
- `flyway_schema_history_* does not exist` = brak **tabeli historii Flyway** (metadane),
  NIE brak Twoich tabel.
- Rozwiązanie: `-baselineOnMigrate=true`. `baselineVersion` decyduje, do której wersji
  Flyway uzna migracje za „już zrobione".

**DEV: baseline PER PROJEKT (tabele istniały, historii nie było).**
`baselineVersion=0` na niepustej bazie → Flyway próbuje odpalić `V1 CREATE TABLE` na
istniejącej tabeli → `ORA-00955: name already used`.
Fix: `baselineVersion` = **max V w danym projekcie** (mapa, nie jedna wartość):
```powershell
$baseline = @{ admin=1; stg=12; maintenance=6; silver=16; gold=13 }
# w pętli: -baselineOnMigrate=true "-baselineVersion=$($baseline[$p])"
```
Efekt: Flyway wpisuje istniejące `V` jako baseline (pomija je), odpala tylko nowsze `V` + `R__`.

> Liczby max V odczytasz z plików:
> ```powershell
> foreach ($p in "admin","stg","maintenance","silver","gold") {
>   $m = Get-ChildItem ".\migrations\$p\sql\V*.sql" |
>     %{ [int]($_.Name -replace '^V(\d+)__.*','$1') } | Measure-Object -Maximum
>   Write-Host "$p = $($m.Maximum)"
> }
> ```

**Baseline działa TYLKO gdy tabeli historii jeszcze nie ma.**
Jak po nieudanych próbach zostały tabele historii ze złym baseline=0 → zmiana
`baselineVersion` nic nie da. Najpierw skasuj śmieciową historię (jako ADMIN):
```sql
BEGIN
  FOR t IN (SELECT owner, table_name FROM dba_tables
            WHERE lower(table_name) LIKE 'flyway_schema_history%') LOOP
    EXECUTE IMMEDIATE 'DROP TABLE '||t.owner||'."'||t.table_name||'" PURGE';
  END LOOP;
END;
/
```

**Checksum mismatch (edytowany `V` po zaaplikowaniu) → `repair`.**
Objaw: `Migration checksum mismatch for migration version N`.
Przyczyna u nas: usunięcie `IF NOT EXISTS` zmieniło treść `V` już zaaplikowanych na PROD.
`repair` **nie odpala SQL-a, nie rusza danych ani struktury** — tylko synchronizuje
checksumy w historii z aktualnymi plikami.
Lokalnie na PROD:
```powershell
$env:TNS_ADMIN     = "C:\BAOK\python\stream_mpk\OCI\Wallet_PKPPROD"
$env:FLYWAY_URL    = "jdbc:oracle:thin:@pkpprod_high"
$env:FLYWAY_USER   = "ADMIN"
$env:FLYWAY_PASSWORD = "<haslo ADMIN PROD>"
$flyway = "C:\flyway\flyway.cmd"; $root = "C:\BAOK\python\stream_mpk"
foreach ($p in "admin","stg","maintenance","silver","gold") {
  & $flyway "-configFiles=$root\migrations\$p\conf\flyway.conf" `
            "-locations=filesystem:$root\migrations\$p\sql" `
            "-url=$env:FLYWAY_URL" "-user=$env:FLYWAY_USER" "-password=$env:FLYWAY_PASSWORD" repair
}
```
Można też wpiąć pętlę `repair` **przed** `migrate` w `cd.yml` (idempotentne, samo-naprawia).

**PROD vs DEV — różne traktowanie:**
- **DEV** miał tabele bez historii → baseline per projekt (adopcja istniejących tabel).
- **PROD** ma już poprawną historię z pierwszej migracji → **zwykły `migrate`**, BEZ baseline.

---

## 7. Deploy kontenerów (opcjonalny klocek — kiedy przeładować)

Migracja schematu **nie** wymaga przeładowania kontenerów. Reload tylko przy zmianie **kodu**:

| Co się zmieniło | Akcja |
|---|---|
| Tylko migracja Flyway (schemat) | nic — kontenery jadą dalej |
| Kod DAG / plugins / ingestion (Airflow) | repo jest montowane → bez rebuildu; restart schedulera / reserialize (~30 s) |
| Kod pollera | COPY do obrazu → **rebuild + `--force-recreate`** |

Ręcznie (poller):
```powershell
docker build -t pkp-poller:latest ingestion
docker compose --env-file ingestion\.env.docker.prod -p pkp-poller-prod-live up -d --force-recreate poller-prod
```

---

## 8. DEV keep-alive (kontekst — pilnuje, żeby DEV nie usnął)

Always Free ADB: **7 dni bez sesji DB → auto-stop**; 3 miesiące stop → reclaim.
Rozwiązanie: task `keepalive_dev` w DAG-u `pkp_daily` (liść po `send_report`,
`trigger_rule=all_done`) — jeden `SELECT 1 FROM dual` do DEV przy każdym runie daily
(daily leci na PROD, więc to on utrzymuje DEV).

Myki:
- Prod-kontener Airflow trzyma **dwa walletty**: `/wallet` (prod) + `/wallet_dev` (dev, mount),
  plus env `KEEPALIVE_DEV_{DSN,USER,PASSWORD,WALLET_DIR,WALLET_PASSWORD}`.
- oracledb thin **wymaga `wallet_password`** (wallet DEV ma szyfrowany `ewallet.pem`;
  bez hasła → `OSError [Errno 22]` przy budowie SSL).
- Weryfikacja aktywności DEV: pytaj jako **ADMIN** (DEV_APP nie widzi `v$session`/
  `unified_audit_trail`). Na ADB `dba_audit_trail` bywa puste (unified auditing).
  Najprostszy dowód: zielony task + **State = Available** w konsoli OCI.

---

## 9. Szybka checklista przy nowej migracji

1. Zmiana struktury → **nowy plik `V`** (nigdy edycja zaaplikowanego — checksum mismatch).
2. Zmiana logiki (pakiet/widok) → edycja `R__` (Flyway odpali sam).
3. `git push` → **CI** (validate na DEV) musi być zielone.
4. **CD** → Run workflow → `migrate-dev` → Approve → `migrate-prod`.
5. Jak checksum mismatch → `repair` przed `migrate`.
6. Zmiana kodu pollera → rebuild + recreate; kod Airflow → tylko restart schedulera.
