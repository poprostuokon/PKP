-- =============================================================================
-- MIGRACJA: V5__pipeline_run.sql
-- PROJEKT:  PKP Wrocław Główny
-- SCHEMAT:  maintenance
-- OPIS:     Tabela audytowa — nagłówek pojedynczego uruchomienia daily pipeline.
--           Rekord zakładany na starcie (set_run_date), domykany na końcu.
-- SILNIK:   Oracle 23ai (Autonomous Database)
-- =============================================================================

CREATE TABLE maintenance.pipeline_run (
    id           NUMBER GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    run_date     DATE                     NOT NULL,               -- data logiczna runu (z set_run_date)
    dag_run_id   VARCHAR2(250)            NOT NULL,               -- run_id z Airflow (scheduled__... / manual__...)
    start_time   TIMESTAMP WITH TIME ZONE DEFAULT SYSTIMESTAMP NOT NULL,
    end_time     TIMESTAMP WITH TIME ZONE,                        -- uzupełniane przy domknięciu runu
    status       VARCHAR2(20)             DEFAULT 'PENDING' NOT NULL,
    created_at   TIMESTAMP WITH TIME ZONE DEFAULT SYSTIMESTAMP NOT NULL,
    CONSTRAINT ck_pipeline_run_status
        CHECK (status IN ('PENDING','SUCCESS','PARTIAL_SUCCESS','ERROR')),
    CONSTRAINT uq_pipeline_run_dag_run_id
        UNIQUE (dag_run_id)                                       -- jeden rekord na dag_run_id (guard na dubel z set_run_date)
);

CREATE INDEX idx_pipeline_run_date
    ON maintenance.pipeline_run (run_date);

COMMENT ON TABLE  maintenance.pipeline_run IS
    'Nagłówek dziennego runu pipeline PKP — jeden wiersz na dag_run_id.';
COMMENT ON COLUMN maintenance.pipeline_run.status IS
    'PENDING na starcie; SUCCESS / PARTIAL_SUCCESS / ERROR po domknięciu.';