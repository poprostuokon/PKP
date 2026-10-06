# Konwencje PL/SQL

Wzorce stosowane w pakietach ładujących (`pkg_silver_load`, `pkg_silver_load_live`, `pkg_gold_load`) i utrzymaniowych (`pkg_tool`, `pkg_maintenance`). Nazewnictwo obiektów: [naming_conventions.md](naming_conventions.md).

---

## 1. Dlaczego PL/SQL

Transformacje między warstwami są zapisane w pakietach PL/SQL, a nie w zewnętrznym narzędziu transformacji.

- **Logika przy danych.** Dane są w Oracle od stagingu do Gold. Transformacja to `INSERT … SELECT` albo `MERGE` wykonane w bazie, bez przesyłania wierszy do Pythona i z powrotem.
- **Transakcje.** Pakiet zamyka całą warstwę jednym `COMMIT` albo wycofuje ją w całości. To zachowanie jest w kodzie procedury, nie w konfiguracji narzędzia.
- **Natywny JSON.** `JSON_TABLE` rozbija dokument na wiersze w tym samym zapytaniu, które ładuje tabelę docelową.
- **Mniej elementów.** Do uruchomienia transformacji wystarcza połączenie z bazą i wywołanie procedury. Airflow i poller wywołują ten sam kod.

Python odpowiada za to, czego baza nie robi dobrze: pobranie danych z API, walidację plików, upload do Object Storage i orkiestrację.

---

## 2. Struktura pakietu

Jeden pakiet na warstwę i tor ładowania:

| Pakiet | Schemat | Zakres |
|---|---|---|
| `pkg_silver_load` | `silver` | `stg` → `silver`, tor dzienny |
| `pkg_silver_load_live` | `silver` | `stg` → `silver`, tor live |
| `pkg_gold_load` | `gold` | `silver` → `gold` |
| `pkg_maintenance` | `maintenance` | reorganizacja tabel i indeksów |
| `pkg_tool` | `maintenance` | funkcje wspólne |

Zasady:

- **Jedna procedura na tabelę.** `p_load_def_station` ładuje `def_station` i nic więcej. Każdą tabelę można przeładować osobno.
- **Procedura główna.** `p_load_all` (Silver), `p_load_dimensions`, `p_load_facts_daily`, `p_load_facts_monthly` (Gold) wywołują procedury tabel w ustalonej kolejności.
- **Wszystkie procedury są publiczne.** Specyfikacja pakietu wystawia zarówno procedury główne, jak i procedury pojedynczych tabel.

**Dlaczego procedury tabel są publiczne:** przy diagnozowaniu problemu albo poprawce jednej tabeli nie trzeba uruchamiać całej warstwy.

---

## 3. Transakcje

`COMMIT` i `ROLLBACK` są wyłącznie w procedurze głównej:

```sql
PROCEDURE p_load_all IS
BEGIN
    EXECUTE IMMEDIATE 'ALTER SESSION DISABLE PARALLEL DML';
    p_load_def_carrier;
    ...
    p_load_disruption_details;
    COMMIT;
EXCEPTION
    WHEN OTHERS THEN
        ROLLBACK;
        DBMS_OUTPUT.PUT_LINE('=== SILVER load ERROR - ROLLBACK: ' || SQLERRM);
        RAISE;
END p_load_all;
```

- Procedury tabel nie zatwierdzają transakcji.
- Błąd wycofuje całą warstwę i jest przekazywany dalej (`RAISE`), żeby task w Airflow zakończył się błędem.
- `ALTER SESSION DISABLE PARALLEL DML` na początku: na Autonomous Database równoległy DML blokuje odczyt zmienionej tabeli w tej samej transakcji (ORA-12839), a kolejne procedury czytają to, co załadowały poprzednie.

**Dlaczego `COMMIT` tylko na górze:** nagłówki i pozycje muszą trafić do bazy razem. Procedura, która sama zatwierdza, nie nadaje się do złożenia w większą transakcję.

Wyjątek: `pkg_maintenance.p_run_compress_queue` zatwierdza po każdym poleceniu, bo wykonuje DDL (które i tak zatwierdza niejawnie) i loguje wynik każdego polecenia osobno.

---

## 4. Wzorce ładowania

### Słowniki i wymiary — `MERGE` z pominięciem wierszy bez zmian

```sql
MERGE INTO def_carrier d
USING ( ... ) s
ON (d.code = s.code AND d.valid_from = s.valid_from)
WHEN MATCHED THEN UPDATE SET d.name = s.name, d.valid_to = s.valid_to,
                             d.loaded_at = pkg_tool.f_now_warsaw
    WHERE DECODE(d.name, s.name, 0, 1) = 1
       OR DECODE(d.valid_to, s.valid_to, 0, 1) = 1
WHEN NOT MATCHED THEN INSERT ...
```

Klauzula `WHERE` w gałęzi `UPDATE` przepuszcza tylko wiersze, w których coś się faktycznie zmieniło. `DECODE(a, b, 0, 1)` traktuje dwa `NULL` jako równe, czego zwykłe `a <> b` nie robi.

**Dlaczego:** bez tego warunku każde ładowanie aktualizowałoby wszystkie wiersze słownika. `loaded_at` przestałby mówić, kiedy wiersz się zmienił, a triggery audytowe i redo pracowałyby na pustych zmianach.

### Dane operacyjne — tylko nowe wiersze

```sql
INSERT INTO schedule_header (...)
SELECT ...
FROM   land_schedules src, json_table(src.payload, '$' ...) j
WHERE  NOT EXISTS (select 1 from schedule_header t where <klucz naturalny>)
QUALIFY row_number() over (partition by <klucz naturalny> order by 1) = 1;
```

- `NOT EXISTS` po kluczu naturalnym pomija to, co już jest w tabeli.
- `QUALIFY` usuwa duplikaty wewnątrz samej paczki (ten sam kurs w dwóch plikach).

W `schedule_header` dodatkowo aktualizowana jest flaga `is_active`: plan, który zniknął z okna dat obecnego w paczce, zostaje oznaczony jako nieaktualny. Aktualizacja dotyka tylko wierszy, w których flaga faktycznie się zmienia.

**Dlaczego bez `UPDATE` danych:** raz zapisany kurs się nie zmienia; zmiana planu przychodzi z API jako nowy `order_id`, czyli nowy wiersz. Ponowne uruchomienie na tej samej paczce nie wstawia niczego.

### Tracking live — `change_hash`

`operation_tracking_log` dostaje nową wersję tylko wtedy, gdy hash pól śledzonych różni się od ostatniej wersji. `disruption_tracking_log` działa w modelu SCD2: poprzednia wersja dostaje `is_active = FALSE`, nowa jest wstawiana, a utrudnienia zakończone są zamykane.

### Fakty Gold — okno `DELETE` + `INSERT`

```sql
v_from := TRUNC(SYSDATE) - p_days;
v_to   := TRUNC(SYSDATE) - 1;
DELETE FROM f_train_run_daily WHERE date_id BETWEEN <v_from> AND <v_to>;
INSERT INTO f_train_run_daily ...
```

Fakty miesięczne rozszerzają okno do pełnych miesięcy i przeliczają je w całości z faktów dziennych.

**Dlaczego `DELETE` + `INSERT`, a nie `MERGE`:** kombinacja wymiarów, która po korekcie danych przestała istnieć, musi zniknąć z faktu. `MERGE` zaktualizuje i doda wiersze, ale nie usunie tych, których już nie ma w źródle.

### Podsumowanie

| Typ tabeli | Wzorzec | Idempotentność |
|---|---|---|
| słownik, wymiar | `MERGE` + `DECODE` | ponowne uruchomienie nie zmienia żadnego wiersza |
| wymiar generowany | `INSERT … WHERE NOT EXISTS` | dopisuje tylko brakujące daty i godziny |
| dane operacyjne | `INSERT … WHERE NOT EXISTS` + `QUALIFY` | klucz naturalny |
| tracking live | porównanie `change_hash` | wersja bez zmian nie jest zapisywana |
| fakt | `DELETE` okna + `INSERT` | okno jest przeliczane od zera |

---

## 5. Parsowanie JSON

Dokument z kolumny `payload` jest rozbijany przez `JSON_TABLE` bezpośrednio w zapytaniu ładującym:

```sql
FROM land_carriers l,
     json_table(l.payload, '$.carriers[*]'
         columns (
             code       varchar2(4000 char) path '$.code',
             valid_from timestamp           path '$.validFrom'
         )) jt
```

- Tablice zagnieżdżone: `NESTED PATH` (kurs → daty kursowania, kurs → przystanki).
- Kolumny tekstowe są deklarowane szeroko (`varchar2(4000 char)`), a zawężenie typu następuje przy wstawianiu do tabeli docelowej. Za długa wartość daje wtedy błąd przy `INSERT`, a nie ciche obcięcie w `JSON_TABLE`.
- Obiekt o dynamicznych kluczach (`{"k1": "v1", "k2": "v2"}`) jest najpierw zamieniany na tablicę par przez `pkg_tool.f_json_obj_to_kv`, bo `JSON_TABLE` iteruje po tablicach, nie po kluczach obiektu.

---

## 6. Czas

| Zasada | Realizacja |
|---|---|
| znaczniki ładowania w czasie polskim | `pkg_tool.f_now_warsaw` zamiast `SYSTIMESTAMP` |
| czas źródła bez zmian | `snapshot_ts` = `generatedAt` z API, w UTC |
| kolumny czasu ze strefą | `TIMESTAMP WITH TIME ZONE` |

**Dlaczego funkcja zamiast `SYSTIMESTAMP`:** Autonomous Database pracuje w UTC. Jedna funkcja daje ten sam czas lokalny we wszystkich pakietach i triggerach, niezależnie od ustawień sesji klienta.

---

## 7. Uprawnienia i synonimy

- **`AUTHID DEFINER`** w pakietach ładujących. Pakiet działa z uprawnieniami schematu-właściciela; konto `dev_app` potrzebuje tylko `EXECUTE` na pakiecie.
- **`AUTHID CURRENT_USER`** w `pkg_maintenance`. Pakiet wykonuje DDL na obiektach innych schematów, więc korzysta z uprawnień konta wywołującego.
- **Synonimy zamiast prefiksów schematów.** Kod pakietu odwołuje się do `land_schedules` i `pkg_tool`, a nie do `stg.land_schedules` i `maintenance.pkg_tool`. Synonimy i granty są tworzone na początku pliku migracji pakietu.
- **Grant na końcu pliku.** `GRANT EXECUTE … TO dev_app` jest ostatnim poleceniem migracji pakietu.

**Dlaczego granty w pliku pakietu:** migracja powtarzalna jest kompletna. Odtworzenie pakietu na czystej bazie nie zależy od osobnego skryptu z uprawnieniami.

**Dlaczego synonimy:** kod procedur nie zawiera nazw schematów, więc zmiana układu schematów oznacza zmianę synonimów, a nie treści pakietu.

---

## 8. Logowanie

Każda procedura tabeli kończy się wywołaniem `p_log_rows(SQL%ROWCOUNT)`. Procedura odczytuje nazwę procedury wywołującej ze stosu wywołań i wypisuje ją z liczbą wierszy:

```sql
v_full := UTL_CALL_STACK.concatenate_subprogram(UTL_CALL_STACK.subprogram(2));
v_step := LOWER(SUBSTR(v_full, INSTR(v_full, '.') + 1));
DBMS_OUTPUT.PUT_LINE(RPAD(v_step, 32) || ' -> ' || p_rows || ' wierszy');
```

Task w Airflow włącza `DBMS_OUTPUT`, po wywołaniu procedury odczytuje bufor i wypisuje go do logu tasku.

**Dlaczego nazwa ze stosu wywołań:** nazwa kroku w logu nie może się rozjechać z nazwą procedury, bo nikt jej nie wpisuje ręcznie.

**Dlaczego `DBMS_OUTPUT`, a nie tabela logów:** status i czas kroku zapisuje audyt w `maintenance.pipeline_run_step`. Liczby wierszy są szczegółem jednego przebiegu i wystarcza, że są w logu tasku.

---

## 9. Audyt słowników

Każdy słownik `def_*` ma trigger `AFTER UPDATE OF <kolumny>`, który zapisuje do `audit_tbl_def` jeden wiersz na każdą faktycznie zmienioną kolumnę:

```sql
SELECT 'DEF_CARRIER', 'code=' || :OLD.code || ';valid_from=' || ..., col, oldv, newv,
       pkg_tool.f_now_warsaw, USER
FROM ( SELECT 'NAME' AS col, :OLD.name AS oldv, :NEW.name AS newv FROM dual
       UNION ALL ... )
WHERE DECODE(oldv, newv, 0, 1) = 1;
```

Trigger reaguje tylko na kolumny, które `MERGE` może zmienić, i używa tego samego porównania `DECODE` co ładowanie.

---

## 10. Widoki raportowe

- **Surowe dane i reguły.** Widok `v_rep_*` zwraca liczniki, sumy i flagi wynikające z reguł biznesowych. Formatowanie i prezentacja należą do aplikacji.
- **Procenty i średnie przy odczycie.** Widok liczy je z miar addytywnych; nie są składowane w faktach.
- **Reguły w jednym miejscu.** Próg punktualności i sposób rozpoznania kursu odwołanego są zapisane w ładowaniu faktu, a widoki z nich korzystają.
- **Filtrowanie po kluczach.** Widoki z `CROSS APPLY` należy filtrować po kolumnach, które zawężają podzapytanie; pozostałe warunki nakładać po pobraniu wyniku.

---

## 11. Nagłówek pliku

Każda migracja zaczyna się blokiem komentarza: nazwa obiektu, co zawiera, ziarno i klucz, zasady ładowania.

```sql
-- =============================================================================
-- silver.schedule_details
-- -----------------------------------------------------------------------------
-- Warstwa SILVER: pozycje rozkładu jazdy - jeden wiersz na przystanek kursu.
-- ...
-- =============================================================================
```

Komentarz przy kolumnie opisuje znaczenie biznesowe albo pochodzenie wartości (`-- → silver.def_station.id`, `-- generatedAt (UTC)`), a nie typ.
