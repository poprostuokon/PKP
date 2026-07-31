CREATE TABLE silver.operation_header (
    id              NUMBER                    	GENERATED ALWAYS AS IDENTITY,
    -- klucz naturalny z API
    schedule_id     NUMBER                		NOT NULL,
    order_id        NUMBER                		NOT NULL,
    train_order_id  NUMBER                		NOT NULL,
    operating_date  DATE                      	NOT NULL,
    -- stan kursu
    train_status    VARCHAR2(10 CHAR)         	NOT NULL,   	-- S/N/P/C/F/X → def_train_status.code (bez FK)
    -- metadane
    snapshot_ts     TIMESTAMP WITH TIME ZONE  	NOT NULL,   	-- generatedAt (UTC)
    loaded_at       TIMESTAMP WITH TIME ZONE  	NOT NULL,
    CONSTRAINT pk_ophe_id PRIMARY KEY (id),
    CONSTRAINT uq_ophe_opda_scid_orid_trid UNIQUE (operating_date, schedule_id, order_id, train_order_id)
);