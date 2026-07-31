CREATE TABLE silver.operation_details (
    ophe_id  			 NUMBER      NOT NULL,
    -- pozycja na trasie
    planned_sequence     NUMBER   NOT NULL,   	-- plannedSequenceNumber
    actual_sequence      NUMBER   NOT NULL,   	
    dsta_id           	 NUMBER  NOT NULL,   	-- → silver.def_station.id
    -- wykonanie (gotowe timestampy z API, UTC)
    actual_arrival       TIMESTAMP WITH TIME ZONE,
    actual_departure     TIMESTAMP WITH TIME ZONE,
    -- status przystanku
    is_confirmed         BOOLEAN     NOT NULL,   -- cf: potwierdzone przejechanie
    is_cancelled         BOOLEAN     NOT NULL,   -- cn: przystanek odwołany
    -- miary wyliczane przy ładowaniu (join do schedule_details)
    arrival_delay_min    NUMBER,             -- actual_arrival − plan
    departure_delay_min  NUMBER,             -- actual_departure − plan
    dwell_time_sec       NUMBER,             -- actual_departure − actual_arrival
    CONSTRAINT pk_opde_id PRIMARY KEY (ophe_id, actual_sequence),
    CONSTRAINT fk_opde_ophe_id FOREIGN KEY (ophe_id) REFERENCES silver.operation_header(id) ON DELETE CASCADE,
	CONSTRAINT fk_opde_dsta_id FOREIGN KEY (dsta_id) REFERENCES silver.def_station(id)
);