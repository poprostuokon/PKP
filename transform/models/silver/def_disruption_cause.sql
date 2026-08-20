{{
    config(
        materialized='incremental',
        incremental_strategy='merge',
        unique_key='code',
        schema='silver'
    )
}}

-- SILVER: def_disruption_cause. MERGE po code (utr_01 ... utr_75).
with stg as (
    select * from {{ ref('int_disruption_types') }}
)
select
    code,
    description,
    systimestamp    as loaded_at
from stg
