-- intermediate: przewoznicy - rozbicie payload JSON na wiersze (ephemeral CTE).
-- Struktura zrodla: { "generatedAt": ..., "carriers": [ {code, name, validFrom, validTo}, ... ] }
-- Zero logiki biznesowej - tylko JSON_TABLE + rename + casty. Uzywane w silver.def_carrier.

with source as (
    select payload
    from {{ source('stg', 'land_carriers') }}
)

select
    jt.code                             as carrier_code,
    jt.name                             as carrier_name,
    jt.valid_from,
    jt.valid_to
from source s,
     json_table(
         s.payload, '$.carriers[*]'
         columns (
             code       varchar2(20 char)  path '$.code',
             name       varchar2(200 char) path '$.name',
             valid_from timestamp          path '$.validFrom',
             valid_to   timestamp          path '$.validTo'
         )
     ) jt
