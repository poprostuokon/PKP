-- =====================================================================
-- MAINTENANCE.PKG_MAINTENANCE
-- Kompresja partycji przez MOVE. Generator wypelnia kolejke gotowymi
-- ALTER-ami, executor je odpala (blad jednej komendy nie przerywa reszty).
-- AUTHID CURRENT_USER -> dziala z prawami DEV_APP (ALTER ANY TABLE).
-- =====================================================================
create or replace PACKAGE             pkg_maintenance AUTHID CURRENT_USER AS

    PROCEDURE gen_compress_queue(
        p_schema    IN VARCHAR2,
        p_table     IN VARCHAR2,
        p_grain     IN VARCHAR2,                 -- 'DAY' | 'MONTH'
        p_days      IN NUMBER   DEFAULT 3,
        p_compress  IN VARCHAR2 DEFAULT 'QUERY HIGH'
    );

    PROCEDURE run_compress_queue;
    
    PROCEDURE clear_queue;

END pkg_maintenance;
/



create or replace PACKAGE BODY             pkg_maintenance AS

    ----------------------------------------------------------------------
    PROCEDURE gen_compress_queue(
        p_schema    IN VARCHAR2,
        p_table     IN VARCHAR2,
        p_grain     IN VARCHAR2,
        p_days      IN NUMBER   DEFAULT 3,
        p_compress  IN VARCHAR2 DEFAULT 'QUERY HIGH'
    ) IS
        v_sch       VARCHAR2(128) := UPPER(p_schema);
        v_tab       VARCHAR2(128) := UPPER(p_table);
        v_grain     VARCHAR2(10)  := UPPER(p_grain);
        v_key_type  VARCHAR2(128);
        v_comp      VARCHAR2(100);
        v_today     DATE := TRUNC(CAST(maintenance.pkg_tool.f_now_warsaw AS DATE));
        v_win_from  NUMBER;
        v_win_to    NUMBER;
        v_hv        VARCHAR2(4000);
        v_bnd_date  DATE;
        v_bnd_num   NUMBER;
        v_data_num  NUMBER;                       -- YYYYMMDD lub YYYYMM danych partycji
        v_cmd       VARCHAR2(1000);
        v_cnt       PLS_INTEGER := 0;
    BEGIN
        -- walidacja wejscia
        IF v_grain NOT IN ('DAY','MONTH') THEN
            raise_application_error(-20010, 'p_grain musi byc DAY lub MONTH');
        END IF;
        IF p_days IS NULL OR p_days < 1 THEN
            raise_application_error(-20011, 'p_days musi byc >= 1');
        END IF;

        -- klauzula kompresji wg rodziny (punkt: jedna proc, HCC + row)
        v_comp := CASE UPPER(p_compress)
                    WHEN 'QUERY HIGH'   THEN 'COLUMN STORE COMPRESS FOR QUERY HIGH'
                    WHEN 'QUERY LOW'    THEN 'COLUMN STORE COMPRESS FOR QUERY LOW'
                    WHEN 'ARCHIVE HIGH' THEN 'COLUMN STORE COMPRESS FOR ARCHIVE HIGH'
                    WHEN 'ARCHIVE LOW'  THEN 'COLUMN STORE COMPRESS FOR ARCHIVE LOW'
                    WHEN 'ADVANCED'     THEN 'ROW STORE COMPRESS ADVANCED'
                    WHEN 'BASIC'        THEN 'ROW STORE COMPRESS BASIC'
                  END;
        IF v_comp IS NULL THEN
            raise_application_error(-20012, 'p_compress niepoprawny: '||p_compress);
        END IF;

        -- typ klucza partycji (A: auto-detekcja ze slownika)
        SELECT c.data_type
          INTO v_key_type
          FROM all_tab_columns c
         WHERE c.owner = v_sch AND c.table_name = v_tab
           AND c.column_name = (
                 SELECT k.column_name FROM all_part_key_columns k
                  WHERE k.owner = v_sch AND k.name = v_tab
                    AND k.column_position = 1);

        -- okno: ostatnie N dni WLACZNIE z dzis (czas Warszawy)
        IF v_grain = 'DAY' THEN
            v_win_from := TO_NUMBER(TO_CHAR(v_today-(p_days-1),'YYYYMMDD'));
            v_win_to   := TO_NUMBER(TO_CHAR(v_today,          'YYYYMMDD'));
        ELSE
            v_win_from := TO_NUMBER(TO_CHAR(v_today-(p_days-1),'YYYYMM'));
            v_win_to   := TO_NUMBER(TO_CHAR(v_today,          'YYYYMM'));
        END IF;


        -- iterujemy TYLKO istniejace partycje (istnieje <=> ma dane)
        FOR rec IN (
            SELECT partition_name, high_value_clob
              FROM all_tab_partitions
             WHERE table_owner = v_sch AND table_name = v_tab
               AND partition_name <> 'P_ANCHOR'
        ) LOOP
            v_hv := SUBSTR(rec.high_value_clob,1,4000);

            -- wartosc danych = HIGH_VALUE - 1
            IF v_key_type = 'DATE' THEN
                EXECUTE IMMEDIATE 'SELECT ('||v_hv||') FROM dual' INTO v_bnd_date;
                v_data_num := TO_NUMBER(TO_CHAR(v_bnd_date-1,
                                 CASE WHEN v_grain='DAY' THEN 'YYYYMMDD' ELSE 'YYYYMM' END));
            ELSE
                EXECUTE IMMEDIATE 'SELECT ('||v_hv||') FROM dual' INTO v_bnd_num;
                v_data_num := v_bnd_num - 1;
            END IF;

            IF v_data_num BETWEEN v_win_from AND v_win_to THEN
                v_cmd := 'ALTER TABLE "'||v_sch||'"."'||v_tab||'" '
                       ||'MOVE PARTITION "'||rec.partition_name||'" '
                       ||v_comp||' ONLINE UPDATE INDEXES';
                INSERT INTO maintenance.sql_exec_queue(sql_) VALUES (v_cmd);
                v_cnt := v_cnt + 1;
            END IF;
        END LOOP;

        COMMIT;
        DBMS_OUTPUT.PUT_LINE('gen_compress_queue: '||v_cnt||' partycji do kompresji '
                             ||'('||v_sch||'.'||v_tab||', '||v_grain||', okno '
                             ||v_win_from||'-'||v_win_to||')');
    END gen_compress_queue;

    ----------------------------------------------------------------------
    PROCEDURE run_compress_queue IS
        v_done  PLS_INTEGER := 0;
        v_fail  PLS_INTEGER := 0;
        v_err   VARCHAR2(4000); 
    BEGIN
        FOR rec IN (SELECT sql_ FROM maintenance.sql_exec_queue) LOOP
            BEGIN
                EXECUTE IMMEDIATE rec.sql_;           -- DDL: auto-commit
                INSERT INTO maintenance.sql_exec_queue_log(sql_, status, error_msg)
                VALUES (rec.sql_, 'DONE', NULL);
                COMMIT;
                v_done := v_done + 1;
            EXCEPTION
                WHEN OTHERS THEN
                    INSERT INTO maintenance.sql_exec_queue_log(sql_, status, error_msg)
                    VALUES (rec.sql_, 'FAILED', v_err);
                    COMMIT;
                    v_fail := v_fail + 1;
            END;
        END LOOP;

        DBMS_OUTPUT.PUT_LINE('run_compress_queue: DONE='||v_done||', FAILED='||v_fail);

        IF v_fail > 0 THEN
            raise_application_error(-20020,
                v_fail||' komend nie powiodlo sie (szczegoly: sql_exec_queue_log)');
        END IF;
    END run_compress_queue;
    
    
    ----------------------------------------------------------------------
    PROCEDURE clear_queue IS
    BEGIN
        EXECUTE IMMEDIATE 'TRUNCATE TABLE maintenance.sql_exec_queue';
    END clear_queue;

END pkg_maintenance;
/

grant execute on maintenance.pkg_maintenance to DEV_APP;