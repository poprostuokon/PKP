CREATE TABLE silver.def_station (
    id             NUMBER                	 NOT NULL,   -- klucz naturalny z API
    name           VARCHAR2(200 CHAR)        NOT NULL,
    dcit_id        NUMBER,                               -- → silver.def_city.id
    is_active      BOOLEAN                   DEFAULT TRUE NOT NULL,  -- false gdy zniknie z API
    first_seen_at  TIMESTAMP WITH TIME ZONE  NOT NULL,
    loaded_at      TIMESTAMP WITH TIME ZONE  NOT NULL,
    CONSTRAINT pk_dsta_id PRIMARY KEY (id),
    CONSTRAINT fk_dsta_dcit_id FOREIGN KEY (dcit_id) REFERENCES silver.def_city(id)
);