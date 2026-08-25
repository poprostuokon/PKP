-- =====================================================================
-- TRIGGERY AUDYTOWE dla slownikow SILVER.DEF_*  ->  silver.def_audit
--
-- Zasada: AFTER UPDATE OF <kolumny aktualizowalne> - jeden wiersz audytu
--         na kazda REALNIE zmieniona kolumne (WHERE DECODE(old,new,0,1)=1, null-safe).
-- business_key = klucz glowny (PK) rekordu. Wartosci jako tekst (TO_CHAR dla dat/liczb).
-- changed_at = pkg_tool.f_now_warsaw (synonim w SILVER), changed_by = USER.
--
-- Wymaga: tabela silver.def_audit oraz synonim silver.pkg_tool (z pkg_silver_load).
-- Repeatable migration Flyway.
-- =====================================================================

-- ---- DEF_CARRIER: aktualizowalne name, valid_to ; PK (code, valid_from) ----
CREATE OR REPLACE TRIGGER silver.trg_def_carrier_audit
AFTER UPDATE OF name, valid_to ON silver.def_carrier
FOR EACH ROW
BEGIN
    INSERT INTO silver.def_audit
        (table_name, business_key, column_name, old_value, new_value, changed_at, changed_by)
    SELECT 'DEF_CARRIER',
           'code=' || :OLD.code || ';valid_from=' || TO_CHAR(:OLD.valid_from,'YYYY-MM-DD'),
           col, oldv, newv, pkg_tool.f_now_warsaw, USER
    FROM (
        SELECT 'NAME'     AS col, :OLD.name                           AS oldv, :NEW.name                           AS newv FROM dual
        UNION ALL
        SELECT 'VALID_TO' AS col, TO_CHAR(:OLD.valid_to,'YYYY-MM-DD'),        TO_CHAR(:NEW.valid_to,'YYYY-MM-DD')          FROM dual
    )
    WHERE DECODE(oldv, newv, 0, 1) = 1;
END;
/

-- ---- DEF_CITY: aktualizowalne station_count ; PK id ----
CREATE OR REPLACE TRIGGER silver.trg_def_city_audit
AFTER UPDATE OF station_count ON silver.def_city
FOR EACH ROW
BEGIN
    INSERT INTO silver.def_audit
        (table_name, business_key, column_name, old_value, new_value, changed_at, changed_by)
    SELECT 'DEF_CITY',
           'id=' || :OLD.id,
           col, oldv, newv, pkg_tool.f_now_warsaw, USER
    FROM (
        SELECT 'STATION_COUNT' AS col, TO_CHAR(:OLD.station_count) AS oldv, TO_CHAR(:NEW.station_count) AS newv FROM dual
    )
    WHERE DECODE(oldv, newv, 0, 1) = 1;
END;
/

-- ---- DEF_STATION: aktualizowalne name, dcit_id ; PK id ----
CREATE OR REPLACE TRIGGER silver.trg_def_station_audit
AFTER UPDATE OF name, dcit_id ON silver.def_station
FOR EACH ROW
BEGIN
    INSERT INTO silver.def_audit
        (table_name, business_key, column_name, old_value, new_value, changed_at, changed_by)
    SELECT 'DEF_STATION',
           'id=' || :OLD.id,
           col, oldv, newv, pkg_tool.f_now_warsaw, USER
    FROM (
        SELECT 'NAME'    AS col, :OLD.name              AS oldv, :NEW.name              AS newv FROM dual
        UNION ALL
        SELECT 'DCIT_ID' AS col, TO_CHAR(:OLD.dcit_id),          TO_CHAR(:NEW.dcit_id)          FROM dual
    )
    WHERE DECODE(oldv, newv, 0, 1) = 1;
END;
/

-- ---- DEF_STOP_TYPE: aktualizowalne description ; PK id ----
CREATE OR REPLACE TRIGGER silver.trg_def_stop_type_audit
AFTER UPDATE OF description ON silver.def_stop_type
FOR EACH ROW
BEGIN
    INSERT INTO silver.def_audit
        (table_name, business_key, column_name, old_value, new_value, changed_at, changed_by)
    SELECT 'DEF_STOP_TYPE',
           'id=' || :OLD.id,
           col, oldv, newv, pkg_tool.f_now_warsaw, USER
    FROM (
        SELECT 'DESCRIPTION' AS col, :OLD.description AS oldv, :NEW.description AS newv FROM dual
    )
    WHERE DECODE(oldv, newv, 0, 1) = 1;
END;
/

-- ---- DEF_COMMERCIAL_CATEGORY: aktualizowalne name, speed_category_code ; PK (code, carrier_code) ----
CREATE OR REPLACE TRIGGER silver.trg_def_comm_cat_audit
AFTER UPDATE OF name, speed_category_code ON silver.def_commercial_category
FOR EACH ROW
BEGIN
    INSERT INTO silver.def_audit
        (table_name, business_key, column_name, old_value, new_value, changed_at, changed_by)
    SELECT 'DEF_COMMERCIAL_CATEGORY',
           'code=' || :OLD.code || ';carrier_code=' || :OLD.carrier_code,
           col, oldv, newv, pkg_tool.f_now_warsaw, USER
    FROM (
        SELECT 'NAME'                AS col, :OLD.name                AS oldv, :NEW.name                AS newv FROM dual
        UNION ALL
        SELECT 'SPEED_CATEGORY_CODE' AS col, :OLD.speed_category_code,        :NEW.speed_category_code        FROM dual
    )
    WHERE DECODE(oldv, newv, 0, 1) = 1;
END;
/

-- ---- DEF_TRAIN_STATUS: aktualizowalne name ; PK code ----
CREATE OR REPLACE TRIGGER silver.trg_def_train_status_audit
AFTER UPDATE OF name ON silver.def_train_status
FOR EACH ROW
BEGIN
    INSERT INTO silver.def_audit
        (table_name, business_key, column_name, old_value, new_value, changed_at, changed_by)
    SELECT 'DEF_TRAIN_STATUS',
           'code=' || :OLD.code,
           col, oldv, newv, pkg_tool.f_now_warsaw, USER
    FROM (
        SELECT 'NAME' AS col, :OLD.name AS oldv, :NEW.name AS newv FROM dual
    )
    WHERE DECODE(oldv, newv, 0, 1) = 1;
END;
/

-- ---- DEF_DISRUPTION_CAUSE: aktualizowalne description ; PK code ----
CREATE OR REPLACE TRIGGER silver.trg_def_disr_cause_audit
AFTER UPDATE OF description ON silver.def_disruption_cause
FOR EACH ROW
BEGIN
    INSERT INTO silver.def_audit
        (table_name, business_key, column_name, old_value, new_value, changed_at, changed_by)
    SELECT 'DEF_DISRUPTION_CAUSE',
           'code=' || :OLD.code,
           col, oldv, newv, pkg_tool.f_now_warsaw, USER
    FROM (
        SELECT 'DESCRIPTION' AS col, :OLD.description AS oldv, :NEW.description AS newv FROM dual
    )
    WHERE DECODE(oldv, newv, 0, 1) = 1;
END;
/
