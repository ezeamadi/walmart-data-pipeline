import os
import pandas as pd
import matplotlib.pyplot as plt
import snowflake.connector

def run_query(sql: str) -> pd.DataFrame:
    with snowflake.connector.connect(
        account=os.environ["SNOWFLAKE_ACCOUNT"],
        user="VIZ_USER",
        role="VIZ_ROLE",
        warehouse="COMPUTE_WH",
        database="WALMART_RAW",
        schema="DBT_DEV",
        private_key_file=os.environ["SNOWFLAKE_PRIVATE_KEY_PATH"],
        private_key_file_pwd=os.environ["SNOWFLAKE_PRIVATE_KEY_PASSPHRASE"],
    ) as conn:
        cur = conn.cursor()
        cur.execute(sql)
        df = cur.fetch_pandas_all()
    df.columns = df.columns.str.lower()  # Snowflake returns uppercase names
    return df


# 1. Holiday vs non-holiday
df_holiday = run_query("""
    SELECT d.isholiday, AVG(f.store_weekly_sales) AS avg_weekly_sales
    FROM walmart_fact_table f
    JOIN walmart_date_dim d ON f.date_id = d.date_id
    GROUP BY d.isholiday
""")

# 2. Sales trend over time
df_trend = run_query("""
    SELECT d.store_date, SUM(f.store_weekly_sales) AS total_sales
    FROM walmart_fact_table f
    JOIN walmart_date_dim d ON f.date_id = d.date_id
    GROUP BY d.store_date
    ORDER BY d.store_date
""")

# 3. Top 10 departments
df_dept = run_query("""
    SELECT dept_id, SUM(store_weekly_sales) AS total_sales
    FROM walmart_fact_table
    GROUP BY dept_id
    ORDER BY total_sales DESC
    LIMIT 10
""")

# 4. Sales per store by store type
df_type = run_query("""
    SELECT s.store_type,
           SUM(f.store_weekly_sales) / COUNT(DISTINCT f.store_id) AS sales_per_store
    FROM walmart_fact_table f
    JOIN walmart_store_dim s
      ON f.store_id = s.store_id AND f.dept_id = s.dept_id
    GROUP BY s.store_type
    ORDER BY s.store_type
""")

# Snowflake decimals can arrive as objects, so convert explicitly
df_holiday["avg_weekly_sales"] = df_holiday["avg_weekly_sales"].astype(float)
df_trend["total_sales"] = df_trend["total_sales"].astype(float)
df_trend["store_date"] = pd.to_datetime(df_trend["store_date"])
df_dept["total_sales"] = df_dept["total_sales"].astype(float)
df_dept["dept_id"] = df_dept["dept_id"].astype(str)
df_type["sales_per_store"] = df_type["sales_per_store"].astype(float)

fig, axes = plt.subplots(2, 2, figsize=(14, 9))

axes[0, 0].bar(df_holiday["isholiday"], df_holiday["avg_weekly_sales"])
axes[0, 0].set_title("Average weekly sales: holiday vs non-holiday")
axes[0, 0].set_ylabel("Sales per store-department-week")

axes[0, 1].plot(df_trend["store_date"], df_trend["total_sales"])
axes[0, 1].set_title("Total weekly sales over time")
axes[0, 1].set_ylabel("Total sales")

axes[1, 0].bar(df_dept["dept_id"], df_dept["total_sales"])
axes[1, 0].set_title("Top 10 departments by total sales")
axes[1, 0].set_xlabel("Department")

axes[1, 1].bar(df_type["store_type"], df_type["sales_per_store"])
axes[1, 1].set_title("Total sales per store, by store type")

fig.tight_layout()
fig.savefig("walmart_dashboard.png", dpi=150)
plt.show()