--- =============================================================================
--- stg.land_schedules
-- -----------------------------------------------------------------------------
-- Tabela landing (staging): surowe dane rozkładu jazdy wczytane z bucketu jako JSON,
-- przed sparsowaniem do warstwy SILVER. Scratch - czyszczona i ładowana
-- wyłącznie nowymi plikami w każdym cyklu. Znacznik loaded_at = czas wczytania.
-- =============================================================================

CREATE TABLE stg.land_schedules (
    payload     JSON,                                                   -- surowy dokument JSON
    loaded_at   TIMESTAMP WITH TIME ZONE DEFAULT SYSTIMESTAMP NOT NULL  -- kiedy wgrano do landing
);