-- 02_cleaning.sql  Dedupe, empty -> NULL, types, entity standardisation (countries vs historical vs OWID aggregates), continent mapping,
-- CO2 join, coverage / outlier / consistency flags, long energy-mix table (Spark SQL dialect)

-- 1. exact duplicate rows dropped, then one row per entity x year (the raw files have no duplicates, the step is kept as a guard)
CREATE OR REPLACE TABLE cln_energy_distinct AS
SELECT DISTINCT * FROM stg_energy;

CREATE OR REPLACE TABLE cln_co2_distinct AS
SELECT DISTINCT * FROM stg_co2;

-- 2. entity dimension: the file mixes real countries with historical states and OWID / source aggregates in one `country` column.
--    Rule: a 3-letter ISO code (not OWID_*) = country; names in entity_overrides.csv = historical country (USSR, Yugoslavia ...) or a fixed
--    country (Kosovo has no ISO code); everything else (empty iso_code or OWID_ prefix) = aggregate, grouped by its type.
CREATE OR REPLACE TABLE cln_entity AS
WITH ent AS (
  SELECT trim(country) AS entity,
         max(NULLIF(upper(trim(iso_code)), '')) AS iso_raw,
         COUNT(DISTINCT NULLIF(upper(trim(iso_code)), '')) AS n_iso,
         min(TRY_CAST(trim(year) AS INT)) AS first_year,
         max(TRY_CAST(trim(year) AS INT)) AS last_year,
         COUNT(*) AS n_rows
  FROM cln_energy_distinct
  GROUP BY trim(country)
), cls AS (
  SELECT e.*, o.entity_type AS o_type, o.continent AS o_continent, NULLIF(trim(o.iso_code_override), '') AS o_iso,
         CASE WHEN o.entity_type IS NOT NULL THEN o.entity_type
              WHEN regexp_like(e.iso_raw, '^[A-Z]{3}$') THEN 'country'
              ELSE 'aggregate' END AS entity_type
  FROM ent e LEFT JOIN ref_entity_overrides o ON e.entity = trim(o.entity)
)
SELECT
  ROW_NUMBER() OVER (ORDER BY CASE c.entity_type WHEN 'country' THEN 1 WHEN 'historical_country' THEN 2 ELSE 3 END, c.entity) AS entity_key,
  c.entity,
  COALESCE(c.iso_raw, c.o_iso) AS iso_code,
  c.entity_type,
  CASE WHEN c.entity_type = 'country' THEN COALESCE(c.o_continent, k.owid_region)
       WHEN c.entity_type = 'historical_country' THEN c.o_continent END AS continent,
  CASE WHEN c.entity_type = 'country' THEN 'Country'
       WHEN c.entity_type = 'historical_country' THEN 'Historical country'
       WHEN c.entity = 'World' THEN 'World'
       WHEN c.entity IN ('Africa', 'Asia', 'Europe', 'North America', 'South America', 'Oceania') THEN 'Continent (OWID)'
       WHEN c.entity LIKE '%income countries' THEN 'Income group (World Bank)'
       WHEN c.entity = 'European Union (27)' THEN 'European Union (27)'
       WHEN c.entity LIKE '% (EI)' THEN 'Source region: Energy Institute'
       WHEN c.entity LIKE '% (EIA)' THEN 'Source region: US EIA'
       WHEN c.entity LIKE '% (Ember)' THEN 'Source region: Ember'
       WHEN c.entity LIKE '% (Shift)' THEN 'Source region: Shift Dataportal'
       ELSE 'Other aggregate' END AS entity_group,
  CASE WHEN c.iso_raw LIKE 'OWID%' THEN 1 ELSE 0 END AS dq_owid_prefix,
  CASE WHEN c.o_type IS NOT NULL THEN 1 ELSE 0 END AS dq_overridden,
  CASE WHEN c.entity_type = 'country' AND COALESCE(c.o_continent, k.owid_region) IS NULL THEN 1 ELSE 0 END AS dq_no_continent,
  c.n_iso, c.first_year, c.last_year, c.n_rows
FROM cls c
LEFT JOIN ref_continents k ON c.iso_raw = upper(trim(k.code));

-- 3. CO2 subset, typed (joined on entity name + year; ISO codes are cross-checked in 05)
CREATE OR REPLACE TABLE cln_co2 AS
WITH d AS (
  SELECT x.*, ROW_NUMBER() OVER (PARTITION BY trim(country), trim(year) ORDER BY co2 DESC NULLS LAST) AS rn FROM cln_co2_distinct x
)
SELECT trim(country) AS entity, TRY_CAST(trim(year) AS INT) AS year, NULLIF(upper(trim(iso_code)), '') AS iso_code,
       TRY_CAST(NULLIF(trim(co2), '') AS DOUBLE) AS co2_mt,
       TRY_CAST(NULLIF(trim(co2_per_capita), '') AS DOUBLE) AS co2_per_capita_t,
       TRY_CAST(NULLIF(trim(coal_co2), '') AS DOUBLE) AS coal_co2_mt,
       TRY_CAST(NULLIF(trim(oil_co2), '') AS DOUBLE) AS oil_co2_mt,
       TRY_CAST(NULLIF(trim(gas_co2), '') AS DOUBLE) AS gas_co2_mt,
       TRY_CAST(NULLIF(trim(consumption_co2), '') AS DOUBLE) AS consumption_co2_mt,
       TRY_CAST(NULLIF(trim(co2_per_unit_energy), '') AS DOUBLE) AS co2_per_kwh_energy_kg,
       TRY_CAST(NULLIF(trim(cumulative_co2), '') AS DOUBLE) AS cumulative_co2_mt
FROM d WHERE rn = 1;

-- 4. typed energy rows: '' -> NULL, numbers via TRY_CAST, entity attributes, GDP per capita, CO2 join
CREATE OR REPLACE TABLE cln_energy_typed AS
WITH d AS (
  SELECT x.*, ROW_NUMBER() OVER (PARTITION BY trim(country), trim(year)
                                 ORDER BY primary_energy_consumption DESC NULLS LAST, electricity_generation DESC NULLS LAST) AS rn
  FROM cln_energy_distinct x
)
SELECT
  trim(e.country) AS entity,
  TRY_CAST(trim(e.year) AS INT) AS year,
  NULLIF(upper(trim(e.iso_code)), '') AS iso_code_raw,
  TRY_CAST(NULLIF(trim(e.population), '') AS BIGINT) AS population,
  TRY_CAST(NULLIF(trim(e.gdp), '') AS DOUBLE) AS gdp,
  TRY_CAST(NULLIF(trim(e.primary_energy_consumption), '') AS DOUBLE) AS primary_energy_consumption,
  TRY_CAST(NULLIF(trim(e.energy_per_capita), '') AS DOUBLE) AS energy_per_capita,
  TRY_CAST(NULLIF(trim(e.energy_per_gdp), '') AS DOUBLE) AS energy_per_gdp,
  TRY_CAST(NULLIF(trim(e.fossil_fuel_consumption), '') AS DOUBLE) AS fossil_fuel_consumption,
  TRY_CAST(NULLIF(trim(e.low_carbon_consumption), '') AS DOUBLE) AS low_carbon_consumption,
  TRY_CAST(NULLIF(trim(e.renewables_consumption), '') AS DOUBLE) AS renewables_consumption,
  TRY_CAST(NULLIF(trim(e.coal_consumption), '') AS DOUBLE) AS coal_consumption,
  TRY_CAST(NULLIF(trim(e.oil_consumption), '') AS DOUBLE) AS oil_consumption,
  TRY_CAST(NULLIF(trim(e.gas_consumption), '') AS DOUBLE) AS gas_consumption,
  TRY_CAST(NULLIF(trim(e.nuclear_consumption), '') AS DOUBLE) AS nuclear_consumption,
  TRY_CAST(NULLIF(trim(e.hydro_consumption), '') AS DOUBLE) AS hydro_consumption,
  TRY_CAST(NULLIF(trim(e.solar_consumption), '') AS DOUBLE) AS solar_consumption,
  TRY_CAST(NULLIF(trim(e.wind_consumption), '') AS DOUBLE) AS wind_consumption,
  TRY_CAST(NULLIF(trim(e.biofuel_consumption), '') AS DOUBLE) AS biofuel_consumption,
  TRY_CAST(NULLIF(trim(e.other_renewable_consumption), '') AS DOUBLE) AS other_renewable_consumption,
  TRY_CAST(NULLIF(trim(e.fossil_share_energy), '') AS DOUBLE) AS fossil_share_energy,
  TRY_CAST(NULLIF(trim(e.low_carbon_share_energy), '') AS DOUBLE) AS low_carbon_share_energy,
  TRY_CAST(NULLIF(trim(e.renewables_share_energy), '') AS DOUBLE) AS renewables_share_energy,
  TRY_CAST(NULLIF(trim(e.coal_share_energy), '') AS DOUBLE) AS coal_share_energy,
  TRY_CAST(NULLIF(trim(e.oil_share_energy), '') AS DOUBLE) AS oil_share_energy,
  TRY_CAST(NULLIF(trim(e.gas_share_energy), '') AS DOUBLE) AS gas_share_energy,
  TRY_CAST(NULLIF(trim(e.nuclear_share_energy), '') AS DOUBLE) AS nuclear_share_energy,
  TRY_CAST(NULLIF(trim(e.hydro_share_energy), '') AS DOUBLE) AS hydro_share_energy,
  TRY_CAST(NULLIF(trim(e.solar_share_energy), '') AS DOUBLE) AS solar_share_energy,
  TRY_CAST(NULLIF(trim(e.wind_share_energy), '') AS DOUBLE) AS wind_share_energy,
  TRY_CAST(NULLIF(trim(e.biofuel_share_energy), '') AS DOUBLE) AS biofuel_share_energy,
  TRY_CAST(NULLIF(trim(e.other_renewables_share_energy), '') AS DOUBLE) AS other_renewables_share_energy,
  TRY_CAST(NULLIF(trim(e.electricity_generation), '') AS DOUBLE) AS electricity_generation,
  TRY_CAST(NULLIF(trim(e.electricity_demand), '') AS DOUBLE) AS electricity_demand,
  TRY_CAST(NULLIF(trim(e.per_capita_electricity), '') AS DOUBLE) AS per_capita_electricity,
  TRY_CAST(NULLIF(trim(e.net_elec_imports), '') AS DOUBLE) AS net_elec_imports,
  TRY_CAST(NULLIF(trim(e.coal_electricity), '') AS DOUBLE) AS coal_electricity,
  TRY_CAST(NULLIF(trim(e.oil_electricity), '') AS DOUBLE) AS oil_electricity,
  TRY_CAST(NULLIF(trim(e.gas_electricity), '') AS DOUBLE) AS gas_electricity,
  TRY_CAST(NULLIF(trim(e.nuclear_electricity), '') AS DOUBLE) AS nuclear_electricity,
  TRY_CAST(NULLIF(trim(e.hydro_electricity), '') AS DOUBLE) AS hydro_electricity,
  TRY_CAST(NULLIF(trim(e.solar_electricity), '') AS DOUBLE) AS solar_electricity,
  TRY_CAST(NULLIF(trim(e.wind_electricity), '') AS DOUBLE) AS wind_electricity,
  TRY_CAST(NULLIF(trim(e.biofuel_electricity), '') AS DOUBLE) AS biofuel_electricity,
  TRY_CAST(NULLIF(trim(e.other_renewable_exc_biofuel_electricity), '') AS DOUBLE) AS other_renewable_exc_biofuel_electricity,
  TRY_CAST(NULLIF(trim(e.fossil_electricity), '') AS DOUBLE) AS fossil_electricity,
  TRY_CAST(NULLIF(trim(e.low_carbon_electricity), '') AS DOUBLE) AS low_carbon_electricity,
  TRY_CAST(NULLIF(trim(e.renewables_electricity), '') AS DOUBLE) AS renewables_electricity,
  TRY_CAST(NULLIF(trim(e.fossil_share_elec), '') AS DOUBLE) AS fossil_share_elec,
  TRY_CAST(NULLIF(trim(e.low_carbon_share_elec), '') AS DOUBLE) AS low_carbon_share_elec,
  TRY_CAST(NULLIF(trim(e.renewables_share_elec), '') AS DOUBLE) AS renewables_share_elec,
  TRY_CAST(NULLIF(trim(e.coal_share_elec), '') AS DOUBLE) AS coal_share_elec,
  TRY_CAST(NULLIF(trim(e.oil_share_elec), '') AS DOUBLE) AS oil_share_elec,
  TRY_CAST(NULLIF(trim(e.gas_share_elec), '') AS DOUBLE) AS gas_share_elec,
  TRY_CAST(NULLIF(trim(e.nuclear_share_elec), '') AS DOUBLE) AS nuclear_share_elec,
  TRY_CAST(NULLIF(trim(e.hydro_share_elec), '') AS DOUBLE) AS hydro_share_elec,
  TRY_CAST(NULLIF(trim(e.solar_share_elec), '') AS DOUBLE) AS solar_share_elec,
  TRY_CAST(NULLIF(trim(e.wind_share_elec), '') AS DOUBLE) AS wind_share_elec,
  TRY_CAST(NULLIF(trim(e.carbon_intensity_elec), '') AS DOUBLE) AS carbon_intensity_elec,
  TRY_CAST(NULLIF(trim(e.greenhouse_gas_emissions), '') AS DOUBLE) AS greenhouse_gas_emissions,
  CASE WHEN TRY_CAST(NULLIF(trim(e.year), '') AS INT) IS NULL THEN 1 ELSE 0 END AS dq_bad_year
FROM d e WHERE e.rn = 1;

-- 5. per-year coverage of real countries: the last years are only partly filled (EIA ends 2023, EI covers ~80 countries in 2024,
--    Ember 2025 is a part-year release), so 'latest complete year' is chosen per metric from this table, not assumed.
CREATE OR REPLACE TABLE cln_year_coverage AS
SELECT t.year,
       SUM(CASE WHEN t.primary_energy_consumption IS NOT NULL THEN 1 ELSE 0 END) AS countries_primary_energy,
       SUM(CASE WHEN t.fossil_share_energy IS NOT NULL THEN 1 ELSE 0 END)        AS countries_energy_mix,
       SUM(CASE WHEN t.electricity_generation IS NOT NULL THEN 1 ELSE 0 END)     AS countries_electricity,
       SUM(CASE WHEN t.carbon_intensity_elec IS NOT NULL THEN 1 ELSE 0 END)      AS countries_carbon_intensity,
       SUM(CASE WHEN t.gdp IS NOT NULL THEN 1 ELSE 0 END)                        AS countries_gdp
FROM cln_energy_typed t JOIN cln_entity n ON t.entity = n.entity
WHERE n.entity_type = 'country'
GROUP BY t.year;

CREATE OR REPLACE TABLE cln_latest_year AS
SELECT
  (SELECT max(year) FROM cln_year_coverage WHERE countries_primary_energy >= 0.9 * (SELECT max(countries_primary_energy) FROM cln_year_coverage)) AS y_primary_all,
  (SELECT max(year) FROM cln_year_coverage WHERE countries_energy_mix >= 0.9 * (SELECT max(countries_energy_mix) FROM cln_year_coverage)) AS y_energy_mix,
  (SELECT max(year) FROM cln_year_coverage WHERE countries_electricity >= 0.9 * (SELECT max(countries_electricity) FROM cln_year_coverage)) AS y_electricity,
  (SELECT max(year) FROM cln_year_coverage WHERE countries_carbon_intensity >= 0.9 * (SELECT max(countries_carbon_intensity) FROM cln_year_coverage)) AS y_carbon_intensity,
  (SELECT max(year) FROM cln_year_coverage WHERE countries_gdp >= 0.9 * (SELECT max(countries_gdp) FROM cln_year_coverage)) AS y_gdp,
  (SELECT max(year) FROM cln_year_coverage) AS y_max;

-- 6. clean entity-year table with flags. Outliers are flagged, not deleted.
CREATE OR REPLACE TABLE cln_energy AS
WITH p AS (   -- per-year 95th percentile of energy per capita among countries (for the outlier rule)
  SELECT t.year, percentile_approx(t.energy_per_capita, 0.95) AS p95_epc
  FROM cln_energy_typed t JOIN cln_entity n ON t.entity = n.entity
  WHERE n.entity_type = 'country' AND t.energy_per_capita IS NOT NULL
  GROUP BY t.year
)
SELECT
  n.entity_key, t.entity, n.iso_code, n.entity_type, n.entity_group, n.continent, t.year,
  t.population, t.gdp,
  CASE WHEN t.population > 0 AND t.gdp IS NOT NULL THEN ROUND(t.gdp / t.population, 1) END AS gdp_per_capita,
  t.primary_energy_consumption, t.energy_per_capita, t.energy_per_gdp,
  t.fossil_fuel_consumption, t.low_carbon_consumption, t.renewables_consumption,
  t.coal_consumption, t.oil_consumption, t.gas_consumption, t.nuclear_consumption, t.hydro_consumption, t.solar_consumption,
  t.wind_consumption, t.biofuel_consumption, t.other_renewable_consumption,
  t.fossil_share_energy, t.low_carbon_share_energy, t.renewables_share_energy, t.coal_share_energy, t.oil_share_energy, t.gas_share_energy,
  t.nuclear_share_energy, t.hydro_share_energy, t.solar_share_energy, t.wind_share_energy, t.biofuel_share_energy, t.other_renewables_share_energy,
  t.electricity_generation, t.electricity_demand, t.per_capita_electricity, t.net_elec_imports,
  t.coal_electricity, t.oil_electricity, t.gas_electricity, t.nuclear_electricity, t.hydro_electricity, t.solar_electricity, t.wind_electricity,
  t.biofuel_electricity, t.other_renewable_exc_biofuel_electricity, t.fossil_electricity, t.low_carbon_electricity, t.renewables_electricity,
  t.fossil_share_elec, t.low_carbon_share_elec, t.renewables_share_elec, t.coal_share_elec, t.oil_share_elec, t.gas_share_elec,
  t.nuclear_share_elec, t.hydro_share_elec, t.solar_share_elec, t.wind_share_elec,
  CASE WHEN t.solar_share_elec IS NOT NULL OR t.wind_share_elec IS NOT NULL
       THEN ROUND(COALESCE(t.solar_share_elec, 0) + COALESCE(t.wind_share_elec, 0), 3) END AS solar_wind_share_elec,
  t.carbon_intensity_elec, t.greenhouse_gas_emissions,
  c.co2_mt, c.co2_per_capita_t, c.coal_co2_mt, c.consumption_co2_mt, c.co2_per_kwh_energy_kg,
  CASE WHEN t.primary_energy_consumption IS NOT NULL OR t.electricity_generation IS NOT NULL THEN 1 ELSE 0 END AS has_energy_data,
  CASE WHEN t.year > (SELECT y_electricity FROM cln_latest_year) THEN 1 ELSE 0 END AS is_partial_year,
  CASE WHEN n.entity_type = 'country' AND t.energy_per_capita > 3 * p.p95_epc THEN 1 ELSE 0 END AS dq_epc_outlier,
  -- reported grid carbon intensity above 900 g/kWh AND above a generous ceiling implied by the fuel mix
  -- (coal 1,100 / oil 900 / gas 700 / other 50 g CO2e per kWh): physically implausible for that mix
  CASE WHEN t.carbon_intensity_elec > 900 AND t.carbon_intensity_elec > (11.0 * COALESCE(t.coal_share_elec, 0) + 9.0 * COALESCE(t.oil_share_elec, 0) + 7.0 * COALESCE(t.gas_share_elec, 0)
         + 0.5 * (100 - COALESCE(t.coal_share_elec, 0) - COALESCE(t.oil_share_elec, 0) - COALESCE(t.gas_share_elec, 0)))
       THEN 1 ELSE 0 END AS dq_ci_implausible,
  CASE WHEN ABS(t.fossil_share_energy + t.low_carbon_share_energy - 100) > 0.5 THEN 1 ELSE 0 END AS dq_mix_sum_mismatch,
  CASE WHEN t.electricity_generation > 0 AND ABS(COALESCE(t.coal_electricity, 0) + COALESCE(t.oil_electricity, 0) + COALESCE(t.gas_electricity, 0)
         + COALESCE(t.nuclear_electricity, 0) + COALESCE(t.hydro_electricity, 0) + COALESCE(t.solar_electricity, 0) + COALESCE(t.wind_electricity, 0)
         + COALESCE(t.biofuel_electricity, 0) + COALESCE(t.other_renewable_exc_biofuel_electricity, 0) - t.electricity_generation)
         > GREATEST(0.02 * t.electricity_generation, 0.1) THEN 1 ELSE 0 END AS dq_elec_sources_incomplete,
  CASE WHEN LEAST(COALESCE(t.fossil_share_energy, 0), COALESCE(t.renewables_share_energy, 0), COALESCE(t.low_carbon_share_elec, 0),
                  COALESCE(t.fossil_share_elec, 0), COALESCE(t.renewables_share_elec, 0)) < 0
         OR GREATEST(COALESCE(t.fossil_share_energy, 0), COALESCE(t.renewables_share_energy, 0), COALESCE(t.low_carbon_share_elec, 0),
                     COALESCE(t.fossil_share_elec, 0), COALESCE(t.renewables_share_elec, 0)) > 100.001 THEN 1 ELSE 0 END AS dq_share_out_of_range,
  CASE WHEN c.iso_code IS NOT NULL AND n.iso_code IS NOT NULL AND c.iso_code <> n.iso_code THEN 1 ELSE 0 END AS dq_co2_iso_mismatch,
  CASE WHEN c.entity IS NULL THEN 1 ELSE 0 END AS dq_no_co2_row
FROM cln_energy_typed t
JOIN cln_entity n ON t.entity = n.entity
LEFT JOIN p ON t.year = p.year
LEFT JOIN cln_co2 c ON t.entity = c.entity AND t.year = c.year
WHERE t.year IS NOT NULL;

-- 7. long energy mix (one row per entity x year x source) for countries, World and the six OWID continents, 1965+.
--    other_renewable = geothermal, biomass and other (excludes biofuels, which have their own row) in both energy and electricity.
CREATE OR REPLACE TABLE cln_mix_long AS
WITH b AS (
  SELECT * FROM cln_energy
  WHERE has_energy_data = 1 AND year >= 1965 AND (entity_type = 'country' OR entity_group IN ('World', 'Continent (OWID)'))
), u AS (
  SELECT entity_key, year, 'coal' AS source, coal_consumption AS energy_twh, coal_share_energy AS share_energy_pct, coal_electricity AS elec_twh, coal_share_elec AS share_elec_pct FROM b
  UNION ALL SELECT entity_key, year, 'oil', oil_consumption, oil_share_energy, oil_electricity, oil_share_elec FROM b
  UNION ALL SELECT entity_key, year, 'gas', gas_consumption, gas_share_energy, gas_electricity, gas_share_elec FROM b
  UNION ALL SELECT entity_key, year, 'nuclear', nuclear_consumption, nuclear_share_energy, nuclear_electricity, nuclear_share_elec FROM b
  UNION ALL SELECT entity_key, year, 'hydro', hydro_consumption, hydro_share_energy, hydro_electricity, hydro_share_elec FROM b
  UNION ALL SELECT entity_key, year, 'solar', solar_consumption, solar_share_energy, solar_electricity, solar_share_elec FROM b
  UNION ALL SELECT entity_key, year, 'wind', wind_consumption, wind_share_energy, wind_electricity, wind_share_elec FROM b
  UNION ALL SELECT entity_key, year, 'biofuel', biofuel_consumption, biofuel_share_energy, biofuel_electricity,
                   CASE WHEN electricity_generation > 0 THEN ROUND(100.0 * biofuel_electricity / electricity_generation, 3) END FROM b
  UNION ALL SELECT entity_key, year, 'other_renewable', other_renewable_consumption, other_renewables_share_energy, other_renewable_exc_biofuel_electricity,
                   CASE WHEN electricity_generation > 0 THEN ROUND(100.0 * other_renewable_exc_biofuel_electricity / electricity_generation, 3) END FROM b
)
SELECT * FROM u WHERE energy_twh IS NOT NULL OR elec_twh IS NOT NULL;
