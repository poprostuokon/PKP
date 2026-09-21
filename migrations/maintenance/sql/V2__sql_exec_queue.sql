-- =====================================================================
-- Kolejka komend do wykonania. TRUNCATE na starcie generatora.
-- Executor czyta wszystkie wiersze i odpala command.
-- =====================================================================
CREATE TABLE maintenance.sql_exec_queue (
    sql_   CLOB                     NOT NULL   -- gotowy ALTER ... MOVE ... COMPRESS
);

grant select on maintenance.sql_exec_queue to DEV_APP;