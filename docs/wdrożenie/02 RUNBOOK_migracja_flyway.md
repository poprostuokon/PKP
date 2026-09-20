# Runbook — migracja bazy PKP (Flyway)

Instrukcja wdrożenia struktury bazy na nową instancję Oracle ADB (23ai/26ai) za pomocą Flyway.
Spisane na bazie pierwszego wdrożenia **PROD** (`PKPPROD`).

---

## 1. Model migracji

- **Wszystkie migracje odpalane są jako `ADMIN`.** `DEV_APP` jest userem *runtime* (poller/Airflow), nie migracyjnym.
- Wszystkie tabele historii `flyway_schema_history_*` lądują w schemacie **`ADMIN`** (Flyway zakłada je w schemacie usera połączenia).
- **5 projektów Flyway**, każdy z własną tabelą historii i własnym `conf`:

  | Projekt       | Zawartość                                  |
  |---------------|--------------------------------------------|
  | `admin`       | userzy (DEV_APP/SILVER/GOLD/MAINTENANCE), granty, DWROLE |
  | `stg`         | landing JSON                               |
  | `maintenance` | `pkg_tool`, tabele utrzymaniowe, audyt     |
  | `silver`      | tabele + widoki + pakiety + triggery warstwy silver |
  | `gold`        | tabele + widoki + pakiety warstwy gold              |

- **Kolejność jest wymuszona zależnościami:** `admin → stg → maintenance → silver → gold`
  (silver/gold potrzebują schematów i `maintenance.pkg_tool` z wcześniejszych kroków).

---

## 2. Wymagania wstępne

- Wallet instancji rozpakowany (NIE jako ZIP), np. `C:\<ścieżka>\OCI\Wallet_PKPPROD`.
- Flyway CLI: `C:\flyway\flyway.cmd`.
- Repo (katalog z `migrations\`): `C:\<ścieżka>\<katalog projektu>`.
- Znane hasła: `ADMIN` (z tworzenia bazy) oraz `DEV_APP` (ustalane w skryptach projektu `admin`).

### Zmienne środowiskowe (PowerShell)

```powershell
$env:TNS_ADMIN="C:\<ścieżka>\katalog projektu\OCI\Wallet_PKPPROD"
$env:FLYWAY_URL="jdbc:oracle:thin:@pkpprod_high"
$env:FLYWAY_USER="ADMIN"
$env:FLYWAY_PASSWORD="<haslo>"
```

> `TNS_ADMIN` musi wskazywać wallet, inaczej `pkpprod_high` się nie rozwiąże (UnknownHostException).

---

## 3. Konwencja plików (V vs R)

- **`V<n>__opis.sql`** — wersjonowane (tabele, DDL strukturalny). Odpalane **RAZ**. Nie edytować po zaaplikowaniu — zmiana = **nowy plik V**.
- **`R__opis.sql`** — repeatable (pakiety, widoki, triggery, synonimy — `CREATE OR REPLACE`). Odpalane **za każdym razem, gdy zmieni się treść pliku**.

### Zasady dla repeatable
- Prefiks to **`R__`** (dwa podkreślniki), **bez numeru wersji**. `R1__` jest **niepoprawne** → Flyway po cichu pomija plik.
- Brak spacji po `R__` (`R__ pkg...` = błąd).
- Kolejność `R__` = **alfabetyczna po nazwie**, po wszystkich `V`. Zależności koduje się numerem w opisie, z zero-paddingiem:

```
R__01_pkg_silver_load.sql
R__02_def_audit_triggers.sql   # triggery po pakiecie (używają pkg_tool)
R__99_synonyms.sql             # jeśli synonimy wydzielone — na końcu
```

> Zero-padding obowiązkowy: `R__10` sortuje się PRZED `R__2`. Zawsze `R__01`, `R__02`, …

---

## 4. Pierwszy przebieg — świeża instancja

Wszystkie 5 projektów jako `ADMIN`, każdy z flagami baseline:

```powershell
$env:TNS_ADMIN="C:\<ścieżka>\<katalog projektu>\OCI\Wallet_PKPPROD"
$env:FLYWAY_URL="jdbc:oracle:thin:@pkpprod_high"
$env:FLYWAY_USER="ADMIN"
$env:FLYWAY_PASSWORD="<haslo>"

foreach ($p in "admin","stg","maintenance","silver","gold") {
  Write-Host "=== migrate: $p ==="
  cmd /c C:\flyway\flyway.cmd `
    "-configFiles=migrations\$p\conf\flyway.conf" `
    "-locations=filesystem:migrations\$p\sql" `
    "-baselineOnMigrate=true" "-baselineVersion=0" migrate
}
```

---

## 5. Ponowna migracja na istniejącej bazie

- `migrate` **NIE odpala ponownie** zaaplikowanych `V` — pomija je po tabeli historii.
- Odpala tylko **nowe `V`** oraz **`R__`, których treść się zmieniła**.
- Jeśli edytowano już zaaplikowany plik `V` → checksum się rozjedzie → błąd. Napraw przez `repair` (patrz §7).

---

## 6. Weryfikacja po migracji

```sql
-- userzy utworzeni?
SELECT username FROM dba_users
WHERE username IN ('DEV_APP','SILVER','GOLD','MAINTENANCE');   -- oczekiwane 4 wiersze

-- co Flyway widzi (per projekt)
-- cmd /c C:\flyway\flyway.cmd "-configFiles=..." "-locations=..." info

-- pakiety/widoki wgrane (repeatable)?
SELECT object_type, object_name, status FROM dba_objects
WHERE owner IN ('SILVER','GOLD','MAINTENANCE')
  AND object_type IN ('PACKAGE','PACKAGE BODY','VIEW','TRIGGER','SYNONYM')
ORDER BY owner, object_type, object_name;
```

Jeśli w logu migracji było `X SQL migrations detected but not run — did not follow the filename convention` → pliki `R__` mają złe nazwy (patrz §3), popraw i `migrate` ponownie.

---

## 7. `repair` — naprawa tabeli historii

`repair` **nie odpala żadnego SQL-a** i nie rusza obiektów. Działa wyłącznie na `flyway_schema_history_*`:
1. przelicza checksumy zaaplikowanych `V` do zgodności z plikami (kasuje mismatch),
2. usuwa wpisy nieudanych migracji.

```powershell
foreach ($p in "admin","stg","maintenance","silver","gold") {
  cmd /c C:\flyway\flyway.cmd `
    "-configFiles=migrations\$p\conf\flyway.conf" `
    "-locations=filesystem:migrations\$p\sql" repair
}
```

Kolejność przy rozjechanym checksumie: **`repair` → `migrate`**.

> `repair` to narzędzie awaryjne (faza deweloperska). Docelowo: zmiana = nowy plik `V`.

---

## 8. Reset instancji (start od zera)

Gdy trzeba wyczyścić i zacząć od nowa (świeża instancja bez danych):

```sql
-- 1) ubij sesje userów (inaczej ORA-01940: user currently connected)
BEGIN
  FOR s IN (SELECT sid, serial# FROM v$session
            WHERE username IN ('DEV_APP','SILVER','GOLD','MAINTENANCE')) LOOP
    EXECUTE IMMEDIATE 'ALTER SYSTEM KILL SESSION '''||s.sid||','||s.serial#||''' IMMEDIATE';
  END LOOP;
END;
/

-- 2) skasuj userów (CASCADE kasuje wszystkie obiekty i dane w schemacie)
DROP USER dev_app     CASCADE;
DROP USER silver      CASCADE;
DROP USER gold        CASCADE;
DROP USER maintenance CASCADE;
DROP USER stg         CASCADE;

-- 3) skasuj tabele historii Flyway
SELECT owner, table_name FROM dba_tables WHERE lower(table_name) LIKE 'flyway%';   -- najpierw sprawdź
DROP TABLE admin."flyway_schema_history_admin"       PURGE;
DROP TABLE admin."flyway_schema_history_stg"         PURGE;
DROP TABLE admin."flyway_schema_history_maintenance" PURGE;
DROP TABLE admin."flyway_schema_history_silver"      PURGE;
DROP TABLE admin."flyway_schema_history_gold"        PURGE;
```

Po resecie → pełny przebieg z §4.

---

## 9. Napotkane błędy i fixy (ściąga)

| Objaw | Przyczyna | Fix |
|---|---|---|
| `ERROR: Invalid flag: .conf` | PowerShell tnie argument na kropce/dwukropku | ujmij `-configFiles=` i `-locations=` w **cudzysłowy**, wołaj przez `cmd /c` |
| `Found non-empty schema(s) "ADMIN" but no schema history table` | ADMIN nigdy nie jest pusty | `-baselineOnMigrate=true -baselineVersion=0` |
| `Migration checksum mismatch for version 1` | edytowano już zaaplikowany plik `V` | `repair`, potem `migrate` |
| `ORA-01940: cannot drop a user that is currently connected` | otwarta sesja usera (często własne okno na DEV_APP) | ubij sesje z `v$session` (patrz §8), zamknij drugie okno |
| `X SQL migrations detected but not run — did not follow the filename convention` | pliki repeatable źle nazwane (`R1__`, spacja) | zmień na `R__NN_opis.sql` (§3) |
| pakiety/widoki się nie wgrały, tabele tak | to samo — `R__` pominięte przez złą nazwę | jak wyżej |

---

## 10. Zasady na przyszłość (po wdrożeniu)

- Zmiana struktury → **nowy plik `V`**, nigdy edycja zaaplikowanego (inaczej checksum + potrzeba `repair`).
- Zmiana logiki (pakiet/widok) → edycja pliku **`R__`**, Flyway odpali go sam.
- `repair` używać tylko awaryjnie.
