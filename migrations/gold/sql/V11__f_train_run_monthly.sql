CREATE TABLE gold.F_TRAIN_RUN_MONTHLY (
    -- ziarno (klucz zlozony)
    month                   NUMBER(6)        NOT NULL,   -- YYYYMM (klucz partycji)
    route_id                NUMBER           NOT NULL,   -- -> d_route
    train_type_id           NUMBER           NOT NULL,   -- -> d_train_type
    status_id               NUMBER           NOT NULL,   -- -> d_train_status
    day_type                CHAR(2)          NOT NULL,   -- 'WD' dni robocze / 'WE' weekend
    -- miary addytywne (roll-up z f_train_run_daily; SUM dla sum/licznikow, MAX dla max)
    runs_count              NUMBER           NOT NULL,   -- liczba kursow
    delayed_count           NUMBER,                      -- kursy z opoznieniem koncowym >=6; NULL dla "Odwolany"
    sum_terminal_delay_min  NUMBER,                      -- suma opoznien koncowych; NULL dla "Odwolany"
    sum_delayed_delay_min   NUMBER,                      -- suma tylko spoznionych (>=6); NULL dla "Odwolany"
    max_terminal_delay_min  NUMBER,                      -- max opoznienie; NULL dla "Odwolany"
	travel_runs_count       NUMBER,   -- SUM(daily) - kursy ukonczone z policzalnym czasem = mianownik srednich
    sum_planned_travel_min  NUMBER,   -- SUM(daily) planowanych czasow przejazdu [min]
    sum_actual_travel_min   NUMBER,   -- SUM(daily) rzeczywistych czasow przejazdu [min]
    min_actual_travel_min   NUMBER,   -- MIN(daily) najszybszy rzeczywisty przejazd [min]
    max_actual_travel_min   NUMBER,    -- MAX(daily) najdluzszy rzeczywisty przejazd [min]
    loaded_at               TIMESTAMP WITH TIME ZONE NOT NULL,
    CONSTRAINT pk_agg_run_m PRIMARY KEY (month, route_id, train_type_id, status_id, day_type)
        USING INDEX LOCAL,
    CONSTRAINT chk_agg_run_m_daytype CHECK (day_type IN ('WD','WE'))
)
PARTITION BY RANGE (month) INTERVAL (1)
( PARTITION p_init VALUES LESS THAN (202601) );

grant select on gold.F_TRAIN_RUN_MONTHLY to DEV_APP;