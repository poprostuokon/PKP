CREATE TABLE silver.def_disruption_cause (
    code         VARCHAR2(20 CHAR)         NOT NULL,   -- utr_01 ... utr_75 (disruptionTypeCode)
    description  VARCHAR2(500 CHAR)        NOT NULL,   -- "Awaria sieci trakcyjnej"
    loaded_at    TIMESTAMP WITH TIME ZONE  NOT NULL,
    CONSTRAINT pk_ddica_code PRIMARY KEY (code)
);