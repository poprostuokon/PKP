-- =============================================================================
-- stg.land_train_statuses
-- -----------------------------------------------------------------------------
-- Tabela landing (staging): surowy słownik statusów kursu wczytany z bucketu
-- jako JSON, przed sparsowaniem do warstwy SILVER. Scratch - czyszczona i
-- ładowana wyłącznie nowymi plikami w każdym cyklu. Znacznik loaded_at = czas
-- wczytania.
-- =============================================================================

CREATE TABLE stg.land_train_statuses (
    payload     JSON,
    loaded_at   TIMESTAMP WITH TIME ZONE DEFAULT SYSTIMESTAMP NOT NULL
);