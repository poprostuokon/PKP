{{
    config(
        materialized='incremental',
        incremental_strategy='merge',
        unique_key=['code', 'valid_from'],
        schema='silver'
    )
}}

-- SILVER: def_carrier (SCD2 z API - validFrom/validTo podaje zrodlo).
-- MERGE po (code, valid_from): jedna wersja kodu = jeden wiersz.
-- Tabela istnieje juz z Flyway - dbt tylko nalewa dane (MERGE), nie tworzy DDL.

with stg as (
    select * from {{ ref('int_carriers') }}
)

select
    carrier_code                as code,
    carrier_name                as name,
    cast(valid_from as date)    as valid_from,
    cast(valid_to   as date)    as valid_to,
    systimestamp                as loaded_at
from stg
