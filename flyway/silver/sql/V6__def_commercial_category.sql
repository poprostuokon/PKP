CREATE TABLE silver.def_commercial_category (
    code                 VARCHAR2(20 CHAR)         NOT NULL,   -- Os, IC, EC, EIC...
    name                 VARCHAR2(200 CHAR),
    carrier_code         VARCHAR2(20 CHAR)         NOT NULL,
    speed_category_code  VARCHAR2(20 CHAR),
    loaded_at            TIMESTAMP WITH TIME ZONE  NOT NULL,
    CONSTRAINT pk_dcoca_co_caco PRIMARY KEY (code, carrier_code)
);