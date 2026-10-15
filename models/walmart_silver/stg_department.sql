{{ config(materialized='table') }}

with stg_department as (

    SELECT 
        TRY_CAST(STORE AS INT) as store_id,
        TRY_CAST(DEPT AS INT) as department_id,
        TRY_CAST(DATE AS DATE) as weekly_date,
        TRY_CAST(WEEKLY_SALES AS DECIMAL(10,3)) as weekly_sales_sum,
        CAST(ISHOLIDAY AS BOOLEAN) as is_holiday
    FROM {{ source('walmart_raw', 'department') }}

)

SELECT * FROM stg_department
