CREATE TABLE stg.land_schedules (
    payload     JSON,                                                   -- surowy dokument JSON
    loaded_at   TIMESTAMP WITH TIME ZONE DEFAULT SYSTIMESTAMP NOT NULL  -- kiedy wgrano do landing
);