CREATE TABLE silver.def_train_status (
    code        VARCHAR2(20 CHAR)         NOT NULL,   -- klucz naturalny (S, P, X...)
    name        VARCHAR2(200 CHAR)        NOT NULL, 
    loaded_at   TIMESTAMP WITH TIME ZONE  NOT NULL,
    CONSTRAINT pk_dtrst_co PRIMARY KEY (code)  
);