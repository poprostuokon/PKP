{{
    config(
        materialized='incremental',
        incremental_strategy='merge',
        unique_key=['code', 'carrier_code'],
        schema='silver'
    )
}}

-- SILVER: def_commercial_category. MERGE po (code, carrier_code).
-- Dedup na wypadek powtorzonych par w zrodle (MERGE wymaga stabilnego zbioru - inaczej ORA-30926).

with stg as (
    select * from {{ ref('int_commercial_categories') }}
),
dedup as (
    select
        code, name, carrier_code, speed_category_code,
        row_number() over (partition by code, carrier_code order by 1) as rn
    from stg
)
select
    code,
    name,
    carrier_code,
    speed_category_code,
    systimestamp    as loaded_at
from dedup
where rn = 1
