-- =============================================================================
-- stg.land_operations
-- -----------------------------------------------------------------------------
-- Tabela landing (staging): surowe dane operacji wczytane z bucketu jako JSON,
-- przed sparsowaniem do warstwy SILVER. Scratch - czyszczona i ładowana
-- wyłącznie nowymi plikami w każdym cyklu. Znacznik loaded_at = czas wczytania.
-- =============================================================================

CREATE TABLE stg.land_operations (
    payload     JSON,
    loaded_at   TIMESTAMP WITH TIME ZONE DEFAULT SYSTIMESTAMP NOT NULL
);