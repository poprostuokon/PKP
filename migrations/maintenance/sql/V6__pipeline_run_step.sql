-- =============================================================================
-- MIGRACJA: V6__pipeline_run_step.sql
-- PROJEKT:  PKP Wrocław Główny
-- SCHEMAT:  maintenance
-- OPIS:     Tabela audytowa — pojedynczy krok (task) runu. Zapisywana przez
--           callbacki Airflow (pre_execute / success / failure / skipped).
--           Źródło prawdy dla timingu, statusu i stack trace w raporcie.
-- SILNIK:   Oracle 23ai (Autonomous Database)
-- =============================================================================

CREATE TABLE maintenance.pipeline_run_step (
    id                NUMBER GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    pipeline_run_id   NUMBER                   NOT NULL,
    step_name         VARCHAR2(200)            NOT NULL,          -- task_id z Airflow
    start_time        TIMESTAMP WITH TIME ZONE DEFAULT SYSTIMESTAMP NOT NULL,
    end_time          TIMESTAMP WITH TIME ZONE,
    status            VARCHAR2(20)             DEFAULT 'PENDING' NOT NULL,
    error_details     CLOB,                                       -- pełny stack trace / opis błędu
    created_at        TIMESTAMP WITH TIME ZONE DEFAULT SYSTIMESTAMP NOT NULL,
    CONSTRAINT fk_run_step_run
        FOREIGN KEY (pipeline_run_id)
        REFERENCES maintenance.pipeline_run (id),
    CONSTRAINT ck_run_step_status
        CHECK (status IN ('PENDING','SUCCESS','ERROR','SKIPPED'))
);

CREATE INDEX maintenance.idx_run_step_run_id
    ON maintenance.pipeline_run_step (pipeline_run_id);

CREATE INDEX maintenance.idx_run_step_status
    ON maintenance.pipeline_run_step (status);

COMMENT ON TABLE  maintenance.pipeline_run_step IS
    'Per-task audyt runu — czasy, status i błędy każdego kroku Airflow.';
COMMENT ON COLUMN maintenance.pipeline_run_step.step_name IS
    'task_id z Airflow; scrapery/loadery daily rozpoznawane po prefiksie.';