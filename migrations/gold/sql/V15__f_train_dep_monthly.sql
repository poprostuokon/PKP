-- =============================================================================
-- gold.f_train_dep_monthly
-- -----------------------------------------------------------------------------
-- Fakt GOLD: miesieczna punktualnosc odjazdow z przystankow, w podziale na
-- trase, typ pociagu, stacje, godzine planowego odjazdu i typ dnia
-- (roboczy/weekend). Lustro f_train_stop_monthly (przyjazdy). Miary to roll-up
-- z f_train_dep_daily. Partycjonowane po miesiacu (YYYYMM).
-- =============================================================================

CREATE TABLE gold.f_train_dep_monthly (
    -- ziarno (klucz zlozony)
    month                    NUMBER(6)        NOT NULL,   -- YYYYMM (klucz partycji)
    route_id                 NUMBER           NOT NULL,   -- -> d_route
    train_type_id            NUMBER           NOT NULL,   -- -> d_train_type
    station_id               NUMBER           NOT NULL,   -- -> d_station
    hour_id                  NUMBER(2)        NOT NULL,   -- -> d_hour (planowa godz. odjazdu)
    day_type                 CHAR(2)          NOT NULL,   -- 'WD' dni robocze / 'WE' weekend
    -- miary addytywne (roll-up z f_train_dep_daily; SUM dla sum/licznikow, MAX dla max)
    departures_count         NUMBER           NOT NULL,
    departures_on_time       NUMBER           NOT NULL,   -- delay <= 5
    departures_delayed       NUMBER           NOT NULL,   -- delay >= 6
    sum_departure_delay_min  NUMBER,
    sum_delayed_delay_min    NUMBER,
    max_departure_delay_min  NUMBER,
    cancelled_count          NUMBER           NOT NULL,
    loaded_at                TIMESTAMP WITH TIME ZONE NOT NULL,
    CONSTRAINT pk_ftdepm  PRIMARY KEY (month, route_id, train_type_id, station_id, hour_id, day_type)
        USING INDEX LOCAL,
    CONSTRAINT chk_ftdepm_daytype  CHECK (day_type IN ('WD','WE'))
)
PARTITION BY RANGE (month) INTERVAL (1)
( PARTITION p_init VALUES LESS THAN (202601) )
STORAGE (INITIAL 64K)
;

grant select on gold.f_train_dep_monthly to DEV_APP;