CREATE TABLE silver.disruption_details (
    schedule_id          NUMBER                		NOT NULL,
    order_id             NUMBER                		NOT NULL,
    train_order_id       NUMBER                		,
    operating_date       DATE                      	NOT NULL,
	sequence_number      NUMBER                 	NOT NULL,
    dsta_id           	 NUMBER                		NOT NULL,   -- → silver.def_station.id
    -- utrudnienie
	dihe_id				 NUMBER						NOT NULL,	-- → silver.disruption_header.id
    -- czas
    loaded_at            TIMESTAMP WITH TIME ZONE  	NOT NULL,
    CONSTRAINT pk_dide_opda_scid_orid_stid_diid PRIMARY KEY (operating_date, schedule_id, order_id, dsta_id, dihe_id),
	--CONSTRAINT fk_dide_dsta_id FOREIGN KEY (dsta_id) REFERENCES silver.def_station(id), -- są przypadki gdzie są wykonane trasy do stacji których nie ma w słowniku (api stacji nie zwrca takie ID ze słownika)
	CONSTRAINT fk_dide_dihe_id FOREIGN KEY (dihe_id) REFERENCES silver.disruption_header(id) ON DELETE CASCADE
);