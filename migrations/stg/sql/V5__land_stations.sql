-- =============================================================================
-- stg.land_stations
-- -----------------------------------------------------------------------------
-- Tabela landing (staging): surowy słownik stacji wczytany z bucketu jako JSON,
-- przed sparsowaniem do warstwy SILVER. Scratch - czyszczona i ładowana
-- wyłącznie nowymi plikami w każdym cyklu. Znacznik loaded_at = czas wczytania.
-- =============================================================================

CREATE TABLE stg.land_stations (
    payload     JSON,
    loaded_at   TIMESTAMP WITH TIME ZONE DEFAULT SYSTIMESTAMP NOT NULL
);