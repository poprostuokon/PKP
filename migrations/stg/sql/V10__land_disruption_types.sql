CREATE TABLE IF NOT EXISTS stg.land_disruption_types (
    payload     JSON,
    loaded_at   TIMESTAMP WITH TIME ZONE DEFAULT SYSTIMESTAMP NOT NULL
);