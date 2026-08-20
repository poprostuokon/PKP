-- intermediate: miasta - rozbicie payload JSON na wiersze (ephemeral CTE).
-- Struktura: { "cities": [ {name, stationCount, stationIds:[...]}, ... ] }
-- Dla def_city bierzemy name + stationCount (stationIds pomijamy - to nie ten wymiar).

with source as (
    select payload
    from {{ source('stg', 'land_cities') }}
)

select
    jt.name             as city_name,
    jt.station_count
from source s,
     json_table(
         s.payload, '$.cities[*]'
         columns (
             name          varchar2(200 char) path '$.name',
             station_count number             path '$.stationCount'
         )
     ) jt
