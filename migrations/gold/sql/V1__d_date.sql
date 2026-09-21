CREATE TABLE gold.d_date (
    id     		NUMBER                    NOT NULL,   -- klucz naturalny YYYYMMDD (np. 20260820)
    full_date   DATE                      NOT NULL,
    year        NUMBER(4)                 NOT NULL,
    quarter     NUMBER(1)                 NOT NULL,   -- 1-4
    month       NUMBER(2)                 NOT NULL,   -- 1-12
    month_name  VARCHAR2(20 CHAR)         NOT NULL,   -- "sierpień"
    day         NUMBER(2)                 NOT NULL,   -- dzień miesiąca
    day_of_week NUMBER(1)                 NOT NULL,   -- 1=pon ... 7=niedz (ISO)
    day_name    VARCHAR2(20 CHAR)         NOT NULL,   -- "środa"
    iso_week    NUMBER(2)                 NOT NULL,   -- tydzień ISO
    is_weekend  CHAR(1)                   NOT NULL,   -- 'T'/'N'
    loaded_at   TIMESTAMP WITH TIME ZONE  NOT NULL,
    CONSTRAINT pk_ddate PRIMARY KEY (id),
    CONSTRAINT uq_ddate_full UNIQUE (full_date),
    CONSTRAINT chk_ddate_weekend CHECK (is_weekend IN ('T','N'))
);