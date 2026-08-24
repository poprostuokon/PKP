CREATE TABLE gold.f_train_disruption_daily (
    -- ziarno (klucz złożony)
    date_id            NUMBER               NOT NULL,   -- YYYYMMDD -> d_date (klucz partycji)
    route_id           NUMBER               NOT NULL,   -- -> d_route
    station_id         NUMBER               NOT NULL,   -- -> d_station
    train_type_id      NUMBER               NOT NULL,   -- -> d_train_type
    hour_id            NUMBER(2)            NOT NULL,   -- -> d_hour (planowa godz.; origin = odjazdu)
    cause_id           NUMBER               NOT NULL,   -- -> d_disruption_cause
    -- miara
    occurrences_count  NUMBER               NOT NULL,   -- liczba wystąpień (dotknięte przystanki)
    loaded_at          TIMESTAMP WITH TIME ZONE NOT NULL,
    CONSTRAINT pk_ftdd PRIMARY KEY (date_id, route_id, station_id, train_type_id, hour_id, cause_id)
        USING INDEX LOCAL
)
PARTITION BY RANGE (date_id) INTERVAL (1)
( PARTITION p_init VALUES LESS THAN (20260101) );