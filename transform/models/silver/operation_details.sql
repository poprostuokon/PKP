{{
    config(
        materialized='incremental',
        incremental_strategy='append',
        schema='silver'
    )
}}

-- SILVER: operation_details (przystanki wykonania). INSERT ONLY NEW po (ophe_id, actual_sequence).
-- ophe_id z JOIN do operation_header (po kluczu naturalnym). Opoznienia z API (withPlanned=true).
-- dwell_time_sec liczony z actual_departure - actual_arrival.

select
    ophe_id, planned_sequence, actual_sequence, dsta_id,
    actual_arrival, actual_departure, is_confirmed, is_cancelled,
    arrival_delay_min, departure_delay_min, dwell_time_sec
from (
    select
        oh.id                                       as ophe_id,
        j.planned_sequence,
        j.actual_sequence,
        j.station_id                                as dsta_id,
        j.actual_arrival,
        j.actual_departure,
        coalesce(j.is_confirmed, false)             as is_confirmed,
        coalesce(j.is_cancelled, false)             as is_cancelled,
        j.arrival_delay_min,
        j.departure_delay_min,
        round((cast(j.actual_departure as date) - cast(j.actual_arrival as date)) * 86400) as dwell_time_sec,
        row_number() over (
            partition by oh.id, j.actual_sequence
            order by 1
        )                                           as rn
    from {{ source('stg', 'land_operations') }} src,
         json_table(
             src.payload, '$.trains[*]'
             columns (
                 schedule_id    number            path '$.scheduleId',
                 order_id       number            path '$.orderId',
                 train_order_id number            path '$.trainOrderId',
                 operating_date varchar2(10 char) path '$.operatingDate',
                 nested path '$.stations[*]' columns (
                     station_id          number                    path '$.stationId',
                     planned_sequence    number                    path '$.plannedSequenceNumber',
                     actual_sequence     number                    path '$.actualSequenceNumber',
                     actual_arrival      timestamp with time zone  path '$.actualArrival',
                     actual_departure    timestamp with time zone  path '$.actualDeparture',
                     arrival_delay_min   number                    path '$.arrivalDelayMinutes',
                     departure_delay_min number                    path '$.departureDelayMinutes',
                     is_confirmed        boolean                   path '$.isConfirmed',
                     is_cancelled        boolean                   path '$.isCancelled'
                 )
             )
         ) j
         join {{ ref('operation_header') }} oh
             on  oh.schedule_id    = j.schedule_id
             and oh.order_id       = j.order_id
             and oh.train_order_id = j.train_order_id
             and oh.operating_date = to_date(j.operating_date, 'YYYY-MM-DD')
) x
where rn = 1
{% if is_incremental() %}
  and not exists (
      select 1 from {{ this }} t
      where t.ophe_id         = x.ophe_id
        and t.actual_sequence = x.actual_sequence
  )
{% endif %}