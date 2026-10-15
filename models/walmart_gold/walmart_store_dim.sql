{{ config(
    materialized='incremental',
    incremental_strategy='merge',
    unique_key=['store_id', 'dept_id'],
    merge_update_columns=['store_type', 'store_size', 'update_date']
) }}

with store_details as (

    SELECT
        store_id,
        store_type,
        store_size
    from {{ ref('stg_stores') }}

),

store_and_dept as (

    SELECT DISTINCT
        store_id, 
        department_id
    FROM {{ ref('stg_department') }}

),

final_data as (

    SELECT        
        s.store_id,
        s.store_type,
        sd.department_id as dept_id,
        s.store_size,
        CURRENT_TIMESTAMP() as insert_date,
        CURRENT_TIMESTAMP() as update_date
    FROM store_details s
    JOIN store_and_dept sd
        ON s.store_id = sd.store_id
        
)

SELECT *
FROM final_data f
{% if is_incremental() %}
    WHERE NOT EXISTS (
        SELECT 1
        FROM {{ this }} t
        WHERE t.store_id = f.store_id
        AND t.dept_id IS NOT DISTINCT FROM f.dept_id
        AND t.store_type IS NOT DISTINCT FROM f.store_type
        AND t.store_size IS NOT DISTINCT FROM f.store_size
    )
{% endif %}

