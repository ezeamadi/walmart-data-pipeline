{{ config(
    materialized='incremental',
    incremental_strategy='merge',
    unique_key='date_id',
    merge_update_columns=['store_date', 'isholiday', 'update_date']
) }}


with weekly_dates_from_dept as (

    SELECT weekly_date as weekly_date from {{ ref('stg_department') }}

),

weekly_dates_from_fact as (

    SELECT weekly_date as weekly_date from {{ ref('stg_fact') }}

),

store_dates_and_id as (

    select 
        TO_CHAR(weekly_date, 'YYYYMMDD')::INT AS date_id,
        weekly_date
    from weekly_dates_from_dept

    union

    select 
        TO_CHAR(weekly_date, 'YYYYMMDD')::INT AS date_id,
        weekly_date
    from weekly_dates_from_fact

),

is_holiday_dates as (

    SELECT weekly_date, is_holiday
    FROM {{ ref('stg_fact') }}

),

final_data as (

    SELECT         
        sdi.date_id, 
        sdi.weekly_date as store_date,
        BOOLOR_AGG(ihd.is_holiday)::VARCHAR(10) as isholiday,
        CURRENT_TIMESTAMP() as insert_date,
        CURRENT_TIMESTAMP() as update_date
    FROM store_dates_and_id sdi
    JOIN is_holiday_dates ihd
        ON sdi.weekly_date = ihd.weekly_date
    GROUP BY sdi.date_id, sdi.weekly_date

)

SELECT * 
FROM final_data f
{% if is_incremental() %}
    WHERE NOT EXISTS (
        SELECT 1
        FROM {{ this }} t
        WHERE t.date_id = f.date_id
        AND t.store_date = f.store_date
        AND t.isholiday IS NOT DISTINCT FROM f.isholiday
    )
{% endif %}
