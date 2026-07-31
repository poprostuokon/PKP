CREATE TABLE silver.schedule_header (
    id                     NUMBER                    GENERATED ALWAYS AS IDENTITY,
    -- klucz naturalny z API
    schedule_id            NUMBER                	 NOT NULL,   -- edycja rozkładu (2026)
    order_id               NUMBER                	 NOT NULL,   -- wersja planu
    train_order_id         NUMBER                	 NOT NULL,   -- tożsamość kursu (stabilna)
    operating_date         DATE                      NOT NULL,   -- dzień kursowania (lokalny)
    -- atrybuty kursu
    name                   VARCHAR2(200 CHAR),                   -- często NULL
    carrier_code           VARCHAR2(20 CHAR)         NOT NULL,   -- → silver.def_carrier.code (bez FK, SCD2)
    category_code          VARCHAR2(20 CHAR)         NOT NULL,   -- → silver.def_commercial_category (bez FK)
    -- numery pociągu
    national_number        VARCHAR2(50 CHAR)         NOT NULL,   -- oryginał, bywa "262/65002"
    intl_arrival_number    VARCHAR2(50 CHAR),
    intl_departure_number  VARCHAR2(50 CHAR),
    -- metadane
    snapshot_ts            TIMESTAMP WITH TIME ZONE  NOT NULL,   -- generatedAt (UTC)
    loaded_at              TIMESTAMP WITH TIME ZONE  NOT NULL,
    CONSTRAINT pk_sche_id PRIMARY KEY (id),
    CONSTRAINT uq_sche_opda_scid_orid_torid UNIQUE (operating_date, schedule_id, order_id, train_order_id)
);