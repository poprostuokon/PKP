# Runbook — migracja bazy danych PKP (Flyway)

Dokument opisuje procedurę wdrożenia struktury bazy danych na instancję Oracle Autonomous
Database (23ai/26ai) przy użyciu Flyway. Procedurę opracowano na podstawie pierwszego
wdrożenia środowiska produkcyjnego (`PKPPROD`).

---

## 1. Model migracji

- Wszystkie migracje wykonywane są jako użytkownik **`ADMIN`**. Użytkownik `DEV_APP`
  pełni rolę konta runtime (poller, Airflow) i nie jest wykorzystywany do migracji.
- Tabele historii `flyway_schema_history_*` tworzone są w schemacie **`ADMIN`** — Flyway
  zakłada je w schemacie użytkownika połączenia.
- Struktura podzielona jest na **pięć projektów Flyway**, z których każdy posiada własną
  tabelę historii oraz własny plik konfiguracyjny:

  | Projekt | Zawartość |
  |---|---|
  | `admin` | Użytkownicy (DEV_APP, SILVER, GOLD, MAINTENANCE), granty, DWROLE |
  | `stg` | Landing JSON |
  | `maintenance` | `pkg_tool`, tabele utrzymaniowe, audyt |
  | `silver` | Tabele, widoki, pakiety i triggery warstwy silver |
  | `gold` | Tabele, widoki i pakiety warstwy gold |

- Kolejność wykonania jest wymuszona zależnościami: **`admin → stg → maintenance → silver
  → gold`**. Warstwy silver i gold wymagają schematów oraz pakietu `maintenance.pkg_tool`
  utworzonych w krokach wcześniejszych.

---

## 2. Wymagania wstępne

- Rozpakowany wallet instancji (nie w postaci archiwum ZIP), np.
  `C:\<ścieżka>\OCI\Wallet_PKPPROD`.
- Flyway CLI: `C:\flyway\flyway.cmd`.
- Repozytorium zawierające katalog `migrations\`.
- Znane hasła: `ADMIN` (ustalone przy tworzeniu bazy) oraz `DEV_APP` (definiowane w
  skryptach projektu `admin`).

### Zmienne środowiskowe (PowerShell)

```powershell
$env:TNS_ADMIN="C:\<ścieżka>\<katalog projektu>\OCI\Wallet_PKPPROD"
$env:FLYWAY_URL="jdbc:oracle:thin:@pkpprod_high"
$env:FLYWAY_USER="ADMIN"
$env:FLYWAY_PASSWORD="<haslo>"
```

`TNS_ADMIN` musi wskazywać katalog walletu — w przeciwnym razie nazwa usługi
`pkpprod_high` nie zostanie rozwiązana (`UnknownHostException`).

---

## 3. Konwencja plików migracji (V oraz R)

- **`V<n>__opis.sql`** — migracje wersjonowane (tabele, DDL strukturalny). Wykonywane
  jednokrotnie. Pliku nie wolno modyfikować po zastosowaniu — każda zmiana wymaga
  utworzenia **nowego pliku `V`**.
- **`R__opis.sql`** — migracje repeatable (pakiety, widoki, triggery, synonimy —
  `CREATE OR REPLACE`). Wykonywane ponownie przy każdej zmianie treści pliku.

### Zasady dla migracji repeatable

- Prefiks to **`R__`** (dwa podkreślniki), bez numeru wersji. Zapis `R1__` jest
  niepoprawny — Flyway pomija taki plik bez ostrzeżenia.
- Brak spacji po `R__` (`R__ pkg...` jest błędem).
- Migracje `R__` wykonywane są w kolejności alfabetycznej według nazwy, po wszystkich
  migracjach `V`. Zależności koduje się numerem w nazwie, z uzupełnieniem zerami:

```
R__01_pkg_silver_load.sql
R__02_def_audit_triggers.sql   # triggery po pakiecie (korzystają z pkg_tool)
R__99_synonyms.sql             # synonimy — na końcu, jeśli wydzielone
```

Uzupełnianie zerami jest obowiązkowe: `R__10` sortuje się przed `R__2`. Należy zawsze
stosować format `R__01`, `R__02`, itd.

---

## 4. Pierwszy przebieg — świeża instancja

Wszystkie pięć projektów wykonywanych jako `ADMIN`, z parametrami inicjalizacji baseline:

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

- `migrate` nie wykonuje ponownie zastosowanych migracji `V` — pomija je na podstawie
  tabeli historii.
- Wykonywane są wyłącznie **nowe migracje `V`** oraz **migracje `R__` o zmienionej treści**.
- Modyfikacja zastosowanego pliku `V` powoduje niezgodność sumy kontrolnej i błąd.
  Procedurę naprawczą opisano w sekcji 7.

---

## 6. Weryfikacja po migracji

```sql
-- Czy użytkownicy zostali utworzeni?
SELECT username FROM dba_users
WHERE username IN ('DEV_APP','SILVER','GOLD','MAINTENANCE', 'STG');   -- oczekiwane 5 wiersze

-- Stan widziany przez Flyway (per projekt):
-- cmd /c C:\flyway\flyway.cmd "-configFiles=..." "-locations=..." info

-- Czy pakiety i widoki (repeatable) zostały wgrane?
SELECT object_type, object_name, status FROM dba_objects
WHERE owner IN ('SILVER','GOLD','MAINTENANCE')
  AND object_type IN ('PACKAGE','PACKAGE BODY','VIEW','TRIGGER','SYNONYM')
ORDER BY owner, object_type, object_name;
```

Komunikat `X SQL migrations detected but not run — did not follow the filename
convention` oznacza niepoprawne nazwy plików `R__` (sekcja 3). Należy poprawić nazwy
i ponowić `migrate`.

---

## 7. `repair` — naprawa tabeli historii

Polecenie `repair` nie wykonuje kodu SQL ani nie modyfikuje obiektów bazy. Operuje
wyłącznie na tabelach `flyway_schema_history_*`:

1. przelicza sumy kontrolne zastosowanych migracji `V` do zgodności z plikami (usuwa
   niezgodności),
2. usuwa wpisy nieudanych migracji.

```powershell
foreach ($p in "admin","stg","maintenance","silver","gold") {
  cmd /c C:\flyway\flyway.cmd `
    "-configFiles=migrations\$p\conf\flyway.conf" `
    "-locations=filesystem:migrations\$p\sql" repair
}
```

Przy niezgodności sum kontrolnych obowiązuje kolejność: **`repair` → `migrate`**.

`repair` jest narzędziem awaryjnym stosowanym w fazie deweloperskiej. Docelowo każda
zmiana struktury realizowana jest przez nowy plik `V`.

---

## 8. Reset instancji (wdrożenie od podstaw)

Procedura czyszczenia instancji w celu ponownego wdrożenia od zera (instancja bez danych):

```sql
-- 1) Zakończenie sesji użytkowników (w przeciwnym razie ORA-01940: user currently connected)
BEGIN
  FOR s IN (SELECT sid, serial# FROM v$session
            WHERE username IN ('DEV_APP','SILVER','GOLD','MAINTENANCE')) LOOP
    EXECUTE IMMEDIATE 'ALTER SYSTEM KILL SESSION '''||s.sid||','||s.serial#||''' IMMEDIATE';
  END LOOP;
END;
/

-- 2) Usunięcie użytkowników (CASCADE usuwa wszystkie obiekty i dane w schemacie)
DROP USER dev_app     CASCADE;
DROP USER silver      CASCADE;
DROP USER gold        CASCADE;
DROP USER maintenance CASCADE;
DROP USER stg         CASCADE;

-- 3) Usunięcie tabel historii Flyway
SELECT owner, table_name FROM dba_tables WHERE lower(table_name) LIKE 'flyway%';   -- weryfikacja
DROP TABLE admin."flyway_schema_history_admin"       PURGE;
DROP TABLE admin."flyway_schema_history_stg"         PURGE;
DROP TABLE admin."flyway_schema_history_maintenance" PURGE;
DROP TABLE admin."flyway_schema_history_silver"      PURGE;
DROP TABLE admin."flyway_schema_history_gold"        PURGE;
```

Po zresetowaniu należy wykonać pełny przebieg według sekcji 4.

---

## 9. Napotkane problemy i rozwiązania

| Objaw | Przyczyna | Rozwiązanie |
|---|---|---|
| `ERROR: Invalid flag: .conf` | PowerShell dzieli argument na kropce/dwukropku | Ująć `-configFiles=` i `-locations=` w cudzysłowy, wywoływać przez `cmd /c` |
| `Found non-empty schema(s) "ADMIN" but no schema history table` | Schemat ADMIN nigdy nie jest pusty | `-baselineOnMigrate=true -baselineVersion=0` |
| `Migration checksum mismatch for version 1` | Modyfikacja zastosowanego pliku `V` | `repair`, następnie `migrate` |
| `ORA-01940: cannot drop a user that is currently connected` | Otwarta sesja użytkownika (często własne połączenie na DEV_APP) | Zakończyć sesje z `v$session` (sekcja 8), zamknąć dodatkowe połączenie |
| `X SQL migrations detected but not run — did not follow the filename convention` | Niepoprawne nazwy plików repeatable (`R1__`, spacja) | Zmienić na `R__NN_opis.sql` (sekcja 3) |
| Wgrane tabele, brak pakietów/widoków | Migracje `R__` pominięte z powodu błędnej nazwy | Jak wyżej |

---

## 10. Zasady utrzymania (po wdrożeniu)

- Zmiana struktury — nowy plik `V`; modyfikacja zastosowanego pliku jest niedozwolona
  (powoduje niezgodność sumy kontrolnej i konieczność `repair`).
- Zmiana logiki (pakiet, widok) — modyfikacja pliku `R__`; Flyway wykona go automatycznie.
- `repair` stosowany wyłącznie awaryjnie.
