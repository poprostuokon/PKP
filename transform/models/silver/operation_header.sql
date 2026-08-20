{{
    config(
        materialized='incremental',
        incremental_strategy='append',
        schema='silver'
    )
}}

-- SILVER: operation_header (wykonanie kursu danego dnia). INSERT ONLY NEW
-- po (operating_date, schedule_id, order_id, train_order_id). JSON wbudowany (bez WITH).
-- id = NULL -> Oracle generuje (BY DEFAULT ON NULL, migracja V19).

select
    id, schedule_id, order_id, train_order_id, operating_date,
    train_status, snapshot_ts, loaded_at
from (
    select
        cast(null as number)                        as id,
        j.schedule_id,
        j.order_id,
        j.train_order_id,
        to_date(j.operating_date, 'YYYY-MM-DD')     as operating_date,
        j.train_status,
        j.snapshot_ts,
        systimestamp                                as loaded_at,
        row_number() over (
            partition by j.operating_date, j.schedule_id, j.order_id, j.train_order_id
            order by 1
        )                                           as rn
    from {{ source('stg', 'land_operations') }} src,
         json_table(
             src.payload, '$'
             columns (
                 snapshot_ts timestamp with time zone path '$.generatedAt',
                 nested path '$.trains[*]' columns (
                     schedule_id    number             path '$.scheduleId',
                     order_id       number             path '$.orderId',
                     train_order_id number             path '$.trainOrderId',
                     operating_date varchar2(10 char)  path '$.operatingDate',
                     train_status   varchar2(10 char)  path '$.trainStatus'
                 )
             )
         ) j
) x
where rn = 1
{% if is_incremental() %}
  and not exists (
      select 1 from {{ this }} t
      where t.operating_date = x.operating_date
        and t.schedule_id    = x.schedule_id
        and t.order_id       = x.order_id
        and t.train_order_id = x.train_order_id
  )
{% endif %}