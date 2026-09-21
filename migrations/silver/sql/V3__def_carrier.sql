CREATE TABLE silver.def_carrier (
    code        VARCHAR2(20 CHAR)         NOT NULL,   -- klucz naturalny (KD, IC, AR...)
    name        VARCHAR2(200 CHAR)        NOT NULL,
    valid_from  DATE                      NOT NULL,   -- z API
    valid_to    DATE                      NOT NULL,   -- z API (2999-12-31 = otwarty)
    loaded_at   TIMESTAMP WITH TIME ZONE  NOT NULL,
    CONSTRAINT pk_dcar_co_vafr PRIMARY KEY (code, valid_from)   -- kilka wersji tego samego kodu
);