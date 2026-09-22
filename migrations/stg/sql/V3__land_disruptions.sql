-- =============================================================================
-- stg.land_disruptions
-- -----------------------------------------------------------------------------
-- Tabela landing (staging): surowe dane dzienne utrudnień wczytane z bucketu
-- jako JSON, przed sparsowaniem do warstwy SILVER. Scratch - czyszczona i
-- ładowana wyłącznie nowymi plikami w każdym cyklu. Znacznik loaded_at = czas
-- wczytania.
-- =============================================================================

CREATE TABLE stg.land_disruptions (
    payload     JSON,
    loaded_at   TIMESTAMP WITH TIME ZONE DEFAULT SYSTIMESTAMP NOT NULL
);