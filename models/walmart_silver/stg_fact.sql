{{ config(materialized='table') }}

with stg_fact as (

    SELECT 
        TRY_CAST(STORE AS INT) as store_id,
        TRY_CAST(DATE AS DATE) as weekly_date,
        TRY_CAST(TEMPERATURE AS DECIMAL(5,2)) as average_temperature,
        TRY_CAST(FUEL_PRICE AS DECIMAL(10,4)) as average_fuel_price,
        TRY_CAST(MARKDOWN1 AS DECIMAL(10,3)) as markdown1,
        TRY_CAST(MARKDOWN2 AS DECIMAL(10,3)) as markdown2,
        TRY_CAST(MARKDOWN3 AS DECIMAL(10,3)) as markdown3,
        TRY_CAST(MARKDOWN4 AS DECIMAL(10,3)) as markdown4,
        TRY_CAST(MARKDOWN5 AS DECIMAL(10,3)) as markdown5,
        TRY_CAST(CPI AS DECIMAL(10,7)) as cpi,
        TRY_CAST(UNEMPLOYMENT AS DECIMAL(5,3)) as unemployment,
        CAST(ISHOLIDAY AS BOOLEAN) as is_holiday
    FROM {{ source('walmart_raw', 'fact') }}

)

SELECT * FROM stg_fact
