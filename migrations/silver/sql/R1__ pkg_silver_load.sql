-- =====================================================================
-- PKG_SILVER_LOAD - ladowanie warstwy SILVER z STG.
--
-- Konwencje:
--   * wymiary def_* -> MERGE (upsert po kluczu biznesowym)
--   * fakty         -> INSERT ONLY NEW (INSERT ... WHERE NOT EXISTS)
--   * loaded_at / first_seen_at -> pkg_tool.f_now_warsaw (czas PL)
--   * bez prefiksow schematow -> SYNONIMY 
--
-- Owner: SILVER. AUTHID DEFINER. Uruchamiaj jako DEV_APP (grant execute na koncu).
-- Repeatable migration Flyway.
-- =====================================================================

-- ---- granty na obiekty bazowe ----
grant execute on MAINTENANCE.PKG_TOOL to silver;
grant select on stg.LAND_SCHEDULES to silver;
grant select on stg.LAND_OPERATIONS to silver;
grant select on stg.LAND_DISRUPTIONS to silver;
grant select on stg.LAND_CITIES to silver;
grant select on stg.LAND_STATIONS to silver;
grant select on stg.LAND_CARRIERS to silver;
grant select on stg.LAND_TRAIN_STATUSES to silver;
grant select on stg.LAND_STOP_TYPES to silver;
grant select on stg.LAND_COMMERCIAL_CATEGORIES to silver;
grant select on stg.LAND_DISRUPTION_TYPES to silver;

-- ---- synonimy ----
CREATE OR REPLACE SYNONYM silver.pkg_tool                     FOR maintenance.pkg_tool;
CREATE OR REPLACE SYNONYM silver.land_schedules              FOR stg.land_schedules;
CREATE OR REPLACE SYNONYM silver.land_operations            FOR stg.land_operations;
CREATE OR REPLACE SYNONYM silver.land_disruptions           FOR stg.land_disruptions;
CREATE OR REPLACE SYNONYM silver.land_cities                FOR stg.land_cities;
CREATE OR REPLACE SYNONYM silver.land_stations             FOR stg.land_stations;
CREATE OR REPLACE SYNONYM silver.land_carriers             FOR stg.land_carriers;
CREATE OR REPLACE SYNONYM silver.land_train_statuses       FOR stg.land_train_statuses;
CREATE OR REPLACE SYNONYM silver.land_stop_types           FOR stg.land_stop_types;
CREATE OR REPLACE SYNONYM silver.land_commercial_categories FOR stg.land_commercial_categories;
CREATE OR REPLACE SYNONYM silver.land_disruption_types     FOR stg.land_disruption_types;



CREATE OR REPLACE PACKAGE silver.pkg_silver_load AUTHID DEFINER AS
    -- wymiary
    PROCEDURE load_def_carrier;
    PROCEDURE load_def_city;
    PROCEDURE load_def_station;
    PROCEDURE load_def_stop_type;
    PROCEDURE load_def_commercial_category;
    PROCEDURE load_def_train_status;
    PROCEDURE load_def_disruption_cause;
    -- fakty
    PROCEDURE load_schedule_header;
    PROCEDURE load_schedule_details;
    PROCEDURE load_operation_header;
    PROCEDURE load_operation_details;
    PROCEDURE load_disruption_header;
    PROCEDURE load_disruption_details;
    -- orchestracja: wszystko w kolejnosci zaleznosci, jeden COMMIT
    PROCEDURE load_all;
END pkg_silver_load;
/

CREATE OR REPLACE PACKAGE BODY silver.pkg_silver_load AS

    -- log do DBMS_OUTPUT; nazwa kroku = nazwa wolajacej procedury (z call stacku)
    PROCEDURE log_rows(p_rows IN NUMBER) IS
        v_full VARCHAR2(200);
        v_step VARCHAR2(128);
    BEGIN
        v_full := UTL_CALL_STACK.concatenate_subprogram( UTL_CALL_STACK.subprogram(2) ); -- PKG.LOAD_X
        v_step := LOWER( SUBSTR(v_full, INSTR(v_full, '.') + 1) );                        -- load_x
        DBMS_OUTPUT.PUT_LINE( RPAD(v_step, 32) || ' -> ' || p_rows || ' wierszy' );
    END log_rows;

    -- ================= WYMIARY (MERGE) =================

    PROCEDURE load_def_carrier IS
    BEGIN
        MERGE INTO def_carrier d
        USING (
            select jt.code,
                   jt.name,
                   cast(jt.valid_from as date) as valid_from,
                   cast(jt.valid_to   as date) as valid_to
            from   land_carriers l,
                   json_table(l.payload, '$.carriers[*]'
                       columns (
                           code       varchar2(4000 char) path '$.code',
                           name       varchar2(4000 char) path '$.name',
                           valid_from timestamp            path '$.validFrom',
                           valid_to   timestamp            path '$.validTo'
                       )) jt
        ) s
        ON (d.code = s.code AND d.valid_from = s.valid_from)
        WHEN MATCHED THEN UPDATE SET d.name = s.name, d.valid_to = s.valid_to, d.loaded_at = pkg_tool.f_now_warsaw
        WHEN NOT MATCHED THEN
            INSERT (code, name, valid_from, valid_to, loaded_at)
            VALUES (s.code, s.name, s.valid_from, s.valid_to, pkg_tool.f_now_warsaw);
        log_rows(SQL%ROWCOUNT);
    END load_def_carrier;

    PROCEDURE load_def_city IS
    BEGIN
        MERGE INTO def_city d
        USING (
            select jt.name as city_name, jt.station_count
            from   land_cities l,
                   json_table(l.payload, '$.cities[*]'
                       columns (
                           name          varchar2(4000 char) path '$.name',
                           station_count number              path '$.stationCount'
                       )) jt
        ) s
        ON (d.name = s.city_name)
        WHEN MATCHED THEN UPDATE SET d.station_count = s.station_count, d.loaded_at = pkg_tool.f_now_warsaw
        WHEN NOT MATCHED THEN
            INSERT (name, station_count, loaded_at)        
            VALUES (s.city_name, s.station_count, pkg_tool.f_now_warsaw);
        log_rows(SQL%ROWCOUNT);
    END load_def_city;

    PROCEDURE load_def_station IS
    BEGIN
        MERGE INTO def_station d
        USING (
            select st.station_id, st.station_name, c.id as dcit_id
            from (
                    select jt.id as station_id, jt.name as station_name
                    from   land_stations l,
                           json_table(l.payload, '$.stations[*]'
                               columns (id number path '$.id', name varchar2(4000 char) path '$.name')) jt
                 ) st
            left join (
                    select jt.city_name, jt.station_id
                    from   land_cities l,
                           json_table(l.payload, '$.cities[*]'
                               columns (
                                   city_name varchar2(4000 char) path '$.name',
                                   nested path '$.stationIds[*]' columns (station_id number path '$')
                               )) jt
                 ) m on m.station_id = st.station_id
            left join def_city c on c.name = m.city_name
            qualify row_number() over (partition by st.station_id order by c.id nulls last) = 1
        ) s
        ON (d.id = s.station_id)
        WHEN MATCHED THEN UPDATE SET d.name = s.station_name, d.dcit_id = s.dcit_id, d.loaded_at = pkg_tool.f_now_warsaw
        WHEN NOT MATCHED THEN
            INSERT (id, name, dcit_id, first_seen_at, loaded_at)
            VALUES (s.station_id, s.station_name, s.dcit_id, pkg_tool.f_now_warsaw, pkg_tool.f_now_warsaw);
        log_rows(SQL%ROWCOUNT);
    END load_def_station;

    PROCEDURE load_def_stop_type IS
    BEGIN
        MERGE INTO def_stop_type d
        USING (
            select jt.id as stop_type_id, jt.description
            from   land_stop_types l,
                   json_table(l.payload, '$.stopTypes[*]'
                       columns (id number path '$.id', description varchar2(4000 char) path '$.description')) jt
        ) s
        ON (d.id = s.stop_type_id)
        WHEN MATCHED THEN UPDATE SET d.description = s.description, d.loaded_at = pkg_tool.f_now_warsaw
        WHEN NOT MATCHED THEN
            INSERT (id, description, loaded_at) VALUES (s.stop_type_id, s.description, pkg_tool.f_now_warsaw);
        log_rows(SQL%ROWCOUNT);
    END load_def_stop_type;

    PROCEDURE load_def_commercial_category IS
    BEGIN
        MERGE INTO def_commercial_category d
        USING (
            select jt.code, jt.name, jt.carrier_code, jt.speed_category_code
            from   land_commercial_categories l,
                   json_table(l.payload, '$.commercialCategories[*]'
                       columns (
                           code                varchar2(4000 char) path '$.code',
                           name                varchar2(4000 char) path '$.name',
                           carrier_code        varchar2(4000 char) path '$.carrierCode',
                           speed_category_code varchar2(4000 char) path '$.speedCategoryCode'
                       )) jt
            qualify row_number() over (partition by jt.code, jt.carrier_code order by 1) = 1
        ) s
        ON (d.code = s.code AND d.carrier_code = s.carrier_code)
        WHEN MATCHED THEN UPDATE SET d.name = s.name, d.speed_category_code = s.speed_category_code, d.loaded_at = pkg_tool.f_now_warsaw
        WHEN NOT MATCHED THEN
            INSERT (code, name, carrier_code, speed_category_code, loaded_at)
            VALUES (s.code, s.name, s.carrier_code, s.speed_category_code, pkg_tool.f_now_warsaw);
        log_rows(SQL%ROWCOUNT);
    END load_def_commercial_category;

    PROCEDURE load_def_train_status IS
    BEGIN
        MERGE INTO def_train_status d
        USING (
            select jt.k as code, jt.v as name
            from   land_train_statuses l,
                   json_table(
                       pkg_tool.f_json_obj_to_kv(json_query(l.payload, '$.trainStatuses' returning clob)),
                       '$[*]' columns (k varchar2(4000 char) path '$.k', v varchar2(4000 char) path '$.v')) jt
        ) s
        ON (d.code = s.code)
        WHEN MATCHED THEN UPDATE SET d.name = s.name, d.loaded_at = pkg_tool.f_now_warsaw
        WHEN NOT MATCHED THEN
            INSERT (code, name, loaded_at) VALUES (s.code, s.name, pkg_tool.f_now_warsaw);
        log_rows(SQL%ROWCOUNT);
    END load_def_train_status;

    PROCEDURE load_def_disruption_cause IS
    BEGIN
        MERGE INTO def_disruption_cause d
        USING (
            select jt.k as code, jt.v as description
            from   land_disruption_types l,
                   json_table(
                       pkg_tool.f_json_obj_to_kv(json_query(l.payload, '$.disruptionTypes' returning clob)),
                       '$[*]' columns (k varchar2(4000 char) path '$.k', v varchar2(4000 char) path '$.v')) jt
        ) s
        ON (d.code = s.code)
        WHEN MATCHED THEN UPDATE SET d.description = s.description, d.loaded_at = pkg_tool.f_now_warsaw
        WHEN NOT MATCHED THEN
            INSERT (code, description, loaded_at) VALUES (s.code, s.description, pkg_tool.f_now_warsaw);
        log_rows(SQL%ROWCOUNT);
    END load_def_disruption_cause;

    -- ================= FAKTY (INSERT ONLY NEW + QUALIFY) =================

    PROCEDURE load_schedule_header IS
    BEGIN
        INSERT INTO schedule_header
            (schedule_id, order_id, train_order_id, operating_date, name, carrier_code, category_code,
             national_number, intl_arrival_number, intl_departure_number, snapshot_ts, loaded_at)
        SELECT j.schedule_id, j.order_id, j.train_order_id,
               to_date(j.operating_date, 'YYYY-MM-DD'),
               j.name, j.carrier_code, j.category_code,
               j.national_number, j.intl_arrival_number, j.intl_departure_number, j.snapshot_ts,
               pkg_tool.f_now_warsaw
        FROM land_schedules src,
             json_table(src.payload, '$'
                 columns (
                     snapshot_ts timestamp with time zone path '$.generatedAt',
                     nested path '$.routes[*]' columns (
                         schedule_id           number              path '$.scheduleId',
                         order_id              number              path '$.orderId',
                         train_order_id        number              path '$.trainOrderId',
                         name                  varchar2(4000 char) path '$.name',
                         carrier_code          varchar2(4000 char) path '$.carrierCode',
                         national_number       varchar2(4000 char) path '$.nationalNumber',
                         intl_arrival_number   varchar2(4000 char) path '$.internationalArrivalNumber',
                         intl_departure_number varchar2(4000 char) path '$.internationalDepartureNumber',
                         category_code         varchar2(4000 char) path '$.commercialCategorySymbol',
                         nested path '$.operatingDates[*]' columns (operating_date varchar2(4000 char) path '$')
                     )
                 )) j
        WHERE NOT EXISTS (
                  select 1 from schedule_header t
                  where t.operating_date = to_date(j.operating_date, 'YYYY-MM-DD')
                    and t.schedule_id = j.schedule_id and t.order_id = j.order_id
                    and t.train_order_id = j.train_order_id)
        QUALIFY row_number() over (
                    partition by j.operating_date, j.schedule_id, j.order_id, j.train_order_id order by 1) = 1;
        log_rows(SQL%ROWCOUNT);
    END load_schedule_header;

    PROCEDURE load_schedule_details IS
    BEGIN
        INSERT INTO schedule_details
            (schedule_id, order_id, order_number, dsta_id, arrival_time, arrival_day, arrival_at,
             arrival_platform, arrival_track, arrival_category, arrival_train_no,
             departure_time, departure_day, departure_at, departure_platform, departure_track,
             departure_category, departure_train_no, dstty_id)
        SELECT j.schedule_id, j.order_id, j.order_number, j.station_id,
               j.arrival_time, j.arrival_day, cast(null as timestamp with time zone),
               j.arrival_platform, j.arrival_track, j.arrival_category, j.arrival_train_no,
               j.departure_time, j.departure_day, cast(null as timestamp with time zone),
               j.departure_platform, j.departure_track, j.departure_category, j.departure_train_no,
               j.stop_type_id
        FROM land_schedules src,
             json_table(src.payload, '$.routes[*]'
                 columns (
                     schedule_id number path '$.scheduleId',
                     order_id    number path '$.orderId',
                     nested path '$.stations[*]' columns (
                         order_number        number              path '$.orderNumber',
                         station_id          number              path '$.stationId',
                         arrival_time        varchar2(4000 char) path '$.arrivalTime',
                         arrival_day         number              path '$.arrivalDay',
                         arrival_platform    varchar2(4000 char) path '$.arrivalPlatform',
                         arrival_track       varchar2(4000 char) path '$.arrivalTrack',
                         arrival_category    varchar2(4000 char) path '$.arrivalCommercialCategory',
                         arrival_train_no    varchar2(4000 char) path '$.arrivalTrainNumber',
                         departure_time      varchar2(4000 char) path '$.departureTime',
                         departure_day       number              path '$.departureDay',
                         departure_platform  varchar2(4000 char) path '$.departurePlatform',
                         departure_track     varchar2(4000 char) path '$.departureTrack',
                         departure_category  varchar2(4000 char) path '$.departureCommercialCategory',
                         departure_train_no  varchar2(4000 char) path '$.departureTrainNumber',
                         stop_type_id        number              path '$.stopTypeId'
                     )
                 )) j
        WHERE NOT EXISTS (
                  select 1 from schedule_details t
                  where t.schedule_id = j.schedule_id and t.order_id = j.order_id
                    and t.order_number = j.order_number)
        QUALIFY row_number() over (
                    partition by j.schedule_id, j.order_id, j.order_number order by 1) = 1;
        log_rows(SQL%ROWCOUNT);
    END load_schedule_details;

    PROCEDURE load_operation_header IS
    BEGIN
        INSERT INTO operation_header
            (schedule_id, order_id, train_order_id, operating_date, train_status, snapshot_ts, loaded_at)
        SELECT j.schedule_id, j.order_id, j.train_order_id,
               to_date(j.operating_date, 'YYYY-MM-DD'), j.train_status, j.snapshot_ts, pkg_tool.f_now_warsaw
        FROM land_operations src,
             json_table(src.payload, '$'
                 columns (
                     snapshot_ts timestamp with time zone path '$.generatedAt',
                     nested path '$.trains[*]' columns (
                         schedule_id    number              path '$.scheduleId',
                         order_id       number              path '$.orderId',
                         train_order_id number              path '$.trainOrderId',
                         operating_date varchar2(4000 char) path '$.operatingDate',
                         train_status   varchar2(4000 char) path '$.trainStatus'
                     )
                 )) j
        WHERE NOT EXISTS (
                  select 1 from operation_header t
                  where t.operating_date = to_date(j.operating_date, 'YYYY-MM-DD')
                    and t.schedule_id = j.schedule_id and t.order_id = j.order_id
                    and t.train_order_id = j.train_order_id)
        QUALIFY row_number() over (
                    partition by j.operating_date, j.schedule_id, j.order_id, j.train_order_id order by 1) = 1;
        log_rows(SQL%ROWCOUNT);
    END load_operation_header;

    PROCEDURE load_operation_details IS
    BEGIN
        INSERT INTO operation_details
            (ophe_id, planned_sequence, actual_sequence, dsta_id, actual_arrival, actual_departure,
             is_confirmed, is_cancelled, arrival_delay_min, departure_delay_min, dwell_time_sec)
        SELECT oh.id, j.planned_sequence, j.actual_sequence, j.station_id,
               j.actual_arrival, j.actual_departure,
               coalesce(j.is_confirmed, false), coalesce(j.is_cancelled, false),
               j.arrival_delay_min, j.departure_delay_min,
               round((cast(j.actual_departure as date) - cast(j.actual_arrival as date)) * 86400)
        FROM land_operations src,
             json_table(src.payload, '$.trains[*]'
                 columns (
                     schedule_id    number              path '$.scheduleId',
                     order_id       number              path '$.orderId',
                     train_order_id number              path '$.trainOrderId',
                     operating_date varchar2(4000 char) path '$.operatingDate',
                     nested path '$.stations[*]' columns (
                         station_id          number                    path '$.stationId',
                         planned_sequence    number                    path '$.plannedSequenceNumber',
                         actual_sequence     number                    path '$.actualSequenceNumber',
                         actual_arrival      timestamp with time zone  path '$.actualArrival',
                         actual_departure    timestamp with time zone  path '$.actualDeparture',
                         arrival_delay_min   number                    path '$.arrivalDelayMinutes',
                         departure_delay_min number                    path '$.departureDelayMinutes',
                         is_confirmed        boolean                   path '$.isConfirmed',
                         is_cancelled        boolean                   path '$.isCancelled'
                     )
                 )) j
             join operation_header oh
                 on  oh.schedule_id    = j.schedule_id
                 and oh.order_id       = j.order_id
                 and oh.train_order_id = j.train_order_id
                 and oh.operating_date = to_date(j.operating_date, 'YYYY-MM-DD')
        WHERE NOT EXISTS (
                  select 1 from operation_details t
                  where t.ophe_id = oh.id and t.actual_sequence = j.actual_sequence)
        QUALIFY row_number() over (partition by oh.id, j.actual_sequence order by 1) = 1;
        log_rows(SQL%ROWCOUNT);
    END load_operation_details;

    PROCEDURE load_disruption_header IS
    BEGIN
        INSERT INTO disruption_header
            (id, disruption_type_code, message, snapshot_ts, loaded_at)
        SELECT to_number(to_char(cast(j.snapshot_ts as date), 'YYYYMMDD')) * 1000000 + j.disruption_id,
               j.disruption_type_code, j.message, j.snapshot_ts, pkg_tool.f_now_warsaw
        FROM land_disruptions src,
             json_table(src.payload, '$'
                 columns (
                     snapshot_ts timestamp with time zone path '$.generatedAt',
                     nested path '$.disruptions[*]' columns (
                         disruption_id        number              path '$.disruptionId',
                         disruption_type_code varchar2(4000 char) path '$.disruptionTypeCode',
                         message              varchar2(4000 char) path '$.message'
                     )
                 )) j
        WHERE NOT EXISTS (
                  select 1 from disruption_header t
                  where t.id = to_number(to_char(cast(j.snapshot_ts as date), 'YYYYMMDD')) * 1000000 + j.disruption_id)
        QUALIFY row_number() over (partition by cast(j.snapshot_ts as date), j.disruption_id order by 1) = 1;
        log_rows(SQL%ROWCOUNT);
    END load_disruption_header;

    PROCEDURE load_disruption_details IS
    BEGIN
        INSERT INTO disruption_details
            (schedule_id, order_id, train_order_id, operating_date, sequence_number, dsta_id, dihe_id, loaded_at)
        SELECT j.schedule_id, j.order_id, j.train_order_id,
               to_date(j.operating_date, 'YYYY-MM-DD'), j.sequence_number, j.station_id,
               to_number(to_char(cast(j.snapshot_ts as date), 'YYYYMMDD')) * 1000000 + j.disruption_id,
               pkg_tool.f_now_warsaw
        FROM land_disruptions src,
             json_table(src.payload, '$'
                 columns (
                     snapshot_ts timestamp with time zone path '$.generatedAt',
                     nested path '$.disruptions[*]' columns (
                         disruption_id number path '$.disruptionId',
                         nested path '$.affectedRoutes[*]' columns (
                             schedule_id     number              path '$.scheduleId',
                             order_id        number              path '$.orderId',
                             train_order_id  number              path '$.trainOrderId',
                             operating_date  varchar2(4000 char) path '$.operatingDate',
                             station_id      number              path '$.stationId',
                             sequence_number number              path '$.sequenceNumber'
                         )
                     )
                 )) j
        WHERE j.schedule_id is not null and j.order_id is not null and j.train_order_id is not null
          AND NOT EXISTS (
                  select 1 from disruption_details t
                  where t.operating_date = to_date(j.operating_date, 'YYYY-MM-DD')
                    and t.schedule_id = j.schedule_id and t.train_order_id = j.train_order_id
                    and t.dsta_id = j.station_id
                    and t.dihe_id = to_number(to_char(cast(j.snapshot_ts as date), 'YYYYMMDD')) * 1000000 + j.disruption_id)
        QUALIFY row_number() over (
                    partition by to_date(j.operating_date, 'YYYY-MM-DD'), j.schedule_id, j.train_order_id, j.station_id,
                                 (to_number(to_char(cast(j.snapshot_ts as date), 'YYYYMMDD')) * 1000000 + j.disruption_id)
                    order by 1) = 1;
        log_rows(SQL%ROWCOUNT);
    END load_disruption_details;

    -- ================= ORCHESTRACJA =================

    PROCEDURE load_all IS
    BEGIN
        DBMS_OUTPUT.PUT_LINE('=== SILVER load START ===');
		EXECUTE IMMEDIATE 'ALTER SESSION DISABLE PARALLEL DML';
        -- wymiary (kolejnosc: city przed station)
        load_def_carrier;
        load_def_city;
        load_def_station;
        load_def_stop_type;
        load_def_commercial_category;
        load_def_train_status;
        load_def_disruption_cause;
        -- fakty (header przed details tam gdzie FK)
        load_schedule_header;
        load_schedule_details;
        load_operation_header;
        load_operation_details;
        load_disruption_header;
        load_disruption_details;

        COMMIT;
        DBMS_OUTPUT.PUT_LINE('=== SILVER load OK (COMMIT) ===');
    EXCEPTION
        WHEN OTHERS THEN
            ROLLBACK;
            DBMS_OUTPUT.PUT_LINE('=== SILVER load ERROR - ROLLBACK: ' || SQLERRM);
            RAISE;
    END load_all;

END pkg_silver_load;
/


grant execute on SILVER.pkg_silver_load to DEV_APP;