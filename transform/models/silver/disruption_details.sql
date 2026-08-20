{{
    config(
        materialized='incremental',
        incremental_strategy='append',
        schema='silver'
    )
}}

-- SILVER: disruption_details (dotkniete kursy). dihe_id liczone tak samo jak header.id.
-- PK (operating_date, schedule_id, train_order_id, dsta_id, dihe_id).
-- depends_on wymusza budowe header PRZED details (FK dihe_id).
-- depends_on: {{ ref('disruption_header') }}

select
    schedule_id, order_id, train_order_id, operating_date,
    sequence_number, dsta_id, dihe_id, loaded_at
from (
    select
        j.schedule_id,
        j.order_id,
        j.train_order_id,
        to_date(j.operating_date, 'YYYY-MM-DD')     as operating_date,
        j.sequence_number,
        j.station_id                                as dsta_id,
        to_number(to_char(cast(j.snapshot_ts as date), 'YYYYMMDD')) * 1000000 + j.disruption_id  as dihe_id,
        systimestamp                                as loaded_at,
        row_number() over (
            partition by to_date(j.operating_date, 'YYYY-MM-DD'),
                         j.schedule_id, j.train_order_id, j.station_id,
                         (to_number(to_char(cast(j.snapshot_ts as date), 'YYYYMMDD')) * 1000000 + j.disruption_id)
            order by 1
        )                                           as rn
    from {{ source('stg', 'land_disruptions') }} src,
         json_table(
             src.payload, '$'
             columns (
                 snapshot_ts timestamp with time zone path '$.generatedAt',
                 nested path '$.disruptions[*]' columns (
                     disruption_id number path '$.disruptionId',
                     nested path '$.affectedRoutes[*]' columns (
                         schedule_id     number            path '$.scheduleId',
                         order_id        number            path '$.orderId',
                         train_order_id  number            path '$.trainOrderId',
                         operating_date  varchar2(10 char) path '$.operatingDate',
                         station_id      number            path '$.stationId',
                         sequence_number number            path '$.sequenceNumber'
                     )
                 )
             )
         ) j
		 
) x
where rn = 1
		and schedule_id is not null and order_id is not null and train_order_id is not null
{% if is_incremental() %}
  and not exists (
      select 1 from {{ this }} t
      where t.operating_date = x.operating_date
        and t.schedule_id    = x.schedule_id
        and t.train_order_id = x.train_order_id
        and t.dsta_id        = x.dsta_id
        and t.dihe_id        = x.dihe_id
  )
{% endif %}
