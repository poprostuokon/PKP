-- =============================================================================
-- gold.d_station
-- -----------------------------------------------------------------------------
-- Wymiar GOLD: słownik stacji kolejowych wraz z nazwą miasta (opcjonalną, gdy
-- stacja nie ma powiązania z miastem). Klucz id to naturalny identyfikator
-- stacji z API, używany bezpośrednio do łączenia z faktami.
-- =============================================================================

CREATE TABLE gold.d_station (
    id    NUMBER                    		NOT NULL,   -- klucz naturalny z API (= silver.def_station.id)
    station_name  VARCHAR2(200 CHAR)        NOT NULL,
    city_name     VARCHAR2(200 CHAR),                   -- NULL gdy stacja bez powiązania z miastem (LEFT JOIN)
    loaded_at     TIMESTAMP WITH TIME ZONE  NOT NULL,
    CONSTRAINT pk_dstat PRIMARY KEY (id)
);