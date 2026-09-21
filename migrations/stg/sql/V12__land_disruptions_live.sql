CREATE TABLE stg.land_disruptions_live (
    payload     JSON,
    loaded_at   TIMESTAMP WITH TIME ZONE DEFAULT SYSTIMESTAMP NOT NULL
);