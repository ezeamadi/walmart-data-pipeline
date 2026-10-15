
{{ config(materialized='table') }}

with raw_fact as (

    SELECT * 
    FROM {{ source('walmart_raw', 'fact') }}

)

select *
from raw_fact

