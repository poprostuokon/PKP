-- intermediate: stacje - { "stations": [ {id, name}, ... ] }
with source as (
    select payload from {{ source('stg', 'land_stations') }}
)
select
    jt.id           as station_id,
    jt.name         as station_name
from source s,
     json_table(
         s.payload, '$.stations[*]'
         columns (
             id   number             path '$.id',
             name varchar2(200 char) path '$.name'
         )
     ) jt
