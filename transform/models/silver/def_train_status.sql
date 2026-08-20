{{
    config(
        materialized='incremental',
        incremental_strategy='merge',
        unique_key='code',
        schema='silver'
    )
}}

-- SILVER: def_train_status. MERGE po code (S, P, C, X, Q...).
with stg as (
    select * from {{ ref('int_train_statuses') }}
)
select
    code,
    name,
    systimestamp    as loaded_at
from stg
