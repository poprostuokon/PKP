-- =============================================================================
-- stg.land_stop_types
-- -----------------------------------------------------------------------------
-- Tabela landing (staging): surowy słownik typów zatrzymania wczytany z bucketu
-- jako JSON, przed sparsowaniem do warstwy SILVER. Scratch - czyszczona i
-- ładowana wyłącznie nowymi plikami w każdym cyklu. Znacznik loaded_at = czas
-- wczytania.
-- =============================================================================

CREATE TABLE stg.land_stop_types (
    payload     JSON,
    loaded_at   TIMESTAMP WITH TIME ZONE DEFAULT SYSTIMESTAMP NOT NULL
);