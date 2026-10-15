{{ config(materialized='table') }}

with stg_stores as (

    SELECT 
        TRY_CAST(STORE AS INT) as store_id,
        CAST(TYPE AS VARCHAR(2)) as store_type,
        TRY_CAST(SIZE AS INT) as store_size
    FROM {{ source('walmart_raw', 'stores') }}

)

SELECT * FROM stg_stores
