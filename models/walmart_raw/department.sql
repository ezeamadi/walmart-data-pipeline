
{{ config(materialized='table') }}

with raw_department as (

    SELECT * 
    FROM {{ source('walmart_raw', 'department') }}

)

select *
from raw_department

