-- intermediate: przyczyny utrudnien - zrodlo to MAPA obiektow {"utr_01":"...","utr_02":"..."}.
with source as (
    select payload from {{ source('stg', 'land_disruption_types') }}
)
select
    jt.k    as code,
    jt.v    as description
from source s,
     json_table(
         maintenance.pkg_tool.f_json_obj_to_kv( json_query(s.payload, '$.disruptionTypes' returning clob) ),
         '$[*]'
         columns (
             k varchar2(20 char)  path '$.k',
             v varchar2(500 char) path '$.v'
         )
     ) jt
