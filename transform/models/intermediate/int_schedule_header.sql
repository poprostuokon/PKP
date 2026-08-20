-- intermediate: naglowki rozkladu. routes[] x operatingDates[] (rozbicie na date).
-- generatedAt (root) powtarzany per wiersz jako snapshot_ts.
with source as (
    select payload from {{ source('stg', 'land_schedules') }}
)
select
	distinct
    jt.schedule_id,
    jt.order_id,
    jt.train_order_id,
    jt.name,
    jt.carrier_code,
    jt.national_number,
    jt.intl_arrival_number,
    jt.intl_departure_number,
    jt.category_code,
    to_date(jt.operating_date, 'YYYY-MM-DD')    as operating_date,
    jt.snapshot_ts
from source s,
     json_table(
         s.payload, '$'
         columns (
             snapshot_ts timestamp with time zone path '$.generatedAt',
             nested path '$.routes[*]' columns (
                 schedule_id           number             path '$.scheduleId',
                 order_id              number             path '$.orderId',
                 train_order_id        number             path '$.trainOrderId',
                 name                  varchar2(200 char) path '$.name',
                 carrier_code          varchar2(20 char)  path '$.carrierCode',
                 national_number       varchar2(50 char)  path '$.nationalNumber',
                 intl_arrival_number   varchar2(50 char)  path '$.internationalArrivalNumber',
                 intl_departure_number varchar2(50 char)  path '$.internationalDepartureNumber',
                 category_code         varchar2(20 char)  path '$.commercialCategorySymbol',
                 nested path '$.operatingDates[*]' columns (
                     operating_date varchar2(10 char) path '$'
                 )
             )
         )
     ) jt