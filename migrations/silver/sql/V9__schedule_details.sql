CREATE TABLE silver.schedule_details (
    schedule_id     	NUMBER     						NOT NULL,   -- edycja rozkladu (np. 2026)
    order_id        	NUMBER      					NOT NULL,   -- wersja tresci planu
    -- pozycja na trasie
    order_number        NUMBER                     		NOT NULL,   -- MOŻE być ujemny (zagranica)
    dsta_id          	NUMBER                    		NOT NULL,   -- → silver.def_station.id
    -- przyjazd
    --arrival_time        INTERVAL DAY(0) TO SECOND(0),             	-- był TIME; NULL na stacji pocz.
	arrival_time        VARCHAR2(8),
    arrival_day         NUMBER,                                		-- offset dnia (0,1) — przez północ
    arrival_at          TIMESTAMP WITH TIME ZONE,                 	-- wyliczane -> UTC
    arrival_platform    VARCHAR2(10 CHAR),
    arrival_track       VARCHAR2(10 CHAR),
    arrival_category    VARCHAR2(20 CHAR),                        	-- → silver.def_commercial_category
    arrival_train_no    VARCHAR2(50 CHAR),                        	-- bywa "262/65002"
    -- odjazd
    --departure_time      INTERVAL DAY(0) TO SECOND(0),             	-- był TIME; NULL na stacji końc.
	departure_time      VARCHAR2(8),
    departure_day       NUMBER,
    departure_at        TIMESTAMP WITH TIME ZONE,                 	-- wyliczane
    departure_platform  VARCHAR2(10 CHAR),
    departure_track     VARCHAR2(10 CHAR),
    departure_category  VARCHAR2(20 CHAR),
    departure_train_no  VARCHAR2(50 CHAR),
    -- postój
    dstty_id        	NUMBER,                                		-- → silver.def_stop_type.id
    CONSTRAINT pk_scde_id      PRIMARY KEY (schedule_id, order_id, order_number),
	CONSTRAINT fk_scde_dsta_id FOREIGN KEY (dsta_id) REFERENCES silver.def_station(id),
	CONSTRAINT fk_scde_dstty_id FOREIGN KEY (dstty_id) REFERENCES silver.def_stop_type(id)
);

ALTER TABLE silver.schedule_details  ADD CONSTRAINT chk_scde_arrival_time 
CHECK (REGEXP_LIKE(arrival_time, '^([0-1][0-9]|2[0-3]):[0-5][0-9]:[0-5][0-9]$'));

ALTER TABLE silver.schedule_details  ADD CONSTRAINT chk_scde_departure_time 
CHECK (REGEXP_LIKE(departure_time, '^([0-1][0-9]|2[0-3]):[0-5][0-9]:[0-5][0-9]$'));