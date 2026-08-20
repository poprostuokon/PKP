{{
    config(
        materialized='incremental',
        incremental_strategy='append',
        schema='silver'
    )
}}

-- SILVER: disruption_header. Brak klucza naturalnego -> id deterministyczne:
--   id = data(generatedAt) YYYYMMDD * 1e6 + disruptionId   (header i details licza tak samo).
-- INSERT ONLY NEW po id. JSON wbudowany (bez WITH).

select
    id, disruption_type_code, message, snapshot_ts, loaded_at
from (
    select
        to_number(to_char(cast(j.snapshot_ts as date), 'YYYYMMDD')) * 1000000 + j.disruption_id  as id,
        j.disruption_type_code,
        j.message,
        j.snapshot_ts,
        systimestamp                                as loaded_at,
        row_number() over (
            partition by cast(j.snapshot_ts as date), j.disruption_id
            order by 1
        )                                           as rn
    from {{ source('stg', 'land_disruptions') }} src,
         json_table(
             src.payload, '$'
             columns (
                 snapshot_ts timestamp with time zone path '$.generatedAt',
                 nested path '$.disruptions[*]' columns (
                     disruption_id        number              path '$.disruptionId',
                     disruption_type_code varchar2(20 char)   path '$.disruptionTypeCode',
                     message              varchar2(1000 char) path '$.message'
                 )
             )
         ) j
) x
where rn = 1
{% if is_incremental() %}
  and not exists (select 1 from {{ this }} t where t.id = x.id)
{% endif %}
