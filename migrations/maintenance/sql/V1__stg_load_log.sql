CREATE TABLE maintenance.stg_load_log (
    object_name   VARCHAR2(1024 CHAR)      NOT NULL,   -- pelna sciezka w buckecie (klucz)
    feed          VARCHAR2(30 CHAR)        NOT NULL,   -- schedules/operations/disruptions/dict:<name>
    load_mode     VARCHAR2(30 CHAR)        NOT NULL,   -- DAILY / LIVE
    part_date     DATE                     NOT NULL,   -- data partycji (z sciezki date=YYYYMMDD)
    status        VARCHAR2(10 CHAR)        NOT NULL,   -- LOADED / FAILED
    bytes         NUMBER,
    err_msg       VARCHAR2(4000 CHAR),
    loaded_at     TIMESTAMP WITH TIME ZONE NOT NULL,
    CONSTRAINT pk_stgload PRIMARY KEY (object_name),
    CONSTRAINT chk_stgload_status CHECK (status IN ('LOADED','FAILED'))
);
CREATE INDEX ix_stgload_day ON maintenance.stg_load_log (part_date, feed);

grant select, insert, update on maintenance.stg_load_log to DEV_APP;