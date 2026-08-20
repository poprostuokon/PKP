{{
    config(
        materialized='incremental',
        incremental_strategy='append',
        schema='silver'
    )
}}

select
    schedule_id, order_id, order_number, dsta_id,
    arrival_time, arrival_day, arrival_at,
    arrival_platform, arrival_track, arrival_category, arrival_train_no,
    departure_time, departure_day, departure_at,
    departure_platform, departure_track, departure_category, departure_train_no,
    dstty_id
from (
    select
        j.schedule_id,
        j.order_id,
        j.order_number,
        j.station_id                               as dsta_id,
        j.arrival_time,
        j.arrival_day,
        cast(null as timestamp with time zone)     as arrival_at,
        j.arrival_platform,
        j.arrival_track,
        j.arrival_category,
        j.arrival_train_no,
        j.departure_time,
        j.departure_day,
        cast(null as timestamp with time zone)     as departure_at,
        j.departure_platform,
        j.departure_track,
        j.departure_category,
        j.departure_train_no,
        j.stop_type_id                             as dstty_id,
        row_number() over (
            partition by j.schedule_id, j.order_id, j.order_number
            order by 1
        )                                          as rn
    from {{ source('stg', 'land_schedules') }} src,
         json_table(
             src.payload, '$.routes[*]'
             columns (
                 schedule_id number path '$.scheduleId',
                 order_id    number path '$.orderId',
                 nested path '$.stations[*]' columns (
                     order_number        number             path '$.orderNumber',
                     station_id          number             path '$.stationId',
                     arrival_time        varchar2(8 char)   path '$.arrivalTime',
                     arrival_day         number             path '$.arrivalDay',
                     arrival_platform    varchar2(10 char)  path '$.arrivalPlatform',
                     arrival_track       varchar2(10 char)  path '$.arrivalTrack',
                     arrival_category    varchar2(20 char)  path '$.arrivalCommercialCategory',
                     arrival_train_no    varchar2(50 char)  path '$.arrivalTrainNumber',
                     departure_time      varchar2(8 char)   path '$.departureTime',
                     departure_day       number             path '$.departureDay',
                     departure_platform  varchar2(10 char)  path '$.departurePlatform',
                     departure_track     varchar2(10 char)  path '$.departureTrackk',
                     departure_category  varchar2(20 char)  path '$.departureCommercialCategory',
                     departure_train_no  varchar2(50 char)  path '$.departureTrainNumber',
                     stop_type_id        number             path '$.stopTypeId'
                 )
             )
         ) j
) x
where rn = 1
{% if is_incremental() %}
  and not exists (
      select 1
      from {{ this }} t
      where t.schedule_id  = x.schedule_id
        and t.order_id     = x.order_id
        and t.order_number = x.order_number
  )
{% endif %}