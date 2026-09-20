-- MAINTENANCE.PKG_TOOL - pakiet funkcji narzedziowych.
-- json_obj_to_kv: zamienia obiekt JSON {"k":"v",...} na tablice [{"k":..,"v":..}],
-- zeby dalo sie ja rozbic JSON_TABLE (iteracja kluczy obiektu).

CREATE OR REPLACE PACKAGE maintenance.pkg_tool AS
    FUNCTION f_json_obj_to_kv(p_json IN CLOB) RETURN CLOB;
	FUNCTION f_now_warsaw RETURN TIMESTAMP WITH TIME ZONE;
END pkg_tool;
/

CREATE OR REPLACE PACKAGE BODY maintenance.pkg_tool AS

    FUNCTION f_json_obj_to_kv(p_json IN CLOB) RETURN CLOB IS
        o     JSON_OBJECT_T;
        keys  JSON_KEY_LIST;
        arr   JSON_ARRAY_T := JSON_ARRAY_T();
        item  JSON_OBJECT_T;
    BEGIN
        IF p_json IS NULL THEN
            RETURN NULL;
        END IF;
        o    := JSON_OBJECT_T.parse(p_json);
        keys := o.get_keys;
        FOR i IN 1 .. keys.COUNT LOOP
            item := JSON_OBJECT_T();
            item.put('k', keys(i));
            item.put('v', o.get_String(keys(i)));
            arr.append(item);
        END LOOP;
        RETURN arr.to_clob;
    END f_json_obj_to_kv;
	
	FUNCTION f_now_warsaw RETURN TIMESTAMP WITH TIME ZONE IS
    BEGIN
        RETURN SYSTIMESTAMP AT TIME ZONE 'Europe/Warsaw';
    END f_now_warsaw;

END pkg_tool;
/


grant execute on  maintenance.pkg_tool to DEV_APP;
grant execute on  maintenance.pkg_tool to SILVER;
grant execute on  maintenance.pkg_tool to GOLD;
