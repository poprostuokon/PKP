CREATE TABLE silver.operation_tracking_log (
    id                   NUMBER                    	GENERATED ALWAYS AS IDENTITY,
    -- klucz naturalny z API (bez FK)
    schedule_id      	 NUMBER                		NOT NULL,
    order_id         	 NUMBER                		NOT NULL,
    train_order_id   	 NUMBER                		NOT NULL,
    operating_date       DATE                      	NOT NULL,
    dsta_id           	 NUMBER                		NOT NULL,   -- → silver.def_station.id (zrobić sprawdzenie i dodać  stacje do słownika gdy nie znajdzie id stacji)
    -- stan w momencie snapshotu
    train_status         VARCHAR2(10 CHAR)         	NOT NULL, 	-- S/N/P/C/F/X → def_train_status.code (bez FK)
    actual_arrival       TIMESTAMP WITH TIME ZONE,
    actual_departure     TIMESTAMP WITH TIME ZONE,
    arrival_delay_min    NUMBER,
    departure_delay_min  NUMBER,
    is_confirmed         BOOLEAN                   	NOT NULL,
    is_cancelled         BOOLEAN                   	NOT NULL,
    -- detekcja zmian
    change_hash          CHAR(64)                  	NOT NULL,   -- hash pól śledzonych
    -- czas
    snapshot_ts          TIMESTAMP WITH TIME ZONE  	NOT NULL,   -- generatedAt (event time)
    ingested_at          TIMESTAMP WITH TIME ZONE  	NOT NULL,   -- kiedy zapisano (processing time)
    CONSTRAINT pk_optrlog_id PRIMARY KEY (operating_date, id) USING INDEX LOCAL,	-- dzieki temu gdy usuniemy partycje nie trzeba odświeżać indeksu, gdyż w tej konfiguracji jest "lokalny"
	CONSTRAINT fk_optrlog_dsta_id FOREIGN KEY (dsta_id) REFERENCES silver.def_station(id)
)
PARTITION BY RANGE (operating_date)
INTERVAL (NUMTODSINTERVAL(1, 'DAY'))
(
    PARTITION p_anchor VALUES LESS THAN (DATE '2026-01-01')
);