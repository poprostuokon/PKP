{{
    config(
        materialized='incremental',
        incremental_strategy='merge',
        unique_key='name',
        merge_update_columns=['station_count', 'loaded_at'],
        schema='silver'
    )
}}

-- SILVER: def_city. MERGE po name (klucz naturalny, UNIQUE).
-- id generuje sie sam (IDENTITY), is_active zostaje na DEFAULT TRUE.

select
    cast(null as number)    as id,
    city_name       as name,
    station_count,
    cast('T' as boolean)    as is_active,
    systimestamp    as loaded_at
from {{ ref('int_cities') }}
