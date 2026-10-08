-- 01_staging.sql  Land the raw files as all-text staging tables (no cleaning yet).
-- DuckDB: read_csv(..., all_varchar = true). On Databricks use
--   read_files('/Volumes/workspace/da_learn_24/raw/owid-energy-data.csv', format => 'csv', header => true, inferSchema => false)
-- which gives the same column names, all typed STRING.

-- owid-energy-data.csv: one row per entity (country, historical country or aggregate) x year, 1900-2025, 130 columns
CREATE OR REPLACE TABLE stg_energy AS
SELECT * FROM read_csv('{{RAW_DIR}}/owid-energy-data.csv', header = true, all_varchar = true);

-- owid-co2-data.csv: one row per entity x year, 1750-2024, 79 columns (joined for CO2 per capita / decoupling)
CREATE OR REPLACE TABLE stg_co2 AS
SELECT * FROM read_csv('{{RAW_DIR}}/owid-co2-data.csv', header = true, all_varchar = true);

-- codebooks: column, description, unit, source (documentation only; used to check that every analysed column is documented)
CREATE OR REPLACE TABLE stg_energy_codebook AS
SELECT * FROM read_csv('{{RAW_DIR}}/owid-energy-codebook.csv', header = true, all_varchar = true);

-- references (data/reference/): OWID's own country -> continent table, and a small hand-made override list
CREATE OR REPLACE TABLE ref_continents AS
SELECT * FROM read_csv('{{REF_DIR}}/owid_continents.csv', header = true, all_varchar = true);
CREATE OR REPLACE TABLE ref_entity_overrides AS
SELECT * FROM read_csv('{{REF_DIR}}/entity_overrides.csv', header = true, all_varchar = true);
