-- =============================================================================
-- maintenance.pkg_maintenance
-- -----------------------------------------------------------------------------
-- Pakiet utrzymaniowy warstwy bazodanowej: analizuje obiekty i generuje polecenia
-- reorganizacyjne do wspólnej kolejki (sql_exec_queue), po czym wykonuje je i
-- loguje wynik. Procedury:
--   * p_clear_queue            - czyści kolejkę poleceń,
--   * p_gen_compress_schema    - kompresja partycji w oknie czasowym wg progów,
--   * p_gen_table_move_schema  - MOVE tabel heap, które uległy fragmentacji,
--   * p_gen_index_rebuild_schema - REBUILD indeksów wg progów degradacji/kompresji,
--   * p_run_compress_queue     - uniwersalny executor kolejki DDL (z logowaniem).
-- Progi (rozmiar, % pełnych bloków, PCTSAVE, del_pct) sterowane parametrami.
-- =============================================================================

create or replace PACKAGE maintenance.pkg_maintenance AUTHID CURRENT_USER AS

    PROCEDURE p_clear_queue;

    PROCEDURE p_gen_compress_schema(
        p_schema     IN VARCHAR2,
        p_days       IN NUMBER   DEFAULT 3,
        p_compress   IN VARCHAR2 DEFAULT 'QUERY HIGH',
        p_min_mb     IN NUMBER   DEFAULT 16,
        p_min_used   IN NUMBER   DEFAULT 50
    );
	
	PROCEDURE p_gen_table_move_schema(
        p_schema     IN VARCHAR2,
        p_min_mb     IN NUMBER DEFAULT 8,    -- pomijaj male tabele
        p_max_full   IN NUMBER DEFAULT 50    -- MOVE gdy % pelnych blokow < tego (rozlazla)
    );
    
    PROCEDURE p_gen_index_rebuild_schema(
        p_schema     IN VARCHAR2,
        p_min_pct    IN NUMBER DEFAULT 15,   -- prog PCTSAVE (kompresja)
        p_min_del    IN NUMBER DEFAULT 15    -- prog del_pct (degradacja)
    );

    PROCEDURE p_run_compress_queue;

END pkg_maintenance;
/



create or replace PACKAGE BODY maintenance.pkg_maintenance AS

    PROCEDURE p_clear_queue IS
    BEGIN
        EXECUTE IMMEDIATE 'TRUNCATE TABLE maintenance.sql_exec_queue';
    END p_clear_queue;

    -- % blokow niepustych; NULL gdy sie nie da (brak ANALYZE ANY -> prog gestosci pominiety)
    FUNCTION f_used_pct(p_sch VARCHAR2, p_tab VARCHAR2, p_part VARCHAR2) RETURN NUMBER IS
        unf NUMBER; unfb NUMBER; f1 NUMBER; f1b NUMBER; f2 NUMBER; f2b NUMBER;
        f3 NUMBER; f3b NUMBER; f4 NUMBER; f4b NUMBER; fb NUMBER; fbb NUMBER;
        used NUMBER; tot NUMBER;
    BEGIN
        DBMS_SPACE.SPACE_USAGE(p_sch,p_tab,'TABLE PARTITION',
            unf,unfb,f1,f1b,f2,f2b,f3,f3b,f4,f4b,fb,fbb,p_part);
        used := fb+f1+f2+f3+f4; tot := used+unf;
        IF tot=0 THEN RETURN NULL; END IF;
        RETURN ROUND(100*used/tot,1);
    EXCEPTION WHEN OTHERS THEN RETURN NULL;
    END f_used_pct;

    PROCEDURE p_gen_compress_schema(
        p_schema     IN VARCHAR2,
        p_days       IN NUMBER   DEFAULT 3,
        p_compress   IN VARCHAR2 DEFAULT 'QUERY HIGH',
        p_min_mb     IN NUMBER   DEFAULT 16,
        p_min_used   IN NUMBER   DEFAULT 50
    ) IS
        v_sch      VARCHAR2(128) := UPPER(p_schema);
        v_comp     VARCHAR2(100);
        v_today    DATE := TRUNC(CAST(maintenance.pkg_tool.f_now_warsaw AS DATE));
        v_wd_from  NUMBER; v_wd_to NUMBER;   -- okno DAY (YYYYMMDD)
        v_wm_from  NUMBER; v_wm_to NUMBER;   -- okno MONTH (YYYYMM)
        v_key_type VARCHAR2(128);
        v_hv       VARCHAR2(4000);
        v_bnd_date DATE; v_bnd_num NUMBER; v_data NUMBER; v_grain VARCHAR2(5);
        v_used NUMBER; v_cmd VARCHAR2(1000);
        v_cnt PLS_INTEGER := 0; v_skip PLS_INTEGER := 0;
    BEGIN
        IF p_days IS NULL OR p_days<1 THEN
            raise_application_error(-20011,'p_days musi byc >= 1'); END IF;

        v_comp := CASE UPPER(p_compress)
            WHEN 'QUERY HIGH'   THEN 'COLUMN STORE COMPRESS FOR QUERY HIGH'
            WHEN 'QUERY LOW'    THEN 'COLUMN STORE COMPRESS FOR QUERY LOW'
            WHEN 'ARCHIVE HIGH' THEN 'COLUMN STORE COMPRESS FOR ARCHIVE HIGH'
            WHEN 'ARCHIVE LOW'  THEN 'COLUMN STORE COMPRESS FOR ARCHIVE LOW'
            WHEN 'ADVANCED'     THEN 'ROW STORE COMPRESS ADVANCED'
            WHEN 'BASIC'        THEN 'ROW STORE COMPRESS BASIC' END;
        IF v_comp IS NULL THEN
            raise_application_error(-20012,'p_compress niepoprawny: '||p_compress); END IF;

        v_wd_from := TO_NUMBER(TO_CHAR(v_today-(p_days-1),'YYYYMMDD'));
        v_wd_to   := TO_NUMBER(TO_CHAR(v_today,'YYYYMMDD'));
        v_wm_from := TO_NUMBER(TO_CHAR(v_today-(p_days-1),'YYYYMM'));
        v_wm_to   := TO_NUMBER(TO_CHAR(v_today,'YYYYMM'));

        -- wszystkie tabele partycjonowane w schemacie
        FOR t IN (
            SELECT table_name FROM dba_tables
             WHERE owner=v_sch AND partitioned='YES'
        ) LOOP
            -- typ klucza partycji tej tabeli
            BEGIN
                SELECT c.data_type INTO v_key_type
                  FROM dba_tab_columns c
                 WHERE c.owner=v_sch AND c.table_name=t.table_name
                   AND c.column_name=(SELECT k.column_name FROM dba_part_key_columns k
                                       WHERE k.owner=v_sch AND k.name=t.table_name
                                         AND k.object_type='TABLE' AND k.column_position=1);
            EXCEPTION WHEN NO_DATA_FOUND THEN CONTINUE; END;

            FOR rec IN (
                SELECT p.partition_name, p.high_value_clob, s.bytes/1024/1024 AS mb
                  FROM dba_tab_partitions p
                  JOIN dba_segments s
                    ON s.owner=p.table_owner AND s.segment_name=p.table_name
                   AND s.partition_name=p.partition_name AND s.segment_type='TABLE PARTITION'
                 WHERE p.table_owner=v_sch AND p.table_name=t.table_name
                   AND p.partition_name NOT IN ('P_ANCHOR','P_INIT')
            ) LOOP
                v_hv := SUBSTR(rec.high_value_clob,1,4000);

                IF v_key_type='DATE' THEN
                    EXECUTE IMMEDIATE 'SELECT ('||v_hv||') FROM dual' INTO v_bnd_date;
                    v_data  := TO_NUMBER(TO_CHAR(v_bnd_date-1,'YYYYMMDD'));
                    v_grain := 'DAY';
                ELSE
                    EXECUTE IMMEDIATE 'SELECT ('||v_hv||') FROM dual' INTO v_bnd_num;
                    v_data  := v_bnd_num-1;
                    v_grain := CASE WHEN v_data>=10000000 THEN 'DAY' ELSE 'MONTH' END;
                END IF;

                -- w oknie? (wg wykrytego grain)
                IF (v_grain='DAY'   AND v_data BETWEEN v_wd_from AND v_wd_to)
                OR (v_grain='MONTH' AND v_data BETWEEN v_wm_from AND v_wm_to) THEN
                    v_used := f_used_pct(v_sch,t.table_name,rec.partition_name);
                    IF ROUND(rec.mb,2) >= p_min_mb
                       AND (v_used IS NULL OR v_used >= p_min_used) THEN
                        v_cmd := 'ALTER TABLE "'||v_sch||'"."'||t.table_name||'" '
                               ||'MOVE PARTITION "'||rec.partition_name||'" '
                               ||v_comp||' UPDATE INDEXES';
                        INSERT INTO maintenance.sql_exec_queue(sql_) VALUES (v_cmd);
                        v_cnt := v_cnt+1;
                    ELSE
                        v_skip := v_skip+1;
                    END IF;
                END IF;
            END LOOP;
        END LOOP;

        COMMIT;
        DBMS_OUTPUT.PUT_LINE('gen_schema '||v_sch
            ||' | do kompresji='||v_cnt||' pominieto(prog)='||v_skip);
    END p_gen_compress_schema;
	
	
	
	-- % blokow PELNYCH wzgledem zaalokowanych (full-heavy = gesta, low = rozlazla)
    FUNCTION f_full_pct(p_sch VARCHAR2, p_tab VARCHAR2) RETURN NUMBER IS
        unf NUMBER; unfb NUMBER; f1 NUMBER; f1b NUMBER; f2 NUMBER; f2b NUMBER;
        f3 NUMBER; f3b NUMBER; f4 NUMBER; f4b NUMBER; fb NUMBER; fbb NUMBER;
        tot NUMBER;
    BEGIN
        DBMS_SPACE.SPACE_USAGE(p_sch,p_tab,'TABLE',
            unf,unfb,f1,f1b,f2,f2b,f3,f3b,f4,f4b,fb,fbb);
        tot := fb+f1+f2+f3+f4+unf;
        IF tot=0 THEN RETURN NULL; END IF;
        RETURN ROUND(100*fb/tot,1);
    EXCEPTION WHEN OTHERS THEN RETURN NULL;
    END f_full_pct;

    PROCEDURE p_gen_table_move_schema(
        p_schema     IN VARCHAR2,
        p_min_mb     IN NUMBER DEFAULT 8,
        p_max_full   IN NUMBER DEFAULT 50
    ) IS
        v_sch   VARCHAR2(128) := UPPER(p_schema);
        v_mb    NUMBER; v_full NUMBER;
        v_cmd   VARCHAR2(1000);
        v_cnt   PLS_INTEGER := 0; v_skip PLS_INTEGER := 0;
    BEGIN
        FOR t IN (
            SELECT tab.table_name, seg.bytes/1024/1024 AS mb
              FROM dba_tables tab
              JOIN dba_segments seg
                ON seg.owner=tab.owner AND seg.segment_name=tab.table_name
               AND seg.segment_type='TABLE'          -- tylko heap, nie partycjonowane
             WHERE tab.owner=v_sch
               AND tab.partitioned='NO'
               AND tab.temporary='N'
               AND tab.iot_type IS NULL              -- pomijaj IOT
        ) LOOP
            v_mb := ROUND(t.mb,2);
            IF v_mb < p_min_mb THEN
                v_skip := v_skip+1;
                CONTINUE;
            END IF;

            v_full := f_full_pct(v_sch, t.table_name);
            -- MOVE gdy rozlazla: malo pelnych blokow (lub nie da sie zmierzyc -> pomijamy dla bezpieczenstwa)
            IF v_full IS NOT NULL AND v_full < p_max_full THEN
                v_cmd := 'ALTER TABLE "'||v_sch||'"."'||t.table_name||'" '
                       ||'MOVE UPDATE INDEXES';
                INSERT INTO maintenance.sql_exec_queue(sql_) VALUES (v_cmd);
                v_cnt := v_cnt+1;
            ELSE
                v_skip := v_skip+1;
            END IF;
        END LOOP;

        COMMIT;
        DBMS_OUTPUT.PUT_LINE('gen_table_move '||v_sch
            ||' | do move='||v_cnt||' pominieto='||v_skip);
    END p_gen_table_move_schema;
	
    
    
    
    
    PROCEDURE p_gen_index_rebuild_schema(
        p_schema     IN VARCHAR2,
        p_min_pct    IN NUMBER DEFAULT 15,
        p_min_del    IN NUMBER DEFAULT 15
    ) IS
        v_sch      VARCHAR2(128) := UPPER(p_schema);
        v_pctsave  NUMBER;
        v_lf       NUMBER;
        v_del      NUMBER;
        v_delpct   NUMBER;
        v_cmd      VARCHAR2(1000);
        v_cnt      PLS_INTEGER := 0;
        v_skip     PLS_INTEGER := 0;
    BEGIN
        FOR ix IN (
            SELECT index_name
              FROM dba_indexes
             WHERE owner = v_sch
               AND index_type IN ('NORMAL','NORMAL/REV')
               AND partitioned = 'NO'                    -- tylko niepartycjonowane
               AND status = 'VALID'
               AND temporary = 'N'
        ) LOOP
            BEGIN
                EXECUTE IMMEDIATE
                    'ANALYZE INDEX "'||v_sch||'"."'||ix.index_name||'" VALIDATE STRUCTURE';

                SELECT opt_cmpr_pctsave, lf_rows, del_lf_rows
                  INTO v_pctsave, v_lf, v_del
                  FROM index_stats;

                v_delpct := CASE WHEN v_lf = 0 THEN 0
                                 ELSE ROUND(100*v_del/v_lf,1) END;

                -- kwalifikacja: save LUB delete powyzej progu
                IF v_pctsave >= p_min_pct OR v_delpct >= p_min_del THEN
                    v_cmd := 'ALTER INDEX "'||v_sch||'"."'||ix.index_name||'" '
                           ||'REBUILD COMPRESS ADVANCED LOW';
                    INSERT INTO maintenance.sql_exec_queue(sql_) VALUES (v_cmd);
                    v_cnt := v_cnt + 1;
                ELSE
                    v_skip := v_skip + 1;
                END IF;

            EXCEPTION
                WHEN OTHERS THEN
                    v_skip := v_skip + 1;   -- np. indeks ktorego nie da sie analyze
            END;
        END LOOP;

        COMMIT;
        DBMS_OUTPUT.PUT_LINE('gen_index '||v_sch
            ||' | do rebuildu='||v_cnt||' pominieto='||v_skip);
    END p_gen_index_rebuild_schema;
    
    
    

    PROCEDURE p_run_compress_queue IS
        v_done PLS_INTEGER:=0; v_fail PLS_INTEGER:=0; v_err VARCHAR2(4000);
    BEGIN
        FOR rec IN (SELECT sql_ FROM maintenance.sql_exec_queue) LOOP
            BEGIN
                EXECUTE IMMEDIATE rec.sql_;
                INSERT INTO maintenance.sql_exec_queue_log(sql_,status,error_msg)
                VALUES (rec.sql_,'DONE',NULL);
                COMMIT; v_done:=v_done+1;
            EXCEPTION WHEN OTHERS THEN
                v_err := SUBSTR(SQLERRM,1,4000);
                INSERT INTO maintenance.sql_exec_queue_log(sql_,status,error_msg)
                VALUES (rec.sql_,'FAILED',v_err);
                COMMIT; v_fail:=v_fail+1;
            END;
        END LOOP;
        DBMS_OUTPUT.PUT_LINE('run: DONE='||v_done||' FAILED='||v_fail);
        IF v_fail>0 THEN
            raise_application_error(-20020, v_fail||' komend padlo (patrz sql_exec_queue_log)');
        END IF;
    END p_run_compress_queue;

END pkg_maintenance;
/

grant execute on maintenance.pkg_maintenance to DEV_APP;