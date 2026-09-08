CREATE TABLE gold.f_train_stop_monthly (
    -- ziarno (klucz zlozony)
    month                   NUMBER(6)        NOT NULL,   -- YYYYMM (klucz partycji)
    route_id                NUMBER           NOT NULL,   -- -> d_route
    train_type_id           NUMBER           NOT NULL,   -- -> d_train_type
    station_id              NUMBER           NOT NULL,   -- -> d_station
    hour_id                 NUMBER(2)        NOT NULL,   -- -> d_hour (planowa godz. przyjazdu)
    day_type                CHAR(2)          NOT NULL,   -- 'WD' dni robocze / 'WE' weekend
    -- miary addytywne (roll-up z f_train_stop_daily; SUM dla sum/licznikow, MAX dla max)
    arrivals_count          NUMBER           NOT NULL,   -- liczba zrealizowanych przyjazdow
    arrivals_on_time        NUMBER           NOT NULL,   -- delay <= 5
    arrivals_delayed        NUMBER           NOT NULL,   -- delay >= 6
    sum_arrival_delay_min   NUMBER,                      -- suma ze znakiem (wszystkie); NULL gdy brak przyjazdow
    sum_delayed_delay_min   NUMBER,                      -- suma tylko spoznionych (>=6)
    max_arrival_delay_min   NUMBER,                      -- max opoznienie w kombinacji
    cancelled_count         NUMBER           NOT NULL,   -- odwolane przystanki
    loaded_at               TIMESTAMP WITH TIME ZONE NOT NULL,
    CONSTRAINT pk_ftsm PRIMARY KEY (month, route_id, train_type_id, station_id, hour_id, day_type)
        USING INDEX LOCAL,
    CONSTRAINT chk_ftsm_daytype CHECK (day_type IN ('WD','WE'))
)
PARTITION BY RANGE (month) INTERVAL (1)
( PARTITION p_init VALUES LESS THAN (202601) );

grant select on gold.f_train_stop_monthly to DEV_APP;