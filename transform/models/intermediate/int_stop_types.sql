-- intermediate: typy postoju - { "stopTypes": [ {id, description}, ... ] }
with source as (
    select payload from {{ source('stg', 'land_stop_types') }}
)
select
    jt.id           as stop_type_id,
    jt.description
from source s,
     json_table(
         s.payload, '$.stopTypes[*]'
         columns (
             id          number             path '$.id',
             description varchar2(500 char) path '$.description'
         )
     ) jt
