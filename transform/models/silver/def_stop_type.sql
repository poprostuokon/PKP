{{
    config(
        materialized='incremental',
        incremental_strategy='merge',
        unique_key='id',
        schema='silver'
    )
}}

-- SILVER: def_stop_type. MERGE po id.
with stg as (
    select * from {{ ref('int_stop_types') }}
)
select
    stop_type_id    as id,
    description,
    systimestamp    as loaded_at
from stg
