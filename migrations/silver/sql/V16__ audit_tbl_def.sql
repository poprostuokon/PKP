CREATE TABLE silver.AUDIT_TBL_DEF (
    audit_id     NUMBER GENERATED ALWAYS AS IDENTITY,
    table_name   VARCHAR2(30 CHAR)        NOT NULL,   
    business_key VARCHAR2(400 CHAR)       NOT NULL,   
    column_name  VARCHAR2(128 CHAR)       NOT NULL,   
    old_value    VARCHAR2(4000 CHAR),                 
    new_value    VARCHAR2(4000 CHAR),                 
    changed_at   TIMESTAMP WITH TIME ZONE NOT NULL,
    changed_by   VARCHAR2(128 CHAR),
    CONSTRAINT pk_defaudit PRIMARY KEY (audit_id)
);