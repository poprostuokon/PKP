-- =============================================================================
-- silver.def_disruption_cause
-- -----------------------------------------------------------------------------
-- Słownik SILVER: przyczyny utrudnień w ruchu pociągów. Mapuje kod z API
-- (disruptionTypeCode, np. utr_01) na opis tekstowy (np. "Awaria sieci
-- trakcyjnej"). Klucz to kod przyczyny.
-- =============================================================================

CREATE TABLE silver.def_disruption_cause (
    code         VARCHAR2(20 CHAR)         NOT NULL,   -- utr_01 ... utr_75 (disruptionTypeCode)
    description  VARCHAR2(500 CHAR)        NOT NULL,   -- "Awaria sieci trakcyjnej"
    loaded_at    TIMESTAMP WITH TIME ZONE  NOT NULL,
    CONSTRAINT pk_ddica_code PRIMARY KEY (code)
);