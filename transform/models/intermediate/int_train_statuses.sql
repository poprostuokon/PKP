-- intermediate: statusy pociagu - zrodlo to MAPA obiektow {"S":"NotStarted...","P":"..."}.
-- fn_json_obj_to_kv zamienia obiekt na tablice [{k,v}], potem JSON_TABLE.
with source as (
    select payload from {{ source('stg', 'land_train_statuses') }}
)
select
    jt.k    as code,
    jt.v    as name
from source s,
     json_table(
         maintenance.pkg_tool.f_json_obj_to_kv( json_query(s.payload, '$.trainStatuses' returning clob) ),
         '$[*]'
         columns (
             k varchar2(20 char)  path '$.k',
             v varchar2(200 char) path '$.v'
         )
     ) jt