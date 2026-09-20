CREATE TABLE IF NOT EXISTS stg.land_commercial_categories (
    payload     JSON,
    loaded_at   TIMESTAMP WITH TIME ZONE DEFAULT SYSTIMESTAMP NOT NULL
);