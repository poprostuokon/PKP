-- =============================================================================
-- maintenance.sql_exec_queue
-- -----------------------------------------------------------------------------
-- Tabela kolejki warstwy utrzymaniowej: bufor poleceń DDL do wykonania
-- (reorganizacje tabel i indeksów, np. ALTER ... MOVE / REBUILD). Procedury
-- generujące dopisują tu polecenia, a procedura wykonująca opróżnia kolejkę
-- i zapisuje wynik do sql_exec_queue_log.
-- =============================================================================

CREATE TABLE maintenance.sql_exec_queue (
    sql_   CLOB                     NOT NULL   -- gotowy ALTER ... MOVE ... COMPRESS
);

grant select on maintenance.sql_exec_queue to DEV_APP;