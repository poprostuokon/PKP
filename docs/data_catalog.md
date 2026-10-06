# Katalog danych

Katalog obiektów bazodanowych w podziale na schematy. Dla każdego schematu: lista obiektów, a pod nią kolumny tabel.

| Schemat | Rola | Tabele | Widoki | Pakiety |
|---|---|---|---|---|
| `stg` | landing surowych JSON z bucketu | 12 | — | — |
| `silver` | model relacyjny, dane operacyjne i tracking live | 16 | 11 | 2 |
| `gold` | Star Schema pod analizy | 15 | 13 | 1 |
| `maintenance` | audyt, monitoring, utrzymanie | 6 | — | 2 |

Schematy są kontami bez logowania (`NO AUTHENTICATION`). Kod aplikacyjny łączy się jako `dev_app` i odwołuje się do obiektów przez synonimy. Warstwa Bronze nie ma schematu w bazie — to pliki w OCI Object Storage.

Opisy kolumn pochodzą z komentarzy w migracjach Flyway (`migrations/<schemat>/sql/V*.sql`).

---

## 1. Schemat `stg`

Tabele landing: jeden wiersz = jeden plik JSON z bucketu. Każda tabela jest czyszczona i ładowana wyłącznie nowymi plikami w każdym przebiegu.

| Tabela | Zawartość | Tor |
|---|---|---|
| `land_schedules` | rozkład jazdy | DAILY |
| `land_operations` | wykonanie kursów | DAILY |
| `land_disruptions` | utrudnienia | DAILY |
| `land_operations_live` | delty wykonania kursów | LIVE |
| `land_disruptions_live` | delty utrudnień | LIVE |
| `land_cities` | słownik miast | DAILY |
| `land_stations` | słownik stacji | DAILY |
| `land_carriers` | słownik przewoźników | DAILY |
| `land_train_statuses` | słownik statusów kursu | DAILY |
| `land_stop_types` | słownik typów postoju | DAILY |
| `land_commercial_categories` | słownik kategorii handlowych | DAILY |
| `land_disruption_types` | słownik przyczyn utrudnień | DAILY |

Wszystkie 12 tabel ma identyczną strukturę:

| Kolumna | Typ | NULL | Opis |
|---|---|---|---|
| `payload` | JSON | tak | surowy dokument JSON |
| `loaded_at` | TIMESTAMP TZ | nie | kiedy wgrano do landing |

---

## 2. Schemat `silver`

### Tabele

| Tabela | Ziarno | Klucz główny | Ładowanie |
|---|---|---|---|
| `def_city` | miasto | `id` | `MERGE` |
| `def_station` | stacja | `id` (z API) | `MERGE` |
| `def_carrier` | wersja przewoźnika | `code`, `valid_from` | `MERGE`, SCD2 |
| `def_train_status` | status kursu | `code` | `MERGE` |
| `def_stop_type` | typ postoju | `id` | `MERGE` |
| `def_commercial_category` | kategoria u przewoźnika | `code`, `carrier_code` | `MERGE` |
| `def_disruption_cause` | przyczyna utrudnienia | `code` | `MERGE` |
| `schedule_header` | kurs w dniu kursowania | `id` | insert-only-new |
| `schedule_details` | przystanek planu | `schedule_id`, `order_id`, `order_number` | insert-only-new |
| `operation_header` | wykonany kurs w dniu | `id` | insert-only-new |
| `operation_details` | przystanek wykonanego kursu | `ophe_id`, `actual_sequence` | insert-only-new |
| `disruption_header` | utrudnienie | `id` | insert-only-new |
| `disruption_details` | przystanek dotknięty utrudnieniem | `operating_date`, `schedule_id`, `order_id`, `dsta_id`, `dihe_id` | insert-only-new |
| `operation_tracking_log` | wersja stanu kursu na stacji (live) | `operating_date`, `id` | append-only wg `change_hash` |
| `disruption_tracking_log` | wersja utrudnienia kursu (live) | `operating_date`, `id` | SCD2 wg `change_hash` |
| `audit_tbl_def` | zmiana jednej kolumny w słowniku | `audit_id` | triggery |

Tabele `*_tracking_log` są partycjonowane po `operating_date` (`RANGE`, `INTERVAL` 1 miesiąc), z kluczem głównym na indeksie `LOCAL`.

### Widoki

| Widok | Ziarno | Opis |
|---|---|---|
| `v_live_departures_wroclaw_gl` | kurs | najbliższe odjazdy z Wrocławia Głównego (od -5 min do +8 h): najnowsza wersja z logu tracking + rozkład + aktywne utrudnienia |
| `v_live_arrivals_wroclaw_gl` | kurs | najbliższe przyjazdy, analogicznie |
| `v_rep_rozklad_wro` | kurs × stacja za Wrocławiem | połączenia bezpośrednie z Wrocławia Głównego, od dziś |
| `v_rep_trasa_wro` | kurs × przystanek | przebieg trasy od Wrocławia do stacji końcowej |
| `v_rep_wykonane_kurs` | kurs | zakończone kursy D-1 … D-7 przez Wrocław: plan i wykonanie |
| `v_rep_wykonane_trasa` | kurs × postój | przebieg zakończonych kursów na całej trasie, z opóźnieniami i utrudnieniami |
| `v_rep_wykonane_utrudnienia` | utrudnienie w kursie | widok pomocniczy dla `v_rep_wykonane_trasa` |
| `v_rep_stacja_wro` | kurs | postoje na Wrocławiu Głównym D-7 … D-1: plan, wykonanie, rola stacji |
| `v_rep_utrudnienia_wro` | kurs × przyczyna | utrudnienia kursów na Wrocławiu Głównym D-1 … D-7 |
| `v_rep_trasa_stacje_miesiac` | trasa × kategoria × stacja | kolejność stacji z planu wzorcowego trasy w miesiącu |
| `v_rep_trasa_start_miesiac` | trasa × kategoria × przewoźnik | opóźnienie odjazdu ze stacji początkowej w miesiącu |

Widoki `v_rep_*` zwracają surowe dane i reguły biznesowe; formatowanie należy do warstwy prezentacji.

Pakiet `pkg_silver_load` odświeża też dwa widoki zmaterializowane, `mv_rep_stacja_wro` i `mv_rep_utrudnienia_wro`. Ich definicje nie są częścią migracji w repozytorium.

### Pakiety i triggery

| Obiekt | Opis |
|---|---|
| `pkg_silver_load` | ładowanie dzienne `stg` → `silver`; procedura główna `p_load_all` (jedna transakcja) i po jednej procedurze `p_load_<tabela>` na tabelę |
| `pkg_silver_load_live` | ładowanie live: `p_load_operation_tracking`, `p_load_disruption_tracking`, procedura główna `p_load_all_live` |
| `trg_def_*_audit` (7) | `AFTER UPDATE` na słownikach `def_*`; zapisują do `audit_tbl_def` jeden wiersz na każdą faktycznie zmienioną kolumnę |

### Kolumny tabel

#### `silver.def_city`

| Kolumna | Typ | NULL | Opis |
|---|---|---|---|
| `id` | NUMBER (IDENTITY) | nie | lokalne ID |
| `name` | VARCHAR2(200) | nie | nazwa |
| `station_count` | NUMBER | tak | z API, kontrola spójności |
| `is_active` | BOOLEAN | nie | czy wiersz jest aktualny |
| `loaded_at` | TIMESTAMP TZ | nie | czas załadowania (Europe/Warsaw) |

#### `silver.def_station`

| Kolumna | Typ | NULL | Opis |
|---|---|---|---|
| `id` | NUMBER | nie | klucz naturalny z API |
| `name` | VARCHAR2(200) | nie | nazwa |
| `dcit_id` | NUMBER | tak | → silver.def_city.id |
| `is_active` | BOOLEAN | nie | false gdy zniknie z API |
| `first_seen_at` | TIMESTAMP TZ | nie | pierwsze pojawienie się w danych |
| `loaded_at` | TIMESTAMP TZ | nie | czas załadowania (Europe/Warsaw) |

#### `silver.def_carrier`

| Kolumna | Typ | NULL | Opis |
|---|---|---|---|
| `code` | VARCHAR2(20) | nie | klucz naturalny (KD, IC, AR...) |
| `name` | VARCHAR2(200) | nie | nazwa |
| `valid_from` | DATE | nie | z API |
| `valid_to` | DATE | nie | z API (2999-12-31 = otwarty) |
| `loaded_at` | TIMESTAMP TZ | nie | czas załadowania (Europe/Warsaw) |

#### `silver.def_train_status`

| Kolumna | Typ | NULL | Opis |
|---|---|---|---|
| `code` | VARCHAR2(20) | nie | klucz naturalny (S, P, X...) |
| `name` | VARCHAR2(200) | nie | nazwa |
| `loaded_at` | TIMESTAMP TZ | nie | czas załadowania (Europe/Warsaw) |

#### `silver.def_stop_type`

| Kolumna | Typ | NULL | Opis |
|---|---|---|---|
| `id` | NUMBER | nie | z API (1, 2, ...) |
| `description` | VARCHAR2(500) | nie | "tylko dla wsiadających" |
| `loaded_at` | TIMESTAMP TZ | nie | czas załadowania (Europe/Warsaw) |

#### `silver.def_commercial_category`

| Kolumna | Typ | NULL | Opis |
|---|---|---|---|
| `code` | VARCHAR2(20) | nie | Os, IC, EC, EIC... |
| `name` | VARCHAR2(200) | tak | nazwa |
| `carrier_code` | VARCHAR2(20) | nie | kod przewoźnika |
| `speed_category_code` | VARCHAR2(20) | tak | kod kategorii prędkości |
| `loaded_at` | TIMESTAMP TZ | nie | czas załadowania (Europe/Warsaw) |

#### `silver.def_disruption_cause`

| Kolumna | Typ | NULL | Opis |
|---|---|---|---|
| `code` | VARCHAR2(20) | nie | utr_01 ... utr_75 (disruptionTypeCode) |
| `description` | VARCHAR2(500) | nie | "Awaria sieci trakcyjnej" |
| `loaded_at` | TIMESTAMP TZ | nie | czas załadowania (Europe/Warsaw) |

#### `silver.schedule_header`

| Kolumna | Typ | NULL | Opis |
|---|---|---|---|
| `id` | NUMBER (IDENTITY) | nie | klucz sztuczny |
| `schedule_id` | NUMBER | nie | edycja rozkładu (2026) |
| `order_id` | NUMBER | nie | wersja planu |
| `train_order_id` | NUMBER | nie | tożsamość kursu (stabilna) |
| `operating_date` | DATE | nie | dzień kursowania (lokalny) |
| `name` | VARCHAR2(200) | tak | często NULL |
| `carrier_code` | VARCHAR2(20) | nie | → silver.def_carrier.code (bez FK, SCD2) |
| `category_code` | VARCHAR2(20) | nie | → silver.def_commercial_category (bez FK) |
| `national_number` | VARCHAR2(50) | nie | oryginał, bywa "262/65002" |
| `intl_arrival_number` | VARCHAR2(50) | tak | numer międzynarodowy (przyjazd) |
| `intl_departure_number` | VARCHAR2(50) | tak | numer międzynarodowy (odjazd) |
| `snapshot_ts` | TIMESTAMP TZ | nie | generatedAt (UTC) |
| `loaded_at` | TIMESTAMP TZ | nie | czas załadowania (Europe/Warsaw) |
| `is_active` | NUMBER(1) | nie | czy wiersz jest aktualny |

#### `silver.schedule_details`

| Kolumna | Typ | NULL | Opis |
|---|---|---|---|
| `schedule_id` | NUMBER | nie | edycja rozkladu (np. 2026) |
| `order_id` | NUMBER | nie | wersja tresci planu |
| `order_number` | NUMBER | nie | MOŻE być ujemny (zagranica) |
| `dsta_id` | NUMBER | nie | → silver.def_station.id |
| `arrival_time` | VARCHAR2(8) | tak | planowa godzina przyjazdu (HH24:MI:SS) |
| `arrival_day` | NUMBER | tak | offset dnia (0,1) — przez północ |
| `arrival_at` | TIMESTAMP TZ | tak | wyliczane -> UTC |
| `arrival_platform` | VARCHAR2(10) | tak | peron przyjazdu |
| `arrival_track` | VARCHAR2(10) | tak | tor przyjazdu |
| `arrival_category` | VARCHAR2(20) | tak | → silver.def_commercial_category |
| `arrival_train_no` | VARCHAR2(50) | tak | bywa "262/65002" |
| `departure_time` | VARCHAR2(8) | tak | planowa godzina odjazdu (HH24:MI:SS) |
| `departure_day` | NUMBER | tak | offset dnia odjazdu (0, 1) |
| `departure_at` | TIMESTAMP TZ | tak | wyliczane |
| `departure_platform` | VARCHAR2(10) | tak | peron odjazdu |
| `departure_track` | VARCHAR2(10) | tak | tor odjazdu |
| `departure_category` | VARCHAR2(20) | tak | kategoria handlowa przy odjeździe |
| `departure_train_no` | VARCHAR2(50) | tak | numer pociągu przy odjeździe |
| `dstty_id` | NUMBER | tak | → silver.def_stop_type.id |

#### `silver.operation_header`

| Kolumna | Typ | NULL | Opis |
|---|---|---|---|
| `id` | NUMBER (IDENTITY) | nie | klucz sztuczny |
| `schedule_id` | NUMBER | nie | edycja rozkładu |
| `order_id` | NUMBER | nie | wersja planu |
| `train_order_id` | NUMBER | nie | tożsamość kursu (stabilna) |
| `operating_date` | DATE | nie | dzień kursowania |
| `train_status` | VARCHAR2(10) | nie | S/N/P/C/F/X → def_train_status.code (bez FK) |
| `snapshot_ts` | TIMESTAMP TZ | nie | generatedAt (UTC) |
| `loaded_at` | TIMESTAMP TZ | nie | czas załadowania (Europe/Warsaw) |

#### `silver.operation_details`

| Kolumna | Typ | NULL | Opis |
|---|---|---|---|
| `ophe_id` | NUMBER | nie | → operation_header.id |
| `planned_sequence` | NUMBER | nie | plannedSequenceNumber |
| `actual_sequence` | NUMBER | nie | kolejność rzeczywista na trasie |
| `dsta_id` | NUMBER | nie | → silver.def_station.id |
| `actual_arrival` | TIMESTAMP TZ | tak | rzeczywisty przyjazd |
| `actual_departure` | TIMESTAMP TZ | tak | rzeczywisty odjazd |
| `is_confirmed` | BOOLEAN | nie | cf: potwierdzone przejechanie |
| `is_cancelled` | BOOLEAN | nie | cn: przystanek odwołany |
| `arrival_delay_min` | NUMBER | tak | actual_arrival − plan |
| `departure_delay_min` | NUMBER | tak | actual_departure − plan |
| `dwell_time_sec` | NUMBER | tak | actual_departure − actual_arrival |

#### `silver.disruption_header`

| Kolumna | Typ | NULL | Opis |
|---|---|---|---|
| `id` | NUMBER (IDENTITY) | nie | klucz sztuczny |
| `disruption_type_code` | VARCHAR2(20) | tak | → silver.def_disruption_cause.code (disruptionTypeCode) bez FK bo może być null (tylko message) |
| `message` | VARCHAR2(1000) | tak | może być null |
| `snapshot_ts` | TIMESTAMP TZ | nie | generatedAt (UTC) |
| `loaded_at` | TIMESTAMP TZ | nie | czas załadowania (Europe/Warsaw) |

#### `silver.disruption_details`

| Kolumna | Typ | NULL | Opis |
|---|---|---|---|
| `schedule_id` | NUMBER | nie | edycja rozkładu |
| `order_id` | NUMBER | nie | wersja planu |
| `train_order_id` | NUMBER | tak | tożsamość kursu (stabilna) |
| `operating_date` | DATE | nie | dzień kursowania |
| `sequence_number` | NUMBER | nie | kolejność przystanku w kursie |
| `dsta_id` | NUMBER | nie | → silver.def_station.id |
| `dihe_id` | NUMBER | nie | → silver.disruption_header.id |
| `loaded_at` | TIMESTAMP TZ | nie | czas załadowania (Europe/Warsaw) |

#### `silver.operation_tracking_log`

| Kolumna | Typ | NULL | Opis |
|---|---|---|---|
| `id` | NUMBER (IDENTITY) | nie | klucz sztuczny |
| `schedule_id` | NUMBER | nie | edycja rozkładu |
| `order_id` | NUMBER | nie | wersja planu |
| `train_order_id` | NUMBER | nie | tożsamość kursu (stabilna) |
| `operating_date` | DATE | nie | dzień kursowania |
| `dsta_id` | NUMBER | nie | → silver.def_station.id (zrobić sprawdzenie i dodać  stacje do słownika gdy nie znajdzie id stacji) |
| `train_status` | VARCHAR2(10) | nie | S/N/P/C/F/X → def_train_status.code (bez FK) |
| `actual_arrival` | TIMESTAMP TZ | tak | rzeczywisty przyjazd |
| `actual_departure` | TIMESTAMP TZ | tak | rzeczywisty odjazd |
| `arrival_delay_min` | NUMBER | tak | opóźnienie przyjazdu [min] |
| `departure_delay_min` | NUMBER | tak | opóźnienie odjazdu [min] |
| `is_confirmed` | BOOLEAN | nie | przejazd potwierdzony |
| `is_cancelled` | BOOLEAN | nie | przystanek odwołany |
| `change_hash` | CHAR(64) | nie | hash pól śledzonych |
| `snapshot_ts` | TIMESTAMP TZ | nie | generatedAt (event time) |
| `ingested_at` | TIMESTAMP TZ | nie | kiedy zapisano (processing time) |

#### `silver.disruption_tracking_log`

| Kolumna | Typ | NULL | Opis |
|---|---|---|---|
| `id` | NUMBER (IDENTITY) | nie | klucz sztuczny |
| `schedule_id` | NUMBER | nie | edycja rozkładu |
| `order_id` | NUMBER | nie | wersja planu |
| `train_order_id` | NUMBER | tak | tożsamość kursu (stabilna) |
| `operating_date` | DATE | nie | dzień kursowania |
| `dsta_id` | NUMBER | nie | → silver.def_station.id (zrobić sprawdzenie i dodać  stacje do słownika gdy nie znajdzie id stacji) |
| `sequence_number` | NUMBER | nie | kolejność przystanku w kursie |
| `disruption_type_code` | VARCHAR2(20) | tak | → silver.def_disruption_cause.code (disruptionTypeCode) bez FK bo może być null (tylko message) |
| `message` | VARCHAR2(1000) | tak | może być null |
| `change_hash` | CHAR(64) | nie | hash pól śledzonych |
| `is_active` | BOOLEAN | nie | czy wiersz jest aktualny |
| `snapshot_ts` | TIMESTAMP TZ | nie | generatedAt z API (UTC) |
| `loaded_at` | TIMESTAMP TZ | nie | czas załadowania (Europe/Warsaw) |

#### `silver.audit_tbl_def`

| Kolumna | Typ | NULL | Opis |
|---|---|---|---|
| `audit_id` | NUMBER (IDENTITY) | nie | klucz sztuczny |
| `table_name` | VARCHAR2(30) | nie | nazwa tabeli słownika |
| `business_key` | VARCHAR2(400) | nie | klucz biznesowy rekordu |
| `column_name` | VARCHAR2(128) | nie | zmieniona kolumna |
| `old_value` | VARCHAR2(4000) | tak | wartość przed zmianą |
| `new_value` | VARCHAR2(4000) | tak | wartość po zmianie |
| `changed_at` | TIMESTAMP TZ | nie | czas zmiany |
| `changed_by` | VARCHAR2(128) | tak | użytkownik bazy |

---

## 3. Schemat `gold`

### Wymiary

| Tabela | Ziarno | Klucz główny | Ładowanie |
|---|---|---|---|
| `d_date` | dzień | `id` (YYYYMMDD) | generowany, idempotentny `INSERT` |
| `d_hour` | godzina doby | `id` (0–23) | generowany, idempotentny `INSERT` |
| `d_station` | stacja | `id` (z API) | `MERGE` |
| `d_route` | relacja: stacja początkowa → końcowa | `id` | `MERGE` |
| `d_train_type` | kategoria × wersja przewoźnika | `id` | `MERGE`, SCD2 |
| `d_train_status` | status kursu | `id` | `MERGE` |
| `d_disruption_cause` | przyczyna utrudnienia | `id` | `MERGE` |

### Fakty

| Tabela | Ziarno | Partycje |
|---|---|---|
| `f_train_run_daily` | dzień × trasa × typ pociągu × status | `RANGE (date_id) INTERVAL (100)` |
| `f_train_stop_daily` | dzień × trasa × typ pociągu × stacja × godzina | jw. |
| `f_train_dep_daily` | dzień × trasa × typ pociągu × stacja × godzina | jw. |
| `f_train_disruption_daily` | dzień × trasa × stacja × typ pociągu × godzina × przyczyna | jw. |
| `f_train_run_monthly` | miesiąc × trasa × typ pociągu × status × typ dnia | `RANGE (month) INTERVAL (1)` |
| `f_train_stop_monthly` | miesiąc × trasa × typ pociągu × stacja × godzina × typ dnia | jw. |
| `f_train_dep_monthly` | miesiąc × trasa × typ pociągu × stacja × godzina × typ dnia | jw. |
| `f_train_disruption_monthly` | miesiąc × trasa × stacja × typ pociągu × godzina × przyczyna × typ dnia | jw. |

Klucz główny każdego faktu to jego ziarno, na indeksie `LOCAL`. Oba schematy partycjonowania dają jedną partycję na miesiąc. Fakty dzienne są ładowane przez `DELETE` okna + `INSERT`, miesięczne są roll-upem z dziennych.

Progi punktualności (UTK): na czas do 5 min, opóźniony od 6 min. `day_type`: `WD` = dni robocze, `WE` = weekend.

### Widoki

| Widok | Ziarno | Opis |
|---|---|---|
| `v_rep_punctuality_monthly` | miesiąc × trasa × typ pociągu | punktualność i ranking tras; kursy odwołane liczone osobno |
| `v_rep_punctuality_by_daytype_monthly` | miesiąc × trasa × typ pociągu × typ dnia | jw. w rozbiciu na dni robocze i weekendy |
| `v_rep_status_share_monthly` | miesiąc × trasa × typ pociągu × status | udział statusów kursów |
| `v_rep_stop_hourly_monthly` | miesiąc × trasa × stacja × godzina × typ pociągu | punktualność przyjazdów wg godziny i stacji |
| `v_rep_disruption_causes_monthly` | miesiąc × trasa × stacja × typ pociągu × przyczyna | ranking przyczyn utrudnień |
| `v_rep_run_route` | kurs × przystanek | profil opóźnienia pojedynczego kursu wzdłuż trasy |
| `v_rep_wro_godz_monthly` | miesiąc × kierunek × godzina | punktualność przyjazdów i odjazdów na Wrocławiu Głównym wg godziny |
| `v_rep_wro_dzien_tyg_monthly` | miesiąc × kierunek × dzień tygodnia | jw. wg dnia tygodnia |
| `v_rep_wro_kierunki_monthly` | miesiąc × kierunek × stacja | skąd przyjeżdżają i dokąd odjeżdżają pociągi |
| `v_rep_wro_utrudnienia_monthly` | miesiąc × dzień tygodnia × przyczyna | utrudnienia na Wrocławiu Głównym |
| `v_run_daily_trace` | kurs | diagnostyka `f_train_run_daily`: kursy z policzonymi kluczami Gold |
| `v_stop_daily_trace` | przystanek | diagnostyka `f_train_stop_daily` |
| `v_disruption_daily_trace` | dotknięty przystanek | diagnostyka `f_train_disruption_daily` |

Widoki raportowe trzymają surowe liczniki i sumy; procenty i średnie są liczone przy odczycie, żeby dało się je poprawnie agregować dalej. Widoki `*_trace` odwracają mapowanie z ładowania faktu: pokazują, które wiersze Silver złożyły się na daną komórkę faktu i które zostały odrzucone (`in_fact = 'N'`).

### Pakiety

| Obiekt | Opis |
|---|---|
| `pkg_gold_load` | `p_load_dimensions`, `p_load_facts_daily(p_days)`, `p_load_facts_monthly(p_days)` oraz po jednej procedurze na tabelę; `p_days` = szerokość przeliczanego okna (domyślnie 3) |

### Kolumny tabel

#### `gold.d_date`

| Kolumna | Typ | NULL | Opis |
|---|---|---|---|
| `id` | NUMBER | nie | klucz naturalny YYYYMMDD (np. 20260820) |
| `full_date` | DATE | nie | data |
| `year` | NUMBER(4) | nie | rok |
| `quarter` | NUMBER(1) | nie | 1-4 |
| `month` | NUMBER(2) | nie | 1-12 |
| `month_name` | VARCHAR2(20) | nie | "sierpień" |
| `day` | NUMBER(2) | nie | dzień miesiąca |
| `day_of_week` | NUMBER(1) | nie | 1=pon ... 7=niedz (ISO) |
| `day_name` | VARCHAR2(20) | nie | "środa" |
| `iso_week` | NUMBER(2) | nie | tydzień ISO |
| `is_weekend` | CHAR(1) | nie | 'T'/'N' |
| `loaded_at` | TIMESTAMP TZ | nie | czas załadowania (Europe/Warsaw) |

#### `gold.d_hour`

| Kolumna | Typ | NULL | Opis |
|---|---|---|---|
| `id` | NUMBER(2) | nie | 0-23 |
| `hour_label` | VARCHAR2(20) | nie | "17:00-17:59" |
| `part_of_day` | VARCHAR2(30) | nie | noc / szczyt poranny / dzień / szczyt popołudniowy / wieczór |
| `loaded_at` | TIMESTAMP TZ | nie | czas załadowania (Europe/Warsaw) |

#### `gold.d_station`

| Kolumna | Typ | NULL | Opis |
|---|---|---|---|
| `id` | NUMBER | nie | klucz naturalny z API (= silver.def_station.id) |
| `station_name` | VARCHAR2(200) | nie | nazwa stacji |
| `city_name` | VARCHAR2(200) | tak | NULL gdy stacja bez powiązania z miastem (LEFT JOIN) |
| `loaded_at` | TIMESTAMP TZ | nie | czas załadowania (Europe/Warsaw) |

#### `gold.d_route`

| Kolumna | Typ | NULL | Opis |
|---|---|---|---|
| `id` | NUMBER (IDENTITY) | nie | klucz sztuczny |
| `from_station_id` | NUMBER | nie | stacja początkowa (min order_number) -> d_station |
| `to_station_id` | NUMBER | nie | stacja końcowa (max order_number)  -> d_station |
| `loaded_at` | TIMESTAMP TZ | nie | czas załadowania (Europe/Warsaw) |

#### `gold.d_train_type`

| Kolumna | Typ | NULL | Opis |
|---|---|---|---|
| `id` | NUMBER (IDENTITY) | nie | klucz sztuczny |
| `category_code` | VARCHAR2(20) | nie | EN, EIC, Os... |
| `category_name` | VARCHAR2(200) | tak | "EuroNight" |
| `speed_category_code` | VARCHAR2(20) | tak | kod kategorii prędkości |
| `carrier_code` | VARCHAR2(20) | nie | kod przewoźnika |
| `carrier_name` | VARCHAR2(200) | nie | "PKP Intercity" |
| `valid_from` | DATE | nie | początek obowiązywania wersji |
| `valid_to` | DATE | nie | 2999-12-31 = wersja bieżąca |
| `loaded_at` | TIMESTAMP TZ | nie | czas załadowania (Europe/Warsaw) |

#### `gold.d_train_status`

| Kolumna | Typ | NULL | Opis |
|---|---|---|---|
| `id` | NUMBER (IDENTITY) | nie | klucz sztuczny |
| `status_code` | VARCHAR2(20) | nie | S, P, C, X... (= silver.def_train_status.code) |
| `status_name` | VARCHAR2(200) | nie | nazwa statusu |
| `loaded_at` | TIMESTAMP TZ | nie | czas załadowania (Europe/Warsaw) |

#### `gold.d_disruption_cause`

| Kolumna | Typ | NULL | Opis |
|---|---|---|---|
| `id` | NUMBER (IDENTITY) | nie | klucz sztuczny |
| `cause_code` | VARCHAR2(20) | nie | utr_XX (= silver.def_disruption_cause.code) |
| `cause_name` | VARCHAR2(400) | nie | "Ograniczenie prędkości pociągu" |
| `loaded_at` | TIMESTAMP TZ | nie | czas załadowania (Europe/Warsaw) |

#### `gold.f_train_run_daily`

| Kolumna | Typ | NULL | Opis |
|---|---|---|---|
| `date_id` | NUMBER | nie | YYYYMMDD -> d_date (klucz partycji) |
| `route_id` | NUMBER | nie | -> d_route |
| `train_type_id` | NUMBER | nie | -> d_train_type |
| `status_id` | NUMBER | nie | -> d_train_status |
| `runs_count` | NUMBER | nie | liczba kursów (dla "Odwołany" = liczba odwołanych) |
| `delayed_count` | NUMBER | tak | kursy z opóźnieniem końcowym >=6; NULL dla "Odwołany" |
| `sum_terminal_delay_min` | NUMBER | tak | suma opóźnień końcowych ze znakiem; NULL dla "Odwołany" |
| `sum_delayed_delay_min` | NUMBER | tak | suma tylko spóźnionych (>=6); NULL dla "Odwołany" |
| `max_terminal_delay_min` | NUMBER | tak | max opóźnienie; NULL dla "Odwołany" |
| `travel_runs_count` | NUMBER | tak | kursy ukonczone z policzalnym czasem (origin+terminal NOT NULL) = mianownik srednich |
| `sum_planned_travel_min` | NUMBER | tak | suma planowanych czasow przejazdu [min]; avg = /travel_runs_count |
| `sum_actual_travel_min` | NUMBER | tak | suma rzeczywistych czasow przejazdu [min]; avg = /travel_runs_count |
| `min_actual_travel_min` | NUMBER | tak | najszybszy rzeczywisty przejazd [min] |
| `max_actual_travel_min` | NUMBER | tak | najdluzszy rzeczywisty przejazd [min] |
| `loaded_at` | TIMESTAMP TZ | nie | czas załadowania (Europe/Warsaw) |

#### `gold.f_train_stop_daily`

| Kolumna | Typ | NULL | Opis |
|---|---|---|---|
| `date_id` | NUMBER | nie | YYYYMMDD -> d_date (klucz partycji) |
| `route_id` | NUMBER | nie | -> d_route |
| `train_type_id` | NUMBER | nie | -> d_train_type (mapowanie po dacie, SCD2) |
| `station_id` | NUMBER | nie | -> d_station |
| `hour_id` | NUMBER(2) | nie | -> d_hour (planowa godz. przyjazdu; origin = odjazdu) |
| `arrivals_count` | NUMBER | nie | liczba zrealizowanych przyjazdów |
| `arrivals_on_time` | NUMBER | nie | delay <= 5 |
| `arrivals_delayed` | NUMBER | nie | delay >= 6 |
| `sum_arrival_delay_min` | NUMBER | tak | suma ze znakiem (wszystkie); NULL gdy brak przyjazdów |
| `sum_delayed_delay_min` | NUMBER | tak | suma tylko spóźnionych (>=6) |
| `max_arrival_delay_min` | NUMBER | tak | max opóźnienie w kombinacji |
| `cancelled_count` | NUMBER | nie | odwołane przystanki |
| `loaded_at` | TIMESTAMP TZ | nie | czas załadowania (Europe/Warsaw) |

#### `gold.f_train_dep_daily`

| Kolumna | Typ | NULL | Opis |
|---|---|---|---|
| `date_id` | NUMBER | nie | YYYYMMDD -> d_date (klucz partycji) |
| `route_id` | NUMBER | nie | -> d_route |
| `train_type_id` | NUMBER | nie | -> d_train_type (mapowanie po dacie, SCD2) |
| `station_id` | NUMBER | nie | -> d_station |
| `hour_id` | NUMBER(2) | nie | -> d_hour (planowa godz. odjazdu) |
| `departures_count` | NUMBER | nie | liczba zrealizowanych odjazdow |
| `departures_on_time` | NUMBER | nie | delay <= 5 |
| `departures_delayed` | NUMBER | nie | delay >= 6 |
| `sum_departure_delay_min` | NUMBER | tak | suma ze znakiem (wszystkie); NULL gdy brak odjazdow |
| `sum_delayed_delay_min` | NUMBER | tak | suma tylko spoznionych (>=6) |
| `max_departure_delay_min` | NUMBER | tak | max opoznienie w kombinacji |
| `cancelled_count` | NUMBER | nie | odwolane przystanki |
| `loaded_at` | TIMESTAMP TZ | nie | czas załadowania (Europe/Warsaw) |

#### `gold.f_train_disruption_daily`

| Kolumna | Typ | NULL | Opis |
|---|---|---|---|
| `date_id` | NUMBER | nie | YYYYMMDD -> d_date (klucz partycji) |
| `route_id` | NUMBER | nie | -> d_route |
| `station_id` | NUMBER | nie | -> d_station |
| `train_type_id` | NUMBER | nie | -> d_train_type |
| `hour_id` | NUMBER(2) | nie | -> d_hour (planowa godz.; origin = odjazdu) |
| `cause_id` | NUMBER | nie | -> d_disruption_cause |
| `occurrences_count` | NUMBER | nie | liczba wystąpień (dotknięte przystanki) |
| `runs_count` | NUMBER | nie | liczba kursów z utrudnieniem |
| `runs_total_count` | NUMBER | nie | liczba wszystkich kursów w kombinacji |
| `loaded_at` | TIMESTAMP TZ | nie | czas załadowania (Europe/Warsaw) |

#### `gold.f_train_run_monthly`

| Kolumna | Typ | NULL | Opis |
|---|---|---|---|
| `month` | NUMBER(6) | nie | YYYYMM (klucz partycji) |
| `route_id` | NUMBER | nie | -> d_route |
| `train_type_id` | NUMBER | nie | -> d_train_type |
| `status_id` | NUMBER | nie | -> d_train_status |
| `day_type` | CHAR(2) | nie | 'WD' dni robocze / 'WE' weekend |
| `runs_count` | NUMBER | nie | liczba kursow |
| `delayed_count` | NUMBER | tak | kursy z opoznieniem koncowym >=6; NULL dla "Odwolany" |
| `sum_terminal_delay_min` | NUMBER | tak | suma opoznien koncowych; NULL dla "Odwolany" |
| `sum_delayed_delay_min` | NUMBER | tak | suma tylko spoznionych (>=6); NULL dla "Odwolany" |
| `max_terminal_delay_min` | NUMBER | tak | max opoznienie; NULL dla "Odwolany" |
| `travel_runs_count` | NUMBER | tak | SUM(daily) - kursy ukonczone z policzalnym czasem = mianownik srednich |
| `sum_planned_travel_min` | NUMBER | tak | SUM(daily) planowanych czasow przejazdu [min] |
| `sum_actual_travel_min` | NUMBER | tak | SUM(daily) rzeczywistych czasow przejazdu [min] |
| `min_actual_travel_min` | NUMBER | tak | MIN(daily) najszybszy rzeczywisty przejazd [min] |
| `max_actual_travel_min` | NUMBER | tak | MAX(daily) najdluzszy rzeczywisty przejazd [min] |
| `loaded_at` | TIMESTAMP TZ | nie | czas załadowania (Europe/Warsaw) |

#### `gold.f_train_stop_monthly`

| Kolumna | Typ | NULL | Opis |
|---|---|---|---|
| `month` | NUMBER(6) | nie | YYYYMM (klucz partycji) |
| `route_id` | NUMBER | nie | -> d_route |
| `train_type_id` | NUMBER | nie | -> d_train_type |
| `station_id` | NUMBER | nie | -> d_station |
| `hour_id` | NUMBER(2) | nie | -> d_hour (planowa godz. przyjazdu) |
| `day_type` | CHAR(2) | nie | 'WD' dni robocze / 'WE' weekend |
| `arrivals_count` | NUMBER | nie | liczba zrealizowanych przyjazdow |
| `arrivals_on_time` | NUMBER | nie | delay <= 5 |
| `arrivals_delayed` | NUMBER | nie | delay >= 6 |
| `sum_arrival_delay_min` | NUMBER | tak | suma ze znakiem (wszystkie); NULL gdy brak przyjazdow |
| `sum_delayed_delay_min` | NUMBER | tak | suma tylko spoznionych (>=6) |
| `max_arrival_delay_min` | NUMBER | tak | max opoznienie w kombinacji |
| `cancelled_count` | NUMBER | nie | odwolane przystanki |
| `loaded_at` | TIMESTAMP TZ | nie | czas załadowania (Europe/Warsaw) |

#### `gold.f_train_dep_monthly`

| Kolumna | Typ | NULL | Opis |
|---|---|---|---|
| `month` | NUMBER(6) | nie | YYYYMM (klucz partycji) |
| `route_id` | NUMBER | nie | -> d_route |
| `train_type_id` | NUMBER | nie | -> d_train_type |
| `station_id` | NUMBER | nie | -> d_station |
| `hour_id` | NUMBER(2) | nie | -> d_hour (planowa godz. odjazdu) |
| `day_type` | CHAR(2) | nie | 'WD' dni robocze / 'WE' weekend |
| `departures_count` | NUMBER | nie | liczba zrealizowanych odjazdów |
| `departures_on_time` | NUMBER | nie | delay <= 5 |
| `departures_delayed` | NUMBER | nie | delay >= 6 |
| `sum_departure_delay_min` | NUMBER | tak | suma opóźnień odjazdów [min] |
| `sum_delayed_delay_min` | NUMBER | tak | suma opóźnień tylko spóźnionych |
| `max_departure_delay_min` | NUMBER | tak | największe opóźnienie odjazdu |
| `cancelled_count` | NUMBER | nie | odwołane przystanki |
| `loaded_at` | TIMESTAMP TZ | nie | czas załadowania (Europe/Warsaw) |

#### `gold.f_train_disruption_monthly`

| Kolumna | Typ | NULL | Opis |
|---|---|---|---|
| `month` | NUMBER(6) | nie | YYYYMM (klucz partycji) |
| `route_id` | NUMBER | nie | -> d_route |
| `station_id` | NUMBER | nie | -> d_station |
| `train_type_id` | NUMBER | nie | -> d_train_type |
| `hour_id` | NUMBER(2) | nie | -> d_hour (planowa godz.) |
| `cause_id` | NUMBER | nie | -> d_disruption_cause |
| `day_type` | CHAR(2) | nie | 'WD' dni robocze / 'WE' weekend |
| `occurrences_count` | NUMBER | nie | liczba wystapien (dotkniete przystanki) |
| `runs_count` | NUMBER | nie | liczba kursów z utrudnieniem |
| `runs_total_count` | NUMBER | nie | liczba wszystkich kursów w kombinacji |
| `loaded_at` | TIMESTAMP TZ | nie | czas załadowania (Europe/Warsaw) |

---

## 4. Schemat `maintenance`

### Tabele

| Tabela | Ziarno | Klucz główny | Zapisuje |
|---|---|---|---|
| `pipeline_run` | przebieg DAG-a `pkp_daily` | `id` | `set_run_date`, `finalize_*` |
| `pipeline_run_step` | task w przebiegu | `id` | callbacki Airflow |
| `stg_load_log` | plik z bucketu | `object_name` | `prepare_stg`, `prepare_stg_live` |
| `poller_heartbeat` | cykl pollera × feed | `run_ts`, `feed` | `live_poller` |
| `sql_exec_queue` | polecenie DDL do wykonania | — | `pkg_maintenance` |
| `sql_exec_queue_log` | wykonane polecenie DDL | `id` | `pkg_maintenance` |

### Pakiety

| Obiekt | Opis |
|---|---|
| `pkg_tool` | funkcje narzędziowe: `f_now_warsaw` (bieżący czas w strefie Europe/Warsaw), `f_json_obj_to_kv` (obiekt JSON → tablica par klucz–wartość dla `JSON_TABLE`) |
| `pkg_maintenance` | `p_gen_table_move_schema`, `p_gen_index_rebuild_schema`, `p_gen_compress_schema` generują polecenia do kolejki; `p_run_compress_queue` wykonuje kolejkę i loguje wynik; `p_clear_queue` czyści kolejkę |

### Kolumny tabel

#### `maintenance.pipeline_run`

| Kolumna | Typ | NULL | Opis |
|---|---|---|---|
| `id` | NUMBER (IDENTITY) | nie | klucz sztuczny |
| `run_date` | DATE | nie | data logiczna runu (z set_run_date) |
| `dag_run_id` | VARCHAR2(250) | nie | run_id z Airflow (scheduled__... / manual__...) |
| `start_time` | TIMESTAMP TZ | nie | start |
| `end_time` | TIMESTAMP TZ | tak | uzupełniane przy domknięciu runu |
| `status` | VARCHAR2(20) | nie | status |
| `created_at` | TIMESTAMP TZ | nie | czas utworzenia wiersza |

#### `maintenance.pipeline_run_step`

| Kolumna | Typ | NULL | Opis |
|---|---|---|---|
| `id` | NUMBER (IDENTITY) | nie | klucz sztuczny |
| `pipeline_run_id` | NUMBER | nie | → pipeline_run.id |
| `step_name` | VARCHAR2(200) | nie | task_id z Airflow |
| `start_time` | TIMESTAMP TZ | nie | start |
| `end_time` | TIMESTAMP TZ | tak | koniec |
| `status` | VARCHAR2(20) | nie | status |
| `error_details` | CLOB | tak | pełny stack trace / opis błędu |
| `created_at` | TIMESTAMP TZ | nie | czas utworzenia wiersza |

#### `maintenance.stg_load_log`

| Kolumna | Typ | NULL | Opis |
|---|---|---|---|
| `object_name` | VARCHAR2(1024) | nie | pelna sciezka w buckecie (klucz) |
| `feed` | VARCHAR2(30) | nie | schedules/operations/disruptions/dict:<name> |
| `load_mode` | VARCHAR2(30) | nie | DAILY / LIVE |
| `part_date` | DATE | nie | data partycji (z sciezki date=YYYYMMDD) |
| `status` | VARCHAR2(10) | nie | LOADED / FAILED |
| `bytes` | NUMBER | tak | rozmiar pliku |
| `err_msg` | VARCHAR2(4000) | tak | komunikat błędu |
| `loaded_at` | TIMESTAMP TZ | nie | czas załadowania (Europe/Warsaw) |

#### `maintenance.poller_heartbeat`

| Kolumna | Typ | NULL | Opis |
|---|---|---|---|
| `run_ts` | TIMESTAMP | nie | start ticku (processing time) = klucz idempotencji |
| `feed` | VARCHAR2(30) | nie | operations / disruptions |
| `outcome` | VARCHAR2(10) | nie | OK / EMPTY / STALE / ERR |
| `delta_count` | NUMBER | tak | rekordow w delcie (0 dla EMPTY) |
| `generated_at` | TIMESTAMP TZ | tak | generatedAt przetworzonego snapshotu; NULL gdy fetch padl |
| `lag_seconds` | NUMBER | tak | now - generatedAt w chwili przetwarzania |
| `cycle_ms` | NUMBER | tak | czas trwania cyklu feedu |
| `err_msg` | VARCHAR2(4000) | tak | tresc bledu dla ERR |
| `created_at` | TIMESTAMP TZ | nie | kiedy realnie zapisano do DB (moze != run_ts gdy ze spoola) |

#### `maintenance.sql_exec_queue`

| Kolumna | Typ | NULL | Opis |
|---|---|---|---|
| `sql_` | CLOB | nie | gotowy ALTER ... MOVE ... COMPRESS |

#### `maintenance.sql_exec_queue_log`

| Kolumna | Typ | NULL | Opis |
|---|---|---|---|
| `id` | NUMBER (IDENTITY) | nie | klucz sztuczny |
| `executed_at` | TIMESTAMP TZ | nie | czas wykonania |
| `sql_` | CLOB | nie | SQL wykonany (kopiowalny do kolejki) |
| `status` | VARCHAR2(10) | nie | DONE / FAILED |
| `error_msg` | VARCHAR2(4000) | tak | SQLERRM gdy FAILED, NULL gdy DONE |
