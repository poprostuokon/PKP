-- =============================================================================
-- gold.d_hour
-- -----------------------------------------------------------------------------
-- Wymiar GOLD: godziny doby (0-23) z etykietą przedziału oraz porą dnia (noc,
-- szczyt poranny, dzień, szczyt popołudniowy, wieczór). Służy do analizy ruchu
-- i opóźnień w rozbiciu na godziny. Klucz id to numer godziny.
-- =============================================================================

CREATE TABLE gold.d_hour (
    id     		NUMBER(2)                 NOT NULL,   -- 0-23
    hour_label  VARCHAR2(20 CHAR)         NOT NULL,   -- "17:00-17:59"
    part_of_day VARCHAR2(30 CHAR)         NOT NULL,   -- noc / szczyt poranny / dzień / szczyt popołudniowy / wieczór
    loaded_at   TIMESTAMP WITH TIME ZONE  NOT NULL,
    CONSTRAINT pk_dhour PRIMARY KEY (id),
    CONSTRAINT chk_dhour_range CHECK (id BETWEEN 0 AND 23)
);