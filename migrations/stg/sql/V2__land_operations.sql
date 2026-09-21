CREATE TABLE stg.land_operations (
    payload     JSON,
    loaded_at   TIMESTAMP WITH TIME ZONE DEFAULT SYSTIMESTAMP NOT NULL
);