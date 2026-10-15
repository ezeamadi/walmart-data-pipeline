{% set tracked_cols = [
    'store_weekly_sales', 'fuel_price', 'store_temperature', 'unemployment',
    'cpi', 'markdown1', 'markdown2', 'markdown3', 'markdown4', 'markdown5'
] %}

{{ config(
    materialized='incremental',
    incremental_strategy='merge',
    unique_key=['store_id', 'dept_id', 'date_id'],
    merge_update_columns=tracked_cols + ['update_date']
) }}

with store_details as (

    SELECT
        store_id, 
        department_id,
        weekly_date,
        weekly_sales_sum
    FROM {{ ref('stg_department') }}

),

fact_details as (

    SELECT
        store_id, 
        weekly_date,
        average_temperature,
        average_fuel_price,
        markdown1,
        markdown2,
        markdown3,
        markdown4,
        markdown5,
        cpi,
        unemployment
    FROM {{ ref('stg_fact') }}

),

final_data as (

    SELECT        
        s.store_id,
        s.department_id as dept_id,
        s.weekly_sales_sum as store_weekly_sales,
        s.weekly_date AS store_date,
        TO_CHAR(s.weekly_date, 'YYYYMMDD')::INT AS date_id,
        f.average_fuel_price as fuel_price,
        f.average_temperature as store_temperature,
        f.unemployment,
        f.cpi,
        f.markdown1,
        f.markdown2,
        f.markdown3,
        f.markdown4,
        f.markdown5,
        CURRENT_TIMESTAMP() as insert_date,
        CURRENT_TIMESTAMP() as update_date,
        CURRENT_TIMESTAMP() as vrsn_start_date,
        CAST(NULL AS TIMESTAMP_LTZ) AS vrsn_end_date
    FROM store_details s
    LEFT JOIN fact_details f
        ON s.store_id = f.store_id
            AND s.weekly_date = f.weekly_date 
)


SELECT *
FROM final_data f
{% if is_incremental() %}
    WHERE NOT EXISTS (
        SELECT 1
        FROM {{ this }} t
        WHERE t.store_id = f.store_id
        AND t.dept_id = f.dept_id
        AND t.date_id = f.date_id
        AND HASH({% for c in tracked_cols %}t.{{ c }}{{ ', ' if not loop.last }}{% endfor %})
            = HASH({% for c in tracked_cols %}f.{{ c }}{{ ', ' if not loop.last }}{% endfor %})
    )
{% endif %}
