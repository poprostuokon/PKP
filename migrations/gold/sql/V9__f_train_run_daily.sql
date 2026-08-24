CREATE TABLE gold.f_train_run_daily (
    -- ziarno (klucz złożony)
    date_id                 NUMBER           NOT NULL,   -- YYYYMMDD -> d_date (klucz partycji)
    route_id                NUMBER           NOT NULL,   -- -> d_route
    train_type_id           NUMBER           NOT NULL,   -- -> d_train_type
    status_id               NUMBER           NOT NULL,   -- -> d_train_status
    -- miary (opóźnienie na stacji końcowej; progi UTK: on-time <=5, delayed >=6)
    runs_count              NUMBER           NOT NULL,   -- liczba kursów (dla "Odwołany" = liczba odwołanych)
    delayed_count           NUMBER,                      -- kursy z opóźnieniem końcowym >=6; NULL dla "Odwołany"
    sum_terminal_delay_min  NUMBER,                      -- suma opóźnień końcowych ze znakiem; NULL dla "Odwołany"
    sum_delayed_delay_min   NUMBER,                      -- suma tylko spóźnionych (>=6); NULL dla "Odwołany"
    max_terminal_delay_min  NUMBER,                      -- max opóźnienie; NULL dla "Odwołany"
    loaded_at               TIMESTAMP WITH TIME ZONE NOT NULL,
    CONSTRAINT pk_ftrd PRIMARY KEY (date_id, route_id, train_type_id, status_id)
        USING INDEX LOCAL
)
PARTITION BY RANGE (date_id) INTERVAL (100)
( PARTITION p_init VALUES LESS THAN (20260101) );