{{
    config(
        materialized='incremental',
        incremental_strategy='merge',
        unique_key='id',
        schema='silver',
        merge_update_columns=['name', 'dcit_id', 'loaded_at']
    )
}}

-- SILVER: def_station. MERGE po id (klucz naturalny z API).
-- dcit_id = silver.def_city.id, wyznaczone: stacja -> miasto (cities.stationIds)
--           -> def_city.id (po nazwie). NULL, gdy stacja nie nalezy do zadnego miasta.
-- first_seen_at ustawiane raz przy insercie (poza merge_update_columns).

with stg as (
    select * from {{ ref('int_stations') }}
),
map as (
    select * from {{ ref('int_city_stations') }}
),
cities as (
    select id as dcit_id, name from {{ ref('def_city') }}
),
joined as (
    select
        stg.station_id      as id,
        stg.station_name    as name,
        c.dcit_id           as dcit_id,
        row_number() over (partition by stg.station_id
                           order by c.dcit_id nulls last) as rn
    from stg
    left join map on map.station_id = stg.station_id
    left join cities c on c.name = map.city_name
)
select
    id,
    name,
    dcit_id,
    'T'             as is_active,
    systimestamp    as first_seen_at,
    systimestamp    as loaded_at
from joined
where rn = 1