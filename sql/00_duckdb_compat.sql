-- 00_duckdb_compat.sql  (DuckDB ONLY - do NOT run on Databricks)
-- Spark / Databricks SQL function shims so that 01-05 can be written in Spark SQL dialect and still run unchanged on DuckDB.
-- On Databricks these functions are built in. Only the argument patterns used in this project are supported.
CREATE OR REPLACE MACRO regexp_like(s, p) AS regexp_matches(s, p);
CREATE OR REPLACE MACRO percentile_approx(x, p) AS quantile_cont(x, p);
