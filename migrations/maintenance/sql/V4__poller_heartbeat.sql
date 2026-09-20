CREATE TABLE IF NOT EXISTS maintenance.poller_heartbeat (
    run_ts         TIMESTAMP                 NOT NULL,   -- start ticku (processing time) = klucz idempotencji
    feed           VARCHAR2(30 CHAR)         NOT NULL,   -- operations / disruptions
    outcome        VARCHAR2(10 CHAR)         NOT NULL,   -- OK / EMPTY / STALE / ERR
    delta_count    NUMBER,                               -- rekordow w delcie (0 dla EMPTY)
    generated_at   TIMESTAMP WITH TIME ZONE,             -- generatedAt przetworzonego snapshotu; NULL gdy fetch padl
    lag_seconds    NUMBER,                               -- now - generatedAt w chwili przetwarzania
    cycle_ms       NUMBER,                               -- czas trwania cyklu feedu
    err_msg        VARCHAR2(4000 CHAR),                  -- tresc bledu dla ERR
    created_at     TIMESTAMP WITH TIME ZONE  NOT NULL,   -- kiedy realnie zapisano do DB (moze != run_ts gdy ze spoola)
    CONSTRAINT pk_pollerhb PRIMARY KEY (run_ts, feed),
    CONSTRAINT chk_pollerhb_outcome CHECK (outcome IN ('OK','EMPTY','STALE','ERR'))
);

GRANT SELECT, INSERT ON maintenance.poller_heartbeat TO DEV_APP;