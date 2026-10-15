
{{ config(materialized='table') }}

with raw_stores as (

    SELECT *
    FROM {{ source('walmart_raw', 'stores') }}

)

SELECT * FROM raw_stores
