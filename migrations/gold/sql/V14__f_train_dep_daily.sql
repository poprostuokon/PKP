-- =============================================================================
-- gold.f_train_dep_daily
-- -----------------------------------------------------------------------------
-- Fakt GOLD: dzienna punktualnosc odjazdow z przystankow, w podziale na trase,
-- typ pociagu, stacje i godzine planowego odjazdu. Lustro f_train_stop_daily
-- (przyjazdy). Pomija stacje koncowa kursu (brak odjazdu). Miary obejmuja liczbe
-- odjazdow (na czas / spoznionych wg progow UTK), odwolane przystanki oraz sumy
-- i max opoznien. Zrodlo dla miesiecznego roll-upu. Partycjonowane po dacie.
-- =============================================================================

CREATE TABLE gold.f_train_dep_daily (
    -- ziarno (klucz zlozony)
    date_id                  NUMBER            NOT NULL,   -- YYYYMMDD -> d_date (klucz partycji)
    route_id                 NUMBER            NOT NULL,   -- -> d_route
    train_type_id            NUMBER            NOT NULL,   -- -> d_train_type (mapowanie po dacie, SCD2)
    station_id               NUMBER            NOT NULL,   -- -> d_station
    hour_id                  NUMBER(2)         NOT NULL,   -- -> d_hour (planowa godz. odjazdu)
    -- miary (odjazdy; progi UTK: on-time <=5, delayed >=6)
    departures_count         NUMBER            NOT NULL,   -- liczba zrealizowanych odjazdow
    departures_on_time       NUMBER            NOT NULL,   -- delay <= 5
    departures_delayed       NUMBER            NOT NULL,   -- delay >= 6
    sum_departure_delay_min  NUMBER,                       -- suma ze znakiem (wszystkie); NULL gdy brak odjazdow
    sum_delayed_delay_min    NUMBER,                       -- suma tylko spoznionych (>=6)
    max_departure_delay_min  NUMBER,                       -- max opoznienie w kombinacji
    cancelled_count          NUMBER            NOT NULL,   -- odwolane przystanki
    loaded_at                TIMESTAMP WITH TIME ZONE NOT NULL,
    CONSTRAINT pk_ftdepd  PRIMARY KEY (date_id, route_id, train_type_id, station_id, hour_id)
        USING INDEX LOCAL
)
PARTITION BY RANGE (date_id) INTERVAL (100)
( PARTITION p_init VALUES LESS THAN (20260101) )
STORAGE (INITIAL 64K)
;

grant select on gold.f_train_dep_daily to DEV_APP;