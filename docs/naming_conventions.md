# Konwencje nazewnicze

Nazwy obiektów bazodanowych, migracji Flyway oraz plików i ścieżek w pipeline. Wszystkie nazwy techniczne są po angielsku, małymi literami, w `snake_case`.

---

## 1. Schematy

| Schemat | Zawartość |
|---|---|
| `stg` | landing surowych JSON |
| `silver` | model relacyjny |
| `gold` | Star Schema |
| `maintenance` | audyt, monitoring, utrzymanie |

Nazwa schematu jest nazwą warstwy. Schematy są kontami bez logowania; aplikacja łączy się jako `dev_app`.

---

## 2. Tabele

| Schemat | Wzorzec | Przykład | Znaczenie |
|---|---|---|---|
| `stg` | `land_<feed>` | `land_schedules` | landing jednego feedu z API |
| `stg` | `land_<feed>_live` | `land_operations_live` | landing delty z toru live |
| `silver` | `def_<nazwa>` | `def_station` | słownik |
| `silver` | `<obszar>_header` | `operation_header` | nagłówek: jeden wiersz na kurs lub utrudnienie |
| `silver` | `<obszar>_details` | `operation_details` | pozycje: jeden wiersz na przystanek |
| `silver` | `<obszar>_tracking_log` | `operation_tracking_log` | historia zmian z toru live |
| `gold` | `d_<nazwa>` | `d_route` | wymiar |
| `gold` | `f_<obszar>_daily` | `f_train_run_daily` | fakt o ziarnie dnia |
| `gold` | `f_<obszar>_monthly` | `f_train_run_monthly` | fakt o ziarnie miesiąca |

Nazwy tabel są w liczbie pojedynczej (`def_station`, nie `def_stations`). Wyjątkiem są tabele `land_*`, które przejmują nazwę feedu z API (`land_stations`).

**Dlaczego prefiksy:** typ obiektu widać w nazwie bez zaglądania do definicji. `d_` i `f_` od razu mówią, co jest wymiarem, a co faktem, a `def_` odróżnia słownik od danych operacyjnych.

---

## 3. Kolumny

| Wzorzec | Przykład | Znaczenie |
|---|---|---|
| `id` | `def_station.id` | klucz główny jednokolumnowy |
| `<skrót_tabeli>_id` | `dsta_id`, `ophe_id` | klucz obcy w Silver (skrót tabeli wskazywanej) |
| `<wymiar>_id` | `route_id`, `station_id` | klucz wymiaru w fakcie Gold (nazwa wymiaru bez `d_`) |
| `code` | `def_train_status.code` | klucz naturalny tekstowy z API |
| `is_<cecha>` | `is_active`, `is_cancelled` | flaga |
| `<zdarzenie>_at` | `loaded_at`, `arrival_at` | znacznik czasu |
| `<zdarzenie>_ts` | `snapshot_ts`, `run_ts` | znacznik czasu pochodzący ze źródła lub z przebiegu |
| `valid_from`, `valid_to` | `def_carrier` | okres obowiązywania wersji (SCD2) |
| `<miara>_count` | `runs_count` | licznik |
| `sum_<miara>`, `min_<miara>`, `max_<miara>` | `sum_arrival_delay_min` | miara zagregowana |
| `<miara>_min`, `<miara>_sec`, `<miara>_ms` | `arrival_delay_min`, `dwell_time_sec` | jednostka w nazwie |

Kolumny techniczne obecne w większości tabel:

| Kolumna | Znaczenie |
|---|---|
| `loaded_at` | czas załadowania wiersza (strefa Europe/Warsaw) |
| `snapshot_ts` | `generatedAt` z odpowiedzi API (UTC) |
| `change_hash` | SHA-256 pól śledzonych, do wykrywania zmian |

**Dlaczego jednostka w nazwie:** `arrival_delay_min` nie wymaga sprawdzania, czy opóźnienie jest w minutach, czy w sekundach.

### Skróty tabel

Klucze obce i nazwy constraintów w Silver używają czteroliterowego skrótu tabeli: dwie pierwsze litery każdego z dwóch członów nazwy. Dla słowników pierwszym znakiem jest `d` (od `def_`).

| Tabela | Skrót |
|---|---|
| `def_city` | `dcit` |
| `def_station` | `dsta` |
| `def_stop_type` | `dstty` |
| `def_carrier` | `dcar` |
| `def_commercial_category` | `dcoca` |
| `def_train_status` | `dtrst` |
| `def_disruption_cause` | `ddica` |
| `schedule_header` | `sche` |
| `schedule_details` | `scde` |
| `operation_header` | `ophe` |
| `operation_details` | `opde` |
| `disruption_header` | `dihe` |
| `disruption_details` | `dide` |

**Dlaczego skróty:** nazwa constraintu z pełnymi nazwami tabel i kolumn przekraczałaby czytelną długość. Skrót jest stały dla tabeli, więc `fk_opde_ophe_id` czyta się jednoznacznie: klucz obcy z `operation_details` do `operation_header`.

---

## 4. Constrainty i indeksy

| Typ | Wzorzec | Przykład |
|---|---|---|
| klucz główny | `pk_<skrót>[_<kolumny>]` | `pk_dsta_id`, `pk_dcar_co_vafr` |
| klucz obcy | `fk_<skrót>_<kolumna>` | `fk_dsta_dcit_id` |
| unikalność | `uq_<skrót>_<kolumny>` | `uq_dcit_name` |
| check | `chk_<skrót>_<reguła>` | `chk_ddate_weekend` |
| indeks | `idx_<tabela>_<kolumny>` | `idx_run_step_status` |

Przy kluczach wielokolumnowych kolumny są skracane do dwóch liter każdego członu: `valid_from` → `vafr`, `operating_date` → `opda`.

---

## 5. Widoki

| Wzorzec | Przykład | Znaczenie |
|---|---|---|
| `v_live_<co>_<stacja>` | `v_live_departures_wroclaw_gl` | dane bieżące z toru live |
| `v_rep_<temat>` | `v_rep_punctuality_monthly` | widok raportowy |
| `v_rep_<temat>_monthly` | `v_rep_stop_hourly_monthly` | widok raportowy o ziarnie miesiąca |
| `v_<fakt>_trace` | `v_run_daily_trace` | diagnostyka faktu Gold |
| `mv_rep_<temat>` | `mv_rep_stacja_wro` | widok zmaterializowany |

---

## 6. PL/SQL

| Obiekt | Wzorzec | Przykład |
|---|---|---|
| pakiet ładujący | `pkg_<warstwa>_load[_live]` | `pkg_silver_load`, `pkg_silver_load_live` |
| pakiet narzędziowy | `pkg_<rola>` | `pkg_tool`, `pkg_maintenance` |
| procedura | `p_<czynność>_<obiekt>` | `p_load_def_station`, `p_gen_index_rebuild_schema` |
| procedura główna | `p_load_all`, `p_load_<grupa>` | `p_load_all`, `p_load_facts_daily` |
| funkcja | `f_<co_zwraca>` | `f_now_warsaw` |
| parametr | `p_<nazwa>` | `p_days`, `p_schema` |
| zmienna lokalna | `v_<nazwa>` | `v_from`, `v_cnt` |
| stała | `c_<nazwa>` | `c_default_days` |
| trigger | `trg_<tabela>_<cel>` | `trg_def_city_audit` |

Procedura ładująca nosi nazwę tabeli, którą zasila: `p_load_schedule_header` ładuje `schedule_header`.

Szczegóły wzorców ładowania: [plsql_conventions.md](plsql_conventions.md).

---

## 7. Migracje Flyway

Pięć niezależnych projektów, po jednym na schemat:

```
migrations/<schemat>/
├── conf/flyway.conf
└── sql/
    ├── V<n>__<obiekt>.sql        migracja wersjonowana
    └── R__<nn>_<obiekt>.sql      migracja powtarzalna
```

| Typ | Wzorzec | Zawartość | Przykład |
|---|---|---|---|
| wersjonowana | `V<n>__<tabela>.sql` | struktura: tabele, constrainty, indeksy | `V9__schedule_details.sql` |
| powtarzalna | `R__<nn>_<obiekt>.sql` | kod: pakiety, widoki, triggery, synonimy | `R__01_pkg_gold_load.sql` |

- Jedna migracja wersjonowana tworzy jedną tabelę.
- Numer `<nn>` w migracji powtarzalnej ustala kolejność wykonania (Flyway sortuje je po opisie); `R__99_*` wykonuje się na końcu.
- Tabela historii: `flyway_schema_history_<schemat>`, osobna dla każdego projektu.

**Dlaczego V i R osobno:** struktura tabeli ma historię zmian, których nie można powtórzyć. Kod pakietu i widoku nie ma stanu — `CREATE OR REPLACE` zawsze daje ten sam wynik, więc Flyway wykonuje plik ponownie przy każdej zmianie jego treści. Nie trzeba tworzyć nowego pliku na każdą poprawkę procedury.

**Dlaczego osobny projekt na schemat:** każdą warstwę można wdrożyć i zweryfikować niezależnie, a historia migracji jednej warstwy nie blokuje pozostałych.

---

## 8. Pliki JSON

| Rodzaj | Wzorzec | Przykład |
|---|---|---|
| słownik | `dict_<nazwa>_<run_ts>.json` | `dict_stations_20261006060012.json` |
| dane dzienne | `<feed>_<data>_<run_ts>.json` | `schedules_20261006_20261006060015.json` |
| dane ze stronicowaniem | `<feed>_<data>_<run_ts>_p<NNN>.json` | `operations_20261006_20261006060020_p001.json` |
| stan pollera | `state_<feed>.json` | `state_operations.json` |
| plik odrzucony | `<nazwa>_<run_ts>.bad.json` + `.err.txt` | — |

`run_ts` to znacznik przebiegu w formacie `YYYYMMDDHH24MISS`. Jest w każdej nazwie pliku i z niego pochodzi data partycji.

**Dlaczego `run_ts` w nazwie:** plik identyfikuje się sam — wiadomo, z którego przebiegu pochodzi, bez osobnego rejestru. Dwa przebiegi tego samego dnia nie nadpisują sobie plików.

---

## 9. Ścieżki w buckecie

```
<tor>/<kategoria>/<feed>/date=<YYYYMMDD>/<plik>
```

| Człon | Wartości |
|---|---|
| `<tor>` | `daily`, `live` |
| `<kategoria>` | `data`, `dict` |
| `<feed>` | `schedules`, `operations`, `disruptions` albo nazwa słownika |
| `date=` | data pobrania (pierwsze 8 cyfr `run_ts`) |

Przykład: `daily/data/operations/date=20261006/operations_20261006_20261006060020_p001.json`

**Dlaczego `date=`:** to konwencja partycjonowania w stylu Hive. Ładowanie do stagingu listuje jeden prefiks dnia zamiast całego bucketu, a format jest zrozumiały dla narzędzi analitycznych czytających bezpośrednio z Object Storage.

---

## 10. Airflow i Docker

| Obiekt | Wzorzec | Przykład |
|---|---|---|
| DAG | `pkp_<częstotliwość>` | `pkp_daily` |
| task | nazwa czynności lub feedu | `silver_load`, `schedules` |
| funkcja tasku | `t_<task>` | `t_silver` |
| zmienna środowiskowa | `PKP_<NAZWA>` | `PKP_ENV`, `PKP_OCI_BUCKET` |
| usługa Docker Compose | `<rola>-<środowisko>` | `poller-dev` |
