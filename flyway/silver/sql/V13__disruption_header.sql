CREATE TABLE silver.disruption_header (
	id                   NUMBER                    	GENERATED ALWAYS AS IDENTITY,
    -- utrudnienie
    disruption_type_code VARCHAR2(20 CHAR),   			-- → silver.def_disruption_cause.code (disruptionTypeCode) bez FK bo może być null (tylko message)
	message				 VARCHAR2(1000 CHAR),			-- może być null
    -- czas
    snapshot_ts          TIMESTAMP WITH TIME ZONE  	NOT NULL,   -- generatedAt (UTC)
    loaded_at            TIMESTAMP WITH TIME ZONE  	NOT NULL,
    CONSTRAINT pk_dihe_id PRIMARY KEY (id)
);