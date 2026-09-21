CREATE TABLE silver.def_stop_type (
    id           NUMBER                 	NOT NULL,   -- z API (1, 2, ...)
    description  VARCHAR2(500 CHAR)        	NOT NULL,   -- "tylko dla wsiadających"
    loaded_at    TIMESTAMP WITH TIME ZONE  	NOT NULL,
    CONSTRAINT pk_dstty_id PRIMARY KEY (id)
);