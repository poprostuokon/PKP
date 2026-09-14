-- =====================================================================
-- PKG_SILVER_LOAD_LIVE - ladowanie trackingu LIVE z landing _live.
-- operations: INSERT ONLY NEW po change_hash (append wersji).
-- disruptions: SCD2 - deactivate + insert (changed) oraz deactivate (ended).
-- change_hash liczy POLLER (SHA-256); tu tylko zapisujemy/porownujemy.
-- Owner: SILVER. AUTHID DEFINER. Repeatable migration Flyway.
-- =====================================================================

grant select on stg.LAND_OPERATIONS_LIVE  to silver;
grant select on stg.LAND_DISRUPTIONS_LIVE to silver;

CREATE OR REPLACE SYNONYM silver.land_operations_live  FOR stg.land_operations_live;
CREATE OR REPLACE SYNONYM silver.land_disruptions_live FOR stg.land_disruptions_live;


CREATE OR REPLACE PACKAGE silver.pkg_silver_load_live AUTHID DEFINER AS
    PROCEDURE load_operation_tracking;
    PROCEDURE load_disruption_tracking;
    PROCEDURE load_all_live;
END pkg_silver_load_live;
/

CREATE OR REPLACE PACKAGE BODY silver.pkg_silver_load_live AS

    PROCEDURE log_rows(p_rows IN NUMBER) IS
        v_full VARCHAR2(200);
        v_step VARCHAR2(128);
    BEGIN
        v_full := UTL_CALL_STACK.concatenate_subprogram(UTL_CALL_STACK.subprogram(2));
        v_step := LOWER(SUBSTR(v_full, INSTR(v_full, '.') + 1));
        DBMS_OUTPUT.PUT_LINE('  ' || RPAD(v_step, 28) || ' rows=' || p_rows);
    END log_rows;


    -- ================= OPERATIONS: INSERT ONLY NEW =================
    PROCEDURE load_operation_tracking IS
    BEGIN
        INSERT INTO operation_tracking_log
            (schedule_id, order_id, train_order_id, operating_date, dsta_id,
             train_status, actual_arrival, actual_departure,
             arrival_delay_min, departure_delay_min,
             is_confirmed, is_cancelled, change_hash, snapshot_ts, ingested_at)
        SELECT j.schedule_id, j.order_id, j.train_order_id,
               TO_DATE(j.operating_date, 'YYYY-MM-DD'), j.station_id,
               j.train_status, j.actual_arrival, j.actual_departure,
               j.arrival_delay_min, j.departure_delay_min,
               NVL(j.is_confirmed, 'false') = 'true',
               NVL(j.is_cancelled, 'false') = 'true',
               j.change_hash, j.snapshot_ts, pkg_tool.f_now_warsaw
        FROM land_operations_live src,
             json_table(src.payload, '$'
                 columns (
                     snapshot_ts timestamp with time zone path '$.generatedAt',
                     nested path '$.trains[*]' columns (
                         schedule_id     number              path '$.scheduleId',
                         order_id        number              path '$.orderId',
                         train_order_id  number              path '$.trainOrderId',
                         operating_date  varchar2(10 char)   path '$.operatingDate',
                         train_status    varchar2(4000 char) path '$.trainStatus',
                         change_hash     char(64)            path '$.changeHash',
                         nested path '$.stations[*]' columns (
                             station_id          number     path '$.stationId',
                             actual_arrival      timestamp  path '$.actualArrival',
                             actual_departure    timestamp  path '$.actualDeparture',
                             arrival_delay_min   number     path '$.arrivalDelayMinutes',
                             departure_delay_min number     path '$.departureDelayMinutes',
                             is_confirmed        varchar2(5) path '$.isConfirmed',
                             is_cancelled        varchar2(5) path '$.isCancelled'
                         )
                     )
                 )
             ) j
        WHERE j.change_hash IS NOT NULL
          AND NOT EXISTS (
                SELECT 1 FROM operation_tracking_log t
                WHERE t.operating_date = TO_DATE(j.operating_date, 'YYYY-MM-DD')
                  AND NVL(t.train_order_id, -1) = NVL(j.train_order_id, -1)
                  AND t.dsta_id = j.station_id
                  AND t.change_hash = j.change_hash
          );
        log_rows(SQL%ROWCOUNT);
    END load_operation_tracking;


    -- ================= DISRUPTIONS: SCD2 =================
    -- Klucz dopasowania: (operating_date, schedule_id, train_order_id[null-safe], dsta_id, sequence_number)
    -- order_id zapisywany, ale NIE w kluczu (niestabilny).
    PROCEDURE load_disruption_tracking IS
    BEGIN
        -- 1) CHANGED: dezaktywuj stara aktywna wersje (inny hash)
        UPDATE disruption_tracking_log t SET t.is_active = FALSE
        WHERE t.is_active = TRUE
          AND EXISTS (
                SELECT 1
                FROM land_disruptions_live src,
                     json_table(src.payload, '$'
                         columns (nested path '$.changed[*]' columns (
                             schedule_id     number            path '$.scheduleId',
                             train_order_id  number            path '$.trainOrderId',
                             operating_date  varchar2(10 char) path '$.operatingDate',
                             station_id      number            path '$.stationId',
                             sequence_number number            path '$.sequenceNumber',
                             change_hash     char(64)          path '$.changeHash'
                         ))) s
                WHERE t.operating_date = TO_DATE(s.operating_date, 'YYYY-MM-DD')
                  AND t.schedule_id = s.schedule_id
                  AND NVL(t.train_order_id, -1) = NVL(s.train_order_id, -1)
                  AND t.dsta_id = s.station_id
                  AND t.sequence_number = s.sequence_number
                  AND t.change_hash <> s.change_hash
          );

        -- 2) CHANGED: wstaw nowa aktywna wersje (brak aktywnej z tym hashem)
        INSERT INTO disruption_tracking_log
            (schedule_id, order_id, train_order_id, operating_date, dsta_id,
             sequence_number, disruption_type_code, message,
             change_hash, is_active, snapshot_ts, loaded_at)
        SELECT s.schedule_id, s.order_id, s.train_order_id,
               TO_DATE(s.operating_date, 'YYYY-MM-DD'), s.station_id,
               s.sequence_number, s.disruption_type_code, s.message,
               s.change_hash, TRUE, s.snapshot_ts, pkg_tool.f_now_warsaw
        FROM land_disruptions_live src,
             json_table(src.payload, '$'
                 columns (
                     snapshot_ts timestamp with time zone path '$.generatedAt',
                     nested path '$.changed[*]' columns (
                         schedule_id          number             path '$.scheduleId',
                         order_id             number             path '$.orderId',
                         train_order_id       number             path '$.trainOrderId',
                         operating_date       varchar2(10 char)  path '$.operatingDate',
                         station_id           number             path '$.stationId',
                         sequence_number      number             path '$.sequenceNumber',
                         disruption_type_code varchar2(20 char)  path '$.disruptionTypeCode',
                         message              varchar2(1000 char) path '$.message',
                         change_hash          char(64)           path '$.changeHash'
                     )
                 )) s
        WHERE s.change_hash IS NOT NULL
          AND NOT EXISTS (
                SELECT 1 FROM disruption_tracking_log t
                WHERE t.operating_date = TO_DATE(s.operating_date, 'YYYY-MM-DD')
                  AND t.schedule_id = s.schedule_id
                  AND NVL(t.train_order_id, -1) = NVL(s.train_order_id, -1)
                  AND t.dsta_id = s.station_id
                  AND t.sequence_number = s.sequence_number
                  AND t.change_hash = s.change_hash
                  AND t.is_active = TRUE
          );

        -- 3) ENDED: dezaktywuj aktywne wiersze pasujace do klucza
        UPDATE disruption_tracking_log t SET t.is_active = FALSE
        WHERE t.is_active = TRUE
          AND EXISTS (
                SELECT 1
                FROM land_disruptions_live src,
                     json_table(src.payload, '$'
                         columns (nested path '$.ended[*]' columns (
                             schedule_id     number            path '$.scheduleId',
                             train_order_id  number            path '$.trainOrderId',
                             operating_date  varchar2(10 char) path '$.operatingDate',
                             station_id      number            path '$.stationId',
                             sequence_number number            path '$.sequenceNumber'
                         ))) s
                WHERE t.operating_date = TO_DATE(s.operating_date, 'YYYY-MM-DD')
                  AND t.schedule_id = s.schedule_id
                  AND NVL(t.train_order_id, -1) = NVL(s.train_order_id, -1)
                  AND t.dsta_id = s.station_id
                  AND t.sequence_number = s.sequence_number
          );
        log_rows(SQL%ROWCOUNT);
    END load_disruption_tracking;


    PROCEDURE load_all_live IS
    BEGIN
        DBMS_OUTPUT.PUT_LINE('=== SILVER LIVE load START ===');
        EXECUTE IMMEDIATE 'ALTER SESSION DISABLE PARALLEL DML';
        load_operation_tracking;
        load_disruption_tracking;
        COMMIT;
        DBMS_OUTPUT.PUT_LINE('=== SILVER LIVE load OK (COMMIT) ===');
    EXCEPTION
        WHEN OTHERS THEN
            ROLLBACK;
            DBMS_OUTPUT.PUT_LINE('=== SILVER LIVE load ERROR - ROLLBACK: ' || SQLERRM);
            RAISE;
    END load_all_live;

END pkg_silver_load_live;
/

grant execute on SILVER.pkg_silver_load_live to DEV_APP;