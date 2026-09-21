CREATE TABLE stg.land_train_statuses (
    payload     JSON,
    loaded_at   TIMESTAMP WITH TIME ZONE DEFAULT SYSTIMESTAMP NOT NULL
);