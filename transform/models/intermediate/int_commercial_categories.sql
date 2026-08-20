-- intermediate: kategorie handlowe
-- { "commercialCategories": [ {code, name, carrierCode, speedCategoryCode}, ... ] }
with source as (
    select payload from {{ source('stg', 'land_commercial_categories') }}
)
select
    jt.code,
    jt.name,
    jt.carrier_code,
    jt.speed_category_code
from source s,
     json_table(
         s.payload, '$.commercialCategories[*]'
         columns (
             code                varchar2(20 char)  path '$.code',
             name                varchar2(200 char) path '$.name',
             carrier_code        varchar2(20 char)  path '$.carrierCode',
             speed_category_code varchar2(20 char)  path '$.speedCategoryCode'
         )
     ) jt
