-- intermediate: mapa stacja -> miasto, z cities[].stationIds[].
-- Struktura: { "cities": [ {name, stationCount, stationIds:[id, id, ...]}, ... ] }
-- JSON_TABLE z NESTED PATH rozbija zagniezdzona tablice stationIds na wiersze.
with source as (
    select payload from {{ source('stg', 'land_cities') }}
)
select
    jt.city_name,
    jt.station_id
from source s,
     json_table(
         s.payload, '$.cities[*]'
         columns (
             city_name varchar2(200 char) path '$.name',
             nested path '$.stationIds[*]'
                 columns ( station_id number path '$' )
         )
     ) jt