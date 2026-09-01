-- =====================================================================
-- PKG_GOLD_LOAD - ladowanie wymiarow warstwy GOLD ze SILVER.
--
-- Konwencje (spojne z pkg_silver_load):
--   * wymiary generowane (d_date, d_hour) -> INSERT idempotentny (WHERE NOT EXISTS)
--   * wymiary ze silver                    -> MERGE (upsert) + no-op skip (DECODE null-safe)
--   * d_train_type                         -> SCD2 (wersje przewoznika z def_carrier)
--   * loaded_at -> pkg_tool.f_now_warsaw
--   * bez prefiksow schematow -> przez SYNONIMY
--   * log_rows -> nazwa kroku z UTL_CALL_STACK
--
-- Owner: GOLD. AUTHID DEFINER. load_dimensions: DISABLE PARALLEL DML + jeden COMMIT.
-- Repeatable migration Flyway.
-- =====================================================================

-- ---- granty (synonimy nie nadaja uprawnien) ----
grant execute on maintenance.pkg_tool               to gold;
grant select  on silver.def_station                 to gold;
grant select  on silver.def_city                    to gold;
grant select  on silver.schedule_header            	to gold;
grant select  on silver.schedule_details            to gold;
grant select  on silver.def_commercial_category     to gold;
grant select  on silver.def_carrier                 to gold;
grant select  on silver.def_train_status            to gold;
grant select  on silver.def_disruption_cause        to gold;
grant select on silver.operation_header  			to gold;
grant select on silver.operation_details 			to gold;
grant select on silver.disruption_header  			to gold;
grant select on silver.disruption_details 			to gold;



-- ---- synonimy: kod pakietu bez prefiksow schematow ----
CREATE OR REPLACE SYNONYM gold.pkg_tool                 FOR maintenance.pkg_tool;
CREATE OR REPLACE SYNONYM gold.def_station             	FOR silver.def_station;
CREATE OR REPLACE SYNONYM gold.def_city                	FOR silver.def_city;
CREATE OR REPLACE SYNONYM gold.schedule_header         	FOR silver.schedule_header;
CREATE OR REPLACE SYNONYM gold.schedule_details        	FOR silver.schedule_details;
CREATE OR REPLACE SYNONYM gold.def_commercial_category 	FOR silver.def_commercial_category;
CREATE OR REPLACE SYNONYM gold.def_carrier             	FOR silver.def_carrier;
CREATE OR REPLACE SYNONYM gold.def_train_status        	FOR silver.def_train_status;
CREATE OR REPLACE SYNONYM gold.def_disruption_cause    	FOR silver.def_disruption_cause;
CREATE OR REPLACE SYNONYM gold.operation_header  		FOR silver.operation_header;
CREATE OR REPLACE SYNONYM gold.operation_details 		FOR silver.operation_details;
CREATE OR REPLACE SYNONYM gold.disruption_header  		FOR silver.disruption_header;
CREATE OR REPLACE SYNONYM gold.disruption_details 		FOR silver.disruption_details;



CREATE OR REPLACE PACKAGE gold.pkg_gold_load AUTHID DEFINER AS
    PROCEDURE load_d_date;
    PROCEDURE load_d_hour;
    PROCEDURE load_d_station;
    PROCEDURE load_d_route (p_full_load IN BOOLEAN DEFAULT FALSE);
    PROCEDURE load_d_train_type;
    PROCEDURE load_d_train_status;
    PROCEDURE load_d_disruption_cause;
    PROCEDURE load_dimensions;
	
    PROCEDURE load_f_train_run_daily(p_days IN NUMBER DEFAULT 3);
	PROCEDURE load_f_train_stop_daily(p_days IN NUMBER DEFAULT 3);
	PROCEDURE load_f_train_disruption_daily(p_days IN NUMBER DEFAULT 3);
    PROCEDURE load_facts_daily (p_days IN NUMBER DEFAULT 3);
	
END pkg_gold_load;
/



create or replace PACKAGE BODY GOLD.pkg_gold_load AS
    
    
    /**********************************************************************************************************/
    /***** log_rows  *****/
    /**********************************************************************************************************/
    -- log do DBMS_OUTPUT; nazwa kroku = wolajaca procedura (z call stacku)
    PROCEDURE log_rows(p_rows IN NUMBER) IS
        v_full VARCHAR2(200);
        v_step VARCHAR2(128);
    BEGIN
        v_full := UTL_CALL_STACK.concatenate_subprogram( UTL_CALL_STACK.subprogram(2) );
        v_step := LOWER( SUBSTR(v_full, INSTR(v_full, '.') + 1) );
        DBMS_OUTPUT.PUT_LINE( RPAD(v_step, 32) || ' -> ' || p_rows || ' wierszy' );
    END log_rows;

    -- ================= WYMIARY GENEROWANE =================
    
    
    /**********************************************************************************************************/
    /***** load_d_date  *****/
    /**********************************************************************************************************/
    PROCEDURE load_d_date IS
        v_start DATE := TRUNC(SYSDATE, 'YYYY');                     -- 1 stycznia roku biezacego
        v_end   DATE := ADD_MONTHS(TRUNC(SYSDATE,'YYYY'), 24) - 1;  -- 31 grudnia roku przyszlego
    BEGIN
        INSERT INTO d_date (
            id, full_date, year, quarter, month, month_name,
            day, day_of_week, day_name, iso_week, is_weekend, loaded_at
        )
        SELECT
            TO_NUMBER(TO_CHAR(g.d,'YYYYMMDD')),
            g.d,
            EXTRACT(YEAR  FROM g.d),
            TO_NUMBER(TO_CHAR(g.d,'Q')),
            EXTRACT(MONTH FROM g.d),
            INITCAP(TRIM(TO_CHAR(g.d,'fmMonth','NLS_DATE_LANGUAGE=POLISH'))),
            EXTRACT(DAY   FROM g.d),
            (TRUNC(g.d) - TRUNC(g.d,'IW') + 1),                    -- 1=pon ... 7=niedz
            INITCAP(TRIM(TO_CHAR(g.d,'fmDay','NLS_DATE_LANGUAGE=POLISH'))),
            TO_NUMBER(TO_CHAR(g.d,'IW')),
            CASE WHEN (TRUNC(g.d) - TRUNC(g.d,'IW') + 1) IN (6,7) THEN 'T' ELSE 'N' END,
            pkg_tool.f_now_warsaw
        FROM (
            SELECT v_start + (LEVEL - 1) AS d
            FROM dual
            CONNECT BY LEVEL <= (v_end - v_start + 1)
        ) g
        WHERE NOT EXISTS (
            SELECT 1 FROM d_date x WHERE x.id = TO_NUMBER(TO_CHAR(g.d,'YYYYMMDD'))
        );
        log_rows(SQL%ROWCOUNT);
    END load_d_date;

    
    
    /**********************************************************************************************************/
    /***** load_d_hour  *****/
    /**********************************************************************************************************/
    PROCEDURE load_d_hour IS
    BEGIN
        INSERT INTO d_hour (id, hour_label, part_of_day, loaded_at)
        SELECT g.h,
               LPAD(g.h,2,'0') || ':00-' || LPAD(g.h,2,'0') || ':59',
               CASE
                   WHEN g.h BETWEEN 0  AND 4  THEN 'noc'
                   WHEN g.h BETWEEN 5  AND 8  THEN 'szczyt poranny'
                   WHEN g.h BETWEEN 9  AND 14 THEN 'dzień'
                   WHEN g.h BETWEEN 15 AND 18 THEN 'szczyt popołudniowy'
                   ELSE 'wieczór'
               END,
               pkg_tool.f_now_warsaw
        FROM ( SELECT LEVEL - 1 AS h FROM dual CONNECT BY LEVEL <= 24 ) g
        WHERE NOT EXISTS ( SELECT 1 FROM d_hour x WHERE x.id = g.h );
        log_rows(SQL%ROWCOUNT);
    END load_d_hour;





    -- ================= WYMIARY ZE SILVER (MERGE + no-op skip) =================
    
    /**********************************************************************************************************/
    /***** load_d_station  *****/
    /**********************************************************************************************************/
    PROCEDURE load_d_station IS
    BEGIN
        MERGE INTO d_station d
        USING (
            select s.id, s.name as station_name, c.name as city_name
            from   def_station s
            left join def_city c on c.id = s.dcit_id
        ) s
        ON (d.id = s.id)
        WHEN MATCHED THEN UPDATE SET
            d.station_name = s.station_name, d.city_name = s.city_name, d.loaded_at = pkg_tool.f_now_warsaw
            WHERE DECODE(d.station_name, s.station_name, 0, 1) = 1
               OR DECODE(d.city_name,    s.city_name,    0, 1) = 1
        WHEN NOT MATCHED THEN
            INSERT (id, station_name, city_name, loaded_at)
            VALUES (s.id, s.station_name, s.city_name, pkg_tool.f_now_warsaw);
        log_rows(SQL%ROWCOUNT);
    END load_d_station;



    /**********************************************************************************************************/
    /***** load_d_route  *****/
    /**********************************************************************************************************/
    PROCEDURE load_d_route(p_full_load IN BOOLEAN DEFAULT FALSE) IS
    BEGIN
        IF p_full_load THEN
            -- PELNY: cala historia rozkladu (jednorazowo). Skanuje cale schedule_details.
            MERGE INTO d_route d
            USING (
                with ep as (
                    select schedule_id, order_id,
                           min(order_number) as min_on,
                           max(order_number) as max_on
                    from   schedule_details
                    group by schedule_id, order_id
                )
                select distinct f.dsta_id as from_station_id, t.dsta_id as to_station_id
                from   ep
                join   schedule_details f
                       on f.schedule_id = ep.schedule_id and f.order_id = ep.order_id and f.order_number = ep.min_on
                join   schedule_details t
                       on t.schedule_id = ep.schedule_id and t.order_id = ep.order_id and t.order_number = ep.max_on
            ) s
            ON (d.from_station_id = s.from_station_id AND d.to_station_id = s.to_station_id)
            WHEN NOT MATCHED THEN
                INSERT (from_station_id, to_station_id, loaded_at)
                VALUES (s.from_station_id, s.to_station_id, pkg_tool.f_now_warsaw);
        ELSE
            -- DZIENNY (domyslny): tylko kursy jadace DZIS - driver ze schedule_header,
            -- join do schedule_details po (schedule_id, order_id) => bez skanu calej tabeli.
            MERGE INTO d_route d
            USING (
                with ord as (
                    select distinct schedule_id, order_id
                    from   schedule_header
                    where  operating_date = trunc(sysdate)
                ),
                ep as (
                    select sd.schedule_id, sd.order_id,
                           min(sd.order_number) as min_on,
                           max(sd.order_number) as max_on
                    from   schedule_details sd
                    join   ord on ord.schedule_id = sd.schedule_id and ord.order_id = sd.order_id
                    group by sd.schedule_id, sd.order_id
                )
                select distinct f.dsta_id as from_station_id, t.dsta_id as to_station_id
                from   ep
                join   schedule_details f
                       on f.schedule_id = ep.schedule_id and f.order_id = ep.order_id and f.order_number = ep.min_on
                join   schedule_details t
                       on t.schedule_id = ep.schedule_id and t.order_id = ep.order_id and t.order_number = ep.max_on
            ) s
            ON (d.from_station_id = s.from_station_id AND d.to_station_id = s.to_station_id)
            WHEN NOT MATCHED THEN
                INSERT (from_station_id, to_station_id, loaded_at)
                VALUES (s.from_station_id, s.to_station_id, pkg_tool.f_now_warsaw);
        END IF;

        log_rows(SQL%ROWCOUNT);
    END load_d_route;

    
    
    
    /**********************************************************************************************************/
    /***** load_d_train_type  *****/
    /**********************************************************************************************************/
    PROCEDURE load_d_train_type IS
    BEGIN
        -- SCD2: kazda kategoria x kazda wersja przewoznika (valid_from/valid_to z def_carrier)
        MERGE INTO d_train_type d
        USING (
            select cc.code                as category_code,
                   cc.name                as category_name,
                   cc.speed_category_code as speed_category_code,
                   ca.code                as carrier_code,
                   ca.name                as carrier_name,
                   ca.valid_from          as valid_from,
                   ca.valid_to            as valid_to
            from   def_commercial_category cc
            join   def_carrier ca on ca.code = cc.carrier_code
        ) s
        ON (    d.category_code = s.category_code
            AND d.carrier_code  = s.carrier_code
            AND d.valid_from    = s.valid_from )
        WHEN MATCHED THEN UPDATE SET
            d.category_name = s.category_name, d.speed_category_code = s.speed_category_code,
            d.carrier_name  = s.carrier_name,  d.valid_to = s.valid_to, d.loaded_at = pkg_tool.f_now_warsaw
            WHERE DECODE(d.category_name,       s.category_name,       0, 1) = 1
               OR DECODE(d.speed_category_code, s.speed_category_code, 0, 1) = 1
               OR DECODE(d.carrier_name,        s.carrier_name,        0, 1) = 1
               OR DECODE(d.valid_to,            s.valid_to,            0, 1) = 1
        WHEN NOT MATCHED THEN
            INSERT (category_code, category_name, speed_category_code, carrier_code, carrier_name, valid_from, valid_to, loaded_at)
            VALUES (s.category_code, s.category_name, s.speed_category_code, s.carrier_code, s.carrier_name, s.valid_from, s.valid_to, pkg_tool.f_now_warsaw);
        log_rows(SQL%ROWCOUNT);
    END load_d_train_type;

    
    
    
    /**********************************************************************************************************/
    /***** load_d_train_status  *****/
    /**********************************************************************************************************/
    PROCEDURE load_d_train_status IS
    BEGIN
        MERGE INTO d_train_status d
        USING (
            select code as status_code, name as status_name from def_train_status
        ) s
        ON (d.status_code = s.status_code)
        WHEN MATCHED THEN UPDATE SET d.status_name = s.status_name, d.loaded_at = pkg_tool.f_now_warsaw
            WHERE DECODE(d.status_name, s.status_name, 0, 1) = 1
        WHEN NOT MATCHED THEN
            INSERT (status_code, status_name, loaded_at)
            VALUES (s.status_code, s.status_name, pkg_tool.f_now_warsaw);
        log_rows(SQL%ROWCOUNT);
    END load_d_train_status;

    
    
    
    /**********************************************************************************************************/
    /***** load_d_disruption_cause  *****/
    /**********************************************************************************************************/
    PROCEDURE load_d_disruption_cause IS
    BEGIN
        MERGE INTO d_disruption_cause d
        USING (
            select code as cause_code, description as cause_name from def_disruption_cause
        ) s
        ON (d.cause_code = s.cause_code)
        WHEN MATCHED THEN UPDATE SET d.cause_name = s.cause_name, d.loaded_at = pkg_tool.f_now_warsaw
            WHERE DECODE(d.cause_name, s.cause_name, 0, 1) = 1
        WHEN NOT MATCHED THEN
            INSERT (cause_code, cause_name, loaded_at)
            VALUES (s.cause_code, s.cause_name, pkg_tool.f_now_warsaw);
        log_rows(SQL%ROWCOUNT);
    END load_d_disruption_cause;
    
    
    
    
    -- ================= FAKTY =================
    
    /**********************************************************************************************************/
    /***** load_f_train_run_daily  *****/
    /**********************************************************************************************************/
    PROCEDURE load_f_train_run_daily(p_days IN NUMBER DEFAULT 3) IS
        v_from DATE;
        v_to   DATE;
    BEGIN
        EXECUTE IMMEDIATE 'ALTER SESSION DISABLE PARALLEL DML';   -- Autonomous: ORA-12839

        v_from := TRUNC(SYSDATE) - p_days;
        v_to   := TRUNC(SYSDATE) - 1;
        DELETE FROM f_train_run_daily
        WHERE date_id BETWEEN TO_NUMBER(TO_CHAR(v_from,'YYYYMMDD')) AND TO_NUMBER(TO_CHAR(v_to,  'YYYYMMDD'));

        INSERT INTO f_train_run_daily
            (date_id, route_id, train_type_id, status_id,
             runs_count, delayed_count, sum_terminal_delay_min, sum_delayed_delay_min, max_terminal_delay_min, loaded_at)
        WITH runs AS (       -- jeden wiersz na kurs w oknie + atrybuty z rozkladu
            select oh.id as ophe_id,
                   oh.operating_date,
                   to_number(to_char(oh.operating_date,'YYYYMMDD')) as date_id,
                   oh.schedule_id, oh.order_id, oh.train_status,
                   sh.category_code, sh.carrier_code
            from operation_header oh
            join schedule_header sh
              on  sh.operating_date = oh.operating_date
              and sh.schedule_id    = oh.schedule_id
              and sh.order_id       = oh.order_id
              and sh.train_order_id = oh.train_order_id
            where oh.operating_date between v_from and v_to
        ),
        ep AS (              -- endpointy rozkladu tylko dla kursow z okna
            select sd.schedule_id, sd.order_id,
                   min(sd.order_number) as min_on, max(sd.order_number) as max_on
            from schedule_details sd
            where (sd.schedule_id, sd.order_id) in (select schedule_id, order_id from runs)
            group by sd.schedule_id, sd.order_id
        ),
        route_pair AS (      -- from/to stacja per (schedule_id, order_id)
            select ep.schedule_id, ep.order_id, f.dsta_id as from_station_id, t.dsta_id as to_station_id
            from ep
            join schedule_details f on f.schedule_id=ep.schedule_id and f.order_id=ep.order_id and f.order_number=ep.min_on
            join schedule_details t on t.schedule_id=ep.schedule_id and t.order_id=ep.order_id and t.order_number=ep.max_on
        ),
        term AS (
            select ophe_id, nvl(arrival_delay_min, 0) as terminal_delay
            from operation_details
            where is_confirmed = 1
            qualify row_number() over (partition by ophe_id order by actual_sequence desc) = 1
        ),
        resolved AS (        -- mapowanie na klucze wymiarow
            select r.date_id,
                   dr.id                    as route_id,
                   coalesce(ttm.id, ttc.id) as train_type_id,   -- SCD2 po dacie + fallback biezaca
                   dts.id                   as status_id,
                   tm.terminal_delay
            from runs r
            left join term       tm on tm.ophe_id = r.ophe_id
            left join route_pair rp on rp.schedule_id = r.schedule_id and rp.order_id = r.order_id
            join d_route dr on dr.from_station_id = rp.from_station_id and dr.to_station_id = rp.to_station_id
            left join d_train_type ttm
                   on ttm.category_code = r.category_code and ttm.carrier_code = r.carrier_code
                  and r.operating_date between ttm.valid_from and ttm.valid_to
            left join d_train_type ttc
                   on ttc.category_code = r.category_code and ttc.carrier_code = r.carrier_code
                  and ttc.valid_to = DATE '2999-12-31'
            join d_train_status dts on dts.status_code = r.train_status
        )
        select date_id, route_id, train_type_id, status_id,
               count(*)                                                                             as runs_count,
               case when count(terminal_delay) = 0 then null
                    else sum(case when terminal_delay >= 6 then 1 else 0 end) end                   as delayed_count,
               sum(terminal_delay)                                                                  as sum_terminal_delay_min,
               case when count(terminal_delay) = 0 then null
                    else nvl(sum(case when terminal_delay >= 6 then terminal_delay end), 0) end     as sum_delayed_delay_min,
               max(terminal_delay)                                                                  as max_terminal_delay_min,
               pkg_tool.f_now_warsaw
        from resolved
        where train_type_id is not null       -- nie wpuszczamy kursow bez zmapowanego typu (NOT NULL w fakcie)
        group by date_id, route_id, train_type_id, status_id;

        log_rows(SQL%ROWCOUNT);
        COMMIT;
    EXCEPTION
        WHEN OTHERS THEN
            ROLLBACK;
            DBMS_OUTPUT.PUT_LINE('load_f_train_run_daily ERROR - ROLLBACK: ' || SQLERRM);
            RAISE;
    END load_f_train_run_daily;
    
    
    
    /**********************************************************************************************************/
    /***** load_f_train_stop_daily  *****/
    /**********************************************************************************************************/
    PROCEDURE load_f_train_stop_daily(p_days IN NUMBER DEFAULT 3) IS
        v_from DATE;
        v_to   DATE;
    BEGIN
        EXECUTE IMMEDIATE 'ALTER SESSION DISABLE PARALLEL DML';

        v_from := TRUNC(SYSDATE) - p_days;
        v_to   := TRUNC(SYSDATE) - 1;
        DELETE FROM f_train_stop_daily
         WHERE date_id BETWEEN TO_NUMBER(TO_CHAR(v_from,'YYYYMMDD'))
                           AND TO_NUMBER(TO_CHAR(v_to,  'YYYYMMDD'));

        INSERT INTO f_train_stop_daily
            (date_id, route_id, train_type_id, station_id, hour_id,
             arrivals_count, arrivals_on_time, arrivals_delayed,
             sum_arrival_delay_min, sum_delayed_delay_min, max_arrival_delay_min, cancelled_count, loaded_at)
        WITH runs AS (            -- kursy w oknie + atrybuty z rozkladu
            select oh.id as ophe_id,
                   oh.operating_date,
                   to_number(to_char(oh.operating_date,'YYYYMMDD')) as date_id,
                   oh.schedule_id, oh.order_id,
                   sh.category_code, sh.carrier_code
            from operation_header oh
            join schedule_header sh
              on  sh.operating_date = oh.operating_date and sh.schedule_id = oh.schedule_id
              and sh.order_id       = oh.order_id       and sh.train_order_id = oh.train_order_id
            where oh.operating_date between v_from and v_to
        ),
        ep AS (
            select sd.schedule_id, sd.order_id,
                   min(sd.order_number) as min_on, max(sd.order_number) as max_on
            from schedule_details sd
            where (sd.schedule_id, sd.order_id) in (select schedule_id, order_id from runs)
            group by sd.schedule_id, sd.order_id
        ),
        route_pair AS (
            select ep.schedule_id, ep.order_id, f.dsta_id as from_station_id, t.dsta_id as to_station_id
            from ep
            join schedule_details f on f.schedule_id=ep.schedule_id and f.order_id=ep.order_id and f.order_number=ep.min_on
            join schedule_details t on t.schedule_id=ep.schedule_id and t.order_id=ep.order_id and t.order_number=ep.max_on
        ),
        stops AS (                -- przystanki (nie-origin) z planowa godzina przyjazdu
            select r.date_id, r.schedule_id, r.order_id, r.operating_date,
                   r.category_code, r.carrier_code,
                   od.dsta_id                              as station_id,
                   to_number(substr(sd.arrival_time,1,2)) as hour_id,
                   case when od.is_confirmed and not od.is_cancelled then 1 else 0 end as is_arrival,
                   case when od.is_confirmed and not od.is_cancelled then nvl(od.arrival_delay_min,0) end as eff_delay,
                   case when od.is_cancelled then 1 else 0 end as is_cancelled
            from runs r
            join operation_details od on od.ophe_id = r.ophe_id
            join schedule_details sd
              on sd.schedule_id = r.schedule_id and sd.order_id = r.order_id
             and sd.order_number = od.planned_sequence
            where sd.arrival_time is not null              -- pomija origin (start bez przyjazdu)
        ),
        resolved AS (
            select s.date_id,
                   dr.id                    as route_id,
                   coalesce(ttm.id, ttc.id) as train_type_id,
                   s.station_id,
                   s.hour_id,
                   s.is_arrival, s.eff_delay, s.is_cancelled
            from stops s
            left join route_pair rp on rp.schedule_id = s.schedule_id and rp.order_id = s.order_id
            join d_route dr on dr.from_station_id = rp.from_station_id and dr.to_station_id = rp.to_station_id
            left join d_train_type ttm
                   on ttm.category_code = s.category_code and ttm.carrier_code = s.carrier_code
                  and s.operating_date between ttm.valid_from and ttm.valid_to
            left join d_train_type ttc
                   on ttc.category_code = s.category_code and ttc.carrier_code = s.carrier_code
                  and ttc.valid_to = DATE '2999-12-31'
        )
        select date_id, route_id, train_type_id, station_id, hour_id,
               sum(is_arrival)                                                        as arrivals_count,
               sum(case when is_arrival = 1 and eff_delay <= 5 then 1 else 0 end)     as arrivals_on_time,
               sum(case when is_arrival = 1 and eff_delay >= 6 then 1 else 0 end)     as arrivals_delayed,
               sum(eff_delay)                                                         as sum_arrival_delay_min,
               case when sum(is_arrival) = 0 then null
                    else nvl(sum(case when eff_delay >= 6 then eff_delay end), 0) end as sum_delayed_delay_min,
               max(eff_delay)                                                         as max_arrival_delay_min,
               sum(is_cancelled)                                                      as cancelled_count,
               pkg_tool.f_now_warsaw
        from resolved
        where train_type_id is not null
        group by date_id, route_id, train_type_id, station_id, hour_id;

        log_rows(SQL%ROWCOUNT);
        COMMIT;
    EXCEPTION
        WHEN OTHERS THEN
            ROLLBACK;
            DBMS_OUTPUT.PUT_LINE('load_f_train_stop_daily ERROR - ROLLBACK: ' || SQLERRM);
            RAISE;
    END load_f_train_stop_daily;



    /**********************************************************************************************************/
    /***** load_f_train_disruption_daily  *****/
    /**********************************************************************************************************/
    PROCEDURE load_f_train_disruption_daily(p_days IN NUMBER DEFAULT 3) IS
        v_from DATE;
        v_to   DATE;
    BEGIN
        EXECUTE IMMEDIATE 'ALTER SESSION DISABLE PARALLEL DML';

        v_from := TRUNC(SYSDATE) - p_days;
        v_to   := TRUNC(SYSDATE) - 1;
        DELETE FROM f_train_disruption_daily
         WHERE date_id BETWEEN TO_NUMBER(TO_CHAR(v_from,'YYYYMMDD'))
                           AND TO_NUMBER(TO_CHAR(v_to,  'YYYYMMDD'));

        INSERT INTO f_train_disruption_daily
            (date_id, route_id, station_id, train_type_id, hour_id, cause_id, occurrences_count, loaded_at)
        WITH dd AS (          -- dotkniete przystanki w oknie
            select d.operating_date,
                   to_number(to_char(d.operating_date,'YYYYMMDD')) as date_id,
                   d.schedule_id, d.order_id, d.train_order_id,
                   d.dsta_id as station_id, d.sequence_number, d.dihe_id
            from disruption_details d
            where d.operating_date between v_from and v_to
        ),
        ep AS (
            select sd.schedule_id, sd.order_id,
                   min(sd.order_number) as min_on, max(sd.order_number) as max_on
            from schedule_details sd
            where (sd.schedule_id, sd.order_id) in (select schedule_id, order_id from dd)
            group by sd.schedule_id, sd.order_id
        ),
        route_pair AS (
            select ep.schedule_id, ep.order_id, f.dsta_id as from_station_id, t.dsta_id as to_station_id
            from ep
            join schedule_details f on f.schedule_id=ep.schedule_id and f.order_id=ep.order_id and f.order_number=ep.min_on
            join schedule_details t on t.schedule_id=ep.schedule_id and t.order_id=ep.order_id and t.order_number=ep.max_on
        ),
        resolved AS (
            select x.date_id,
                   dr.id                    as route_id,
                   x.station_id,
                   coalesce(ttm.id, ttc.id) as train_type_id,
                   to_number(substr(coalesce(sd.arrival_time, sd.departure_time),1,2)) as hour_id,
                   coalesce(dc_t.id, dc_m.id) as cause_id
            from dd x
            join schedule_header sh
              on  sh.operating_date = x.operating_date and sh.schedule_id = x.schedule_id
              and sh.order_id       = x.order_id       and sh.train_order_id = x.train_order_id
            join disruption_header dh on dh.id = x.dihe_id
            join schedule_details sd
              on sd.schedule_id = x.schedule_id and sd.order_id = x.order_id
             and sd.order_number = x.sequence_number
            left join route_pair rp on rp.schedule_id = x.schedule_id and rp.order_id = x.order_id
            join d_route dr on dr.from_station_id = rp.from_station_id and dr.to_station_id = rp.to_station_id
            left join d_train_type ttm
                   on ttm.category_code = sh.category_code and ttm.carrier_code = sh.carrier_code
                  and x.operating_date between ttm.valid_from and ttm.valid_to
            left join d_train_type ttc
                   on ttc.category_code = sh.category_code and ttc.carrier_code = sh.carrier_code
                  and ttc.valid_to = DATE '2999-12-31'
            left join d_disruption_cause dc_t on dc_t.cause_code = dh.disruption_type_code
            left join d_disruption_cause dc_m on dc_m.cause_code = dh.message
        )
        select date_id, route_id, station_id, train_type_id, hour_id, cause_id,
               count(*) as occurrences_count,
               pkg_tool.f_now_warsaw
        from resolved
        where train_type_id is not null
          and cause_id      is not null
          and hour_id       is not null
        group by date_id, route_id, station_id, train_type_id, hour_id, cause_id;

        log_rows(SQL%ROWCOUNT);
        COMMIT;
    EXCEPTION
        WHEN OTHERS THEN
            ROLLBACK;
            DBMS_OUTPUT.PUT_LINE('load_f_train_disruption_daily ERROR - ROLLBACK: ' || SQLERRM);
            RAISE;
    END load_f_train_disruption_daily;
    
    
    

    -- ================= ORCHESTRACJA =================

    PROCEDURE load_dimensions (p_route_full IN BOOLEAN DEFAULT FALSE) IS
    BEGIN
        DBMS_OUTPUT.PUT_LINE('=== GOLD dimensions load START ===');
        EXECUTE IMMEDIATE 'ALTER SESSION DISABLE PARALLEL DML';

        load_d_date;
        load_d_hour;
        load_d_station;
        load_d_route(p_route_full);
        load_d_train_type;
        load_d_train_status;
        load_d_disruption_cause;

        COMMIT;
        DBMS_OUTPUT.PUT_LINE('=== GOLD dimensions load OK (COMMIT) ===');
    EXCEPTION
        WHEN OTHERS THEN
            ROLLBACK;
            DBMS_OUTPUT.PUT_LINE('=== GOLD dimensions load ERROR - ROLLBACK: ' || SQLERRM);
            RAISE;
    END load_dimensions;
    
    
    
    PROCEDURE load_facts_daily (p_days IN NUMBER DEFAULT 3) IS
    BEGIN
        DBMS_OUTPUT.PUT_LINE('=== GOLD facts daily load START ===');
        EXECUTE IMMEDIATE 'ALTER SESSION DISABLE PARALLEL DML';

        load_f_train_run_daily(p_days);
        load_f_train_stop_daily(p_days);
        load_f_train_disruption_daily(p_days);

        COMMIT;
        DBMS_OUTPUT.PUT_LINE('=== GOLD facts daily load OK (COMMIT) ===');
    EXCEPTION
        WHEN OTHERS THEN
            ROLLBACK;
            DBMS_OUTPUT.PUT_LINE('=== GOLD facts daily load ERROR - ROLLBACK: ' || SQLERRM);
            RAISE;
    END load_facts_daily;

END pkg_gold_load;

/


grant execute on gold.pkg_gold_load to DEV_APP;