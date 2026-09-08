CREATE TABLE gold.f_train_disruption_monthly (
    -- ziarno (klucz zlozony)
    month              NUMBER(6)            NOT NULL,   -- YYYYMM (klucz partycji)
    route_id           NUMBER               NOT NULL,   -- -> d_route
    station_id         NUMBER               NOT NULL,   -- -> d_station
    train_type_id      NUMBER               NOT NULL,   -- -> d_train_type
    hour_id            NUMBER(2)            NOT NULL,   -- -> d_hour (planowa godz.)
    cause_id           NUMBER               NOT NULL,   -- -> d_disruption_cause
    day_type           CHAR(2)              NOT NULL,   -- 'WD' dni robocze / 'WE' weekend
    -- miara addytywna (roll-up z f_train_disruption_daily)
    occurrences_count  NUMBER               NOT NULL,   -- liczba wystapien (dotkniete przystanki)
    loaded_at          TIMESTAMP WITH TIME ZONE NOT NULL,
    CONSTRAINT pk_ftdm PRIMARY KEY (month, route_id, station_id, train_type_id, hour_id, cause_id, day_type)
        USING INDEX LOCAL,
    CONSTRAINT chk_ftdm_daytype CHECK (day_type IN ('WD','WE'))
)
PARTITION BY RANGE (month) INTERVAL (1)
( PARTITION p_init VALUES LESS THAN (202601) );

grant select on gold.f_train_disruption_monthly to DEV_APP;