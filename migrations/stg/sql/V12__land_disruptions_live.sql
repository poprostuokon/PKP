CREATE TABLE IF NOT EXISTS stg.land_disruptions_live (
    payload     JSON,
    loaded_at   TIMESTAMP WITH TIME ZONE DEFAULT SYSTIMESTAMP NOT NULL
);