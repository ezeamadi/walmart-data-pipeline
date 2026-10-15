# Walmart Sales Data Pipeline

An end-to-end ELT project that loads Walmart sales data from Amazon S3 into Snowflake, models it into a star schema with dbt, and visualizes the results with Python.

```
S3 (CSV files)
   |  Snowflake storage integration + external stage, COPY INTO
   v
Snowflake  BRONZE   raw tables, loaded as-is
   |  dbt
   v
Snowflake  SILVER   cleaned and typed staging models
   |  dbt
   v
Snowflake  GOLD     date dimension, store dimension, sales fact table
   |  Python (read-only role)
   v
Charts (matplotlib)
```

## Tech stack

| Layer                      | Tool                                                        |
| -------------------------- | ----------------------------------------------------------- |
| Storage                    | Amazon S3                                                   |
| Warehouse                  | Snowflake                                                   |
| Transformation and testing | dbt (developed in dbt Cloud), `dbt_utils` package           |
| Visualization              | Python, pandas, matplotlib, `snowflake-connector-python`    |
| Authentication             | Key pair authentication for the dbt and visualization users |

## Data

The project uses three CSV files from a Walmart store sales dataset. The files are **not included** in this repository.

| File             | Content                                                                 | Grain                   |
| ---------------- | ----------------------------------------------------------------------- | ----------------------- |
| `department.csv` | Weekly sales per department, holiday flag                               | Store, department, week |
| `fact.csv`       | Temperature, fuel price, markdowns 1-5, CPI, unemployment, holiday flag | Store, week             |
| `stores.csv`     | Store type and size                                                     | Store                   |

## Repository layout

```
.
├── README.md
├── dbt_project.yml
├── packages.yml
├── models/
│   ├── walmart_silver/      stg_stores, stg_department, stg_fact + schema.yml
│   └── walmart_gold/        walmart_date_dim, walmart_store_dim, walmart_fact_table + schema.yml
├── macros/
│   └── generate_schema_name.sql
├── snowflake/
│   ├── 01_setup.sql         database, schemas, storage integration, stage
│   ├── 02_bronze_load.sql   Bronze tables and COPY INTO
│   └── 03_roles.sql         dbt and visualization roles and grants
├── viz/
│   └── walmart-dashboard.py
├── docs/
│   └── walmart_dashboard.png
└── requirements.txt
```

## Data model

### Bronze

Raw tables loaded directly from S3 with `COPY INTO` through an external stage.

| Table        | Typing                                    | Notes                                                                                                             |
| ------------ | ----------------------------------------- | ----------------------------------------------------------------------------------------------------------------- |
| `DEPARTMENT` | Typed columns (`DECIMAL(15,2)` for sales) | Loaded with `skip_header = 1`                                                                                     |
| `FACT`       | All `VARCHAR`                             | Raw landing cannot reject rows. `NULL_IF` converts `NA` and similar text to real NULLs. Casting happens in Silver |
| `STORES`     | See `snowflake/02_bronze_load.sql`        |                                                                                                                   |

### Silver

One staging model per Bronze table. Each model selects explicit columns, renames them, and casts types with `TRY_CAST`. Silver is the only layer that reads Bronze (through `source()`).

### Gold

| Model                | One row per                | Key                              |
| -------------------- | -------------------------- | -------------------------------- |
| `walmart_date_dim`   | Week                       | `date_id` (`YYYYMMDD` integer)   |
| `walmart_store_dim`  | Store and department pair  | `store_id`, `dept_id`            |
| `walmart_fact_table` | Store, department and week | `store_id`, `dept_id`, `date_id` |

The fact table starts from department sales and left-joins the store-level measures (temperature, fuel price, CPI, unemployment, markdowns) on store and week, so no sales row is ever dropped. `date_id` was added to the fact table so it can join to the date dimension.

All Gold models are built as **SCD Type 1**: incremental models using the `merge` strategy, a `unique_key`, and `merge_update_columns` so a changed row is overwritten in place while the original `insert_date` is preserved. A `NOT EXISTS` filter sends only new or changed rows to the merge, so `update_date` moves only when a value really changed.

## Setup

### Prerequisites

- An AWS account with an S3 bucket and an IAM role that Snowflake can assume
- A Snowflake account
- A dbt Cloud account (or dbt Core with a `profiles.yml`; see the note below)
- Python 3.10 or newer, and OpenSSL for key generation

### 1. Snowflake and S3

1. Upload the three CSV files to your S3 bucket.
2. Open `snowflake/01_setup.sql` and replace the placeholders:
   - `<AWS_ACCOUNT_ID>` and `<IAM_ROLE_NAME>` in the storage integration
   - `<YOUR_BUCKET>` in the allowed locations and stage URL
3. Run `DESCRIBE INTEGRATION` and use the returned IAM user ARN and external ID in the role's trust policy.
4. Run `snowflake/02_bronze_load.sql` to create the Bronze tables and load them. Check the `COPY INTO` output (`rows_parsed`, `rows_loaded`, `errors_seen`) against the CSV row counts.

### 2. Roles and users

Run `snowflake/03_roles.sql`. It creates:

| Role       | Purpose                   | Access                                                       |
| ---------- | ------------------------- | ------------------------------------------------------------ |
| `DBT_ROLE` | Used by dbt               | Read Bronze, create objects in Silver, Gold and a dev schema |
| `VIZ_ROLE` | Used by the Python script | Read-only on the schema holding the Gold tables              |

Each role has a service user that authenticates with a key pair. Generate the keys locally (they are never committed):

```bash
openssl genrsa 2048 | openssl pkcs8 -topk8 -v2 aes-256-cbc -inform PEM -out dbt_key.p8
openssl rsa -in dbt_key.p8 -pubout -out dbt_key.pub
```

Attach the public key to the user with `ALTER USER <user> SET RSA_PUBLIC_KEY = '...'`, using only the text between the `BEGIN` and `END` lines. Repeat with a separate key pair for the visualization user.

### 3. dbt

1. Create a dbt project connected to Snowflake with key pair credentials (database `WALMART_RAW`, role `DBT_ROLE`) and add this repository's files.
2. Install packages and build:

```bash
dbt deps
dbt build --full-refresh   # first run, to create the incremental tables
dbt build                  # later runs
```

The `generate_schema_name` macro keeps all objects in the developer's schema outside production, and routes models to `SILVER` and `GOLD` when the target is named `prod`.

**dbt Core:** this project was developed in dbt Cloud, so no `profiles.yml` is included. To use dbt Core, create a `profiles.yml` for Snowflake with key pair authentication and read the secrets from environment variables. Never commit it.

### 4. Visualization

```bash
python -m venv .venv
source .venv/bin/activate            # Windows: .venv\Scripts\activate
pip install -r requirements.txt

export SNOWFLAKE_ACCOUNT="<org>-<account>"
export SNOWFLAKE_PRIVATE_KEY_PATH="/path/to/viz_key.p8"
export SNOWFLAKE_PRIVATE_KEY_PASSPHRASE="<passphrase>"

python viz/walmart-dashboard.py
```

The script saves `walmart_dashboard.png` and opens a chart window. At the top of the script, a single schema variable controls whether it reads `DBT_DEV` or `GOLD`.

## Design decisions

| Decision                                 | Reason                                                                                                                    |
| ---------------------------------------- | ------------------------------------------------------------------------------------------------------------------------- |
| Bronze `FACT` loaded as text             | Raw landing should never reject rows. Type problems surface in Silver, where `TRY_CAST` plus `not_null` tests expose them |
| `NULL_IF` at load time                   | Missing markdowns become real NULLs instead of the string `NA`                                                            |
| One Silver model per Bronze table        | Each source is cleaned in one place, and joining is left to Gold                                                          |
| `date_id` as a `YYYYMMDD` integer        | Readable, deterministic, and no hashing needed for a calendar key                                                         |
| Left join from department sales          | Sales rows are the facts and must never be dropped by a missing store-level row                                           |
| Incremental merge for SCD1               | Demonstrates update-in-place behavior and keeps the original insert timestamp                                             |
| Separate roles for dbt and visualization | Least privilege: the notebook user is read-only                                                                           |
| Key pair authentication                  | Service users have no password or MFA prompt, and keys can be rotated                                                     |

## Testing and data quality

- `not_null` and `unique` tests on key columns
- Composite uniqueness tests with `dbt_utils.unique_combination_of_columns` on the store dimension and the fact table
- Row-count comparison between Silver `department` and the fact table to detect join fan-out or dropped rows
- Date-range and holiday-flag consistency checks between the two source files
- Foreign key checks from the fact table to both dimensions `[VERIFY: keep only if you implemented them]`

## Results

![Dashboard](docs/walmart_dashboard.png)

The dashboard contains four views: average weekly sales for holiday versus non-holiday weeks, total sales over time, the top 10 departments by total sales, and total sales per store by store type.

## Limitations

| Limitation                                      | Detail                                                                                                                                                                                                                                             |
| ----------------------------------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Production deployment not run                   | Models were built and tested in a dev schema (`DBT_DEV`), and the dashboard reads from it. The macro that routes models to `SILVER` and `GOLD` exists but was not exercised in a deployed job                                                      |
| Store-level measures repeat per department      | Temperature, fuel price, CPI, unemployment and markdowns repeat on every department row. Summing them gives wrong results, and averaging across department rows weights each store by its number of departments. Aggregate to store and week first |
| SCD1 keeps no history                           | Changed values are overwritten. `vrsn_start_date` and `vrsn_end_date` are placeholders, and rows deleted at the source are not removed from Gold                                                                                                   |
| Date dimension extends past the last sales week | The store-level file covers more weeks than the department sales file, so some dates have no sales                                                                                                                                                 |
| Store dimension repeats store attributes        | Store type and size repeat for every department, as required by the assignment's schema                                                                                                                                                            |
| Manual loading                                  | `COPY INTO` runs by hand, with no Snowpipe, scheduling or orchestration                                                                                                                                                                            |
| Broad setup role                                | The setup script uses `ACCOUNTADMIN`, which is acceptable for a personal project but not for a shared environment                                                                                                                                  |
| Limited testing                                 | Tests cover keys, uniqueness and basic quality, and the Python code has no automated tests                                                                                                                                                         |
| Incremental comparison scans the target         | The `NOT EXISTS` filter reads the whole target table each run, which is fine at this size but would not scale to very large tables                                                                                                                 |
| No CI                                           | There are no automated checks on pull requests                                                                                                                                                                                                     |

## Possible improvements

- Run the production deployment and point the dashboard at `GOLD`
- Add a scheduled dbt job and automate loading with Snowpipe
- Add dbt CI on pull requests
- Track history with dbt snapshots (SCD2) where it is needed
- Add source freshness checks and more business-rule tests

## Author

`Eze Amadi` | `https://www.linkedin.com/in/ezeamadi/`
