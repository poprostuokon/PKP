CREATE TABLE gold.f_train_stop_daily (
    -- ziarno (klucz złożony)
    date_id                NUMBER            NOT NULL,   -- YYYYMMDD -> d_date (klucz partycji)
    route_id               NUMBER            NOT NULL,   -- -> d_route
    train_type_id          NUMBER            NOT NULL,   -- -> d_train_type (mapowanie po dacie, SCD2)
    station_id             NUMBER            NOT NULL,   -- -> d_station
    hour_id                NUMBER(2)         NOT NULL,   -- -> d_hour (planowa godz. przyjazdu; origin = odjazdu)
    stop_role              CHAR(1)           NOT NULL,   -- 'O' origin / 'M' pośredni / 'D' końcowy
    -- miary (przyjazdy; progi UTK: on-time <=5, delayed >=6)
    arrivals_count         NUMBER            NOT NULL,   -- liczba zrealizowanych przyjazdów
    arrivals_on_time       NUMBER            NOT NULL,   -- delay <= 5
    arrivals_delayed       NUMBER            NOT NULL,   -- delay >= 6
    sum_arrival_delay_min  NUMBER,                       -- suma ze znakiem (wszystkie); NULL gdy brak przyjazdów
    sum_delayed_delay_min  NUMBER,                       -- suma tylko spóźnionych (>=6)
    max_arrival_delay_min  NUMBER,                       -- max opóźnienie w kombinacji
    cancelled_count        NUMBER            NOT NULL,   -- odwołane przystanki
    loaded_at              TIMESTAMP WITH TIME ZONE NOT NULL,
    CONSTRAINT pk_ftsd PRIMARY KEY (date_id, route_id, train_type_id, station_id, hour_id, stop_role)
        USING INDEX LOCAL,
    CONSTRAINT chk_ftsd_role CHECK (stop_role IN ('O','M','D'))
)
PARTITION BY RANGE (date_id) INTERVAL (1)
( PARTITION p_init VALUES LESS THAN (20260101) );