-- 05_quality_checks.sql  Data-quality evidence: before/after counts, issue counts, null rates, assertions (Spark SQL dialect)

CREATE OR REPLACE TABLE dq_row_counts AS
SELECT 'owid-energy-data rows' AS entity, (SELECT COUNT(*) FROM stg_energy) AS raw_rows, (SELECT COUNT(*) FROM cln_energy_distinct) AS distinct_rows,
       (SELECT COUNT(*) FROM cln_energy) AS clean_rows, 'entity x year (all entities)' AS grain
UNION ALL SELECT 'owid-co2-data rows', (SELECT COUNT(*) FROM stg_co2), (SELECT COUNT(*) FROM cln_co2_distinct), (SELECT COUNT(*) FROM cln_co2), 'entity x year'
UNION ALL SELECT 'entities (country column)', NULL, NULL, (SELECT COUNT(*) FROM cln_entity), 'country / historical country / aggregate'
UNION ALL SELECT 'real countries', NULL, NULL, (SELECT COUNT(*) FROM cln_entity WHERE entity_type = 'country'), 'ISO 3166 alpha-3 (+ Kosovo)'
UNION ALL SELECT 'fact_energy_year', NULL, NULL, (SELECT COUNT(*) FROM fact_energy_year), 'entity x year with any energy or electricity value'
UNION ALL SELECT 'fact_energy_year (countries only)', NULL, NULL, (SELECT COUNT(*) FROM fact_energy_year f JOIN dim_entity d ON f.entity_key = d.entity_key
       WHERE d.is_country = 1), 'country x year'
UNION ALL SELECT 'fact_energy_mix', NULL, NULL, (SELECT COUNT(*) FROM fact_energy_mix), 'entity x year x source (countries, World, continents, 1965+)'
UNION ALL SELECT 'dim_entity', NULL, NULL, (SELECT COUNT(*) FROM dim_entity), 'entity'
UNION ALL SELECT 'dim_year', NULL, NULL, (SELECT COUNT(*) FROM dim_year), 'year'
UNION ALL SELECT 'dim_source', NULL, NULL, (SELECT COUNT(*) FROM dim_source), 'energy source';

CREATE OR REPLACE TABLE dq_null_rates AS
WITH c AS (SELECT * FROM cln_energy WHERE entity_type = 'country')
SELECT 'country-years (all)' AS entity, 'primary_energy_consumption' AS column_name,
       ROUND(100.0 * SUM(CASE WHEN primary_energy_consumption IS NULL THEN 1 ELSE 0 END) / COUNT(*), 2) AS null_pct,
       'early years and small countries have no energy data; kept as NULL' AS treatment FROM c
UNION ALL SELECT 'country-years 2000+', 'primary_energy_consumption', ROUND(100.0 * SUM(CASE WHEN primary_energy_consumption IS NULL THEN 1 ELSE 0 END) / COUNT(*), 2),
       '2024 only for ~79 Energy Institute countries (EIA ends 2023)' FROM c WHERE year >= 2000
UNION ALL SELECT 'country-years 2000+', 'fossil_share_energy (energy mix)', ROUND(100.0 * SUM(CASE WHEN fossil_share_energy IS NULL THEN 1 ELSE 0 END) / COUNT(*), 2),
       'mix only for Energy Institute countries; others in EI residual regions' FROM c WHERE year >= 2000
UNION ALL SELECT 'country-years 2000+', 'electricity_generation', ROUND(100.0 * SUM(CASE WHEN electricity_generation IS NULL THEN 1 ELSE 0 END) / COUNT(*), 2),
       'Ember covers ~214 countries 2000-2024' FROM c WHERE year >= 2000
UNION ALL SELECT 'country-years 2000+', 'carbon_intensity_elec', ROUND(100.0 * SUM(CASE WHEN carbon_intensity_elec IS NULL THEN 1 ELSE 0 END) / COUNT(*), 2),
       'Ember; implausible values flagged' FROM c WHERE year >= 2000
UNION ALL SELECT 'country-years 2000+', 'gdp', ROUND(100.0 * SUM(CASE WHEN gdp IS NULL THEN 1 ELSE 0 END) / COUNT(*), 2),
       'Maddison GDP ends 2022 and misses small countries' FROM c WHERE year >= 2000
UNION ALL SELECT 'country-years 2000+', 'co2_mt (joined)', ROUND(100.0 * SUM(CASE WHEN co2_mt IS NULL THEN 1 ELSE 0 END) / COUNT(*), 2),
       'CO2 file ends 2024; joined on entity + year' FROM c WHERE year >= 2000
UNION ALL SELECT 'country-years 2000+', 'population', ROUND(100.0 * SUM(CASE WHEN population IS NULL THEN 1 ELSE 0 END) / COUNT(*), 2),
       'per-capita measures NULL where missing' FROM c WHERE year >= 2000;

CREATE OR REPLACE TABLE dq_issues AS
SELECT 'exact duplicate rows dropped (energy)' AS check_name, (SELECT COUNT(*) FROM stg_energy) - (SELECT COUNT(*) FROM cln_energy_distinct) AS affected_rows
UNION ALL SELECT 'duplicate entity x year keys (energy, after exact dedupe)', (SELECT COUNT(*) FROM cln_energy_distinct) - (SELECT COUNT(*) FROM cln_energy_typed)
UNION ALL SELECT 'rows with unparseable year dropped', (SELECT COUNT(*) FROM cln_energy_typed WHERE year IS NULL)
UNION ALL SELECT 'aggregate rows (World, continents, income groups, EI/EIA/Ember/Shift regions) kept out of country rankings',
       (SELECT COUNT(*) FROM cln_energy WHERE entity_type = 'aggregate')
UNION ALL SELECT 'aggregate entities with empty iso_code', (SELECT COUNT(*) FROM cln_entity WHERE entity_type = 'aggregate' AND iso_code IS NULL)
UNION ALL SELECT 'entities with OWID_ iso prefix', (SELECT SUM(dq_owid_prefix) FROM cln_entity)
UNION ALL SELECT 'historical-country rows (USSR, Yugoslavia, Czechoslovakia, East/West Germany, Serbia and Montenegro)',
       (SELECT COUNT(*) FROM cln_energy WHERE entity_type = 'historical_country')
UNION ALL SELECT 'Kosovo rows with empty iso_code (assigned OWID_KOS, kept as a country)', (SELECT COUNT(*) FROM cln_energy WHERE entity = 'Kosovo')
UNION ALL SELECT 'Antarctica rows (ISO ATA, no OWID continent; continent set by override)', (SELECT COUNT(*) FROM cln_energy WHERE entity = 'Antarctica')
UNION ALL SELECT 'entity-years with population/GDP only, no energy value (left out of facts)', (SELECT COUNT(*) FROM cln_energy WHERE has_energy_data = 0)
UNION ALL SELECT 'part-year rows after the latest complete electricity year (flagged provisional)', (SELECT SUM(is_partial_year) FROM cln_energy)
UNION ALL SELECT 'energy per capita > 3x the year''s country p95 (flagged; refinery / tiny-population territories)', (SELECT SUM(dq_epc_outlier) FROM cln_energy)
UNION ALL SELECT 'grid carbon intensity implausible for its fuel mix (flagged, out of intensity ranking)', (SELECT SUM(dq_ci_implausible) FROM cln_energy)
UNION ALL SELECT 'electricity source breakdown incomplete (sources <> generation by > 2%, nearly all pre-2000)', (SELECT SUM(dq_elec_sources_incomplete) FROM cln_energy)
UNION ALL SELECT 'energy-mix shares outside 0..100', (SELECT SUM(dq_share_out_of_range) FROM cln_energy)
UNION ALL SELECT 'fossil + low-carbon share of energy <> 100 (> 0.5 pp)', (SELECT SUM(dq_mix_sum_mismatch) FROM cln_energy)
UNION ALL SELECT 'energy rows with no CO2 row to join', (SELECT SUM(dq_no_co2_row) FROM cln_energy WHERE has_energy_data = 1)
UNION ALL SELECT 'CO2 vs energy ISO code mismatches', (SELECT SUM(dq_co2_iso_mismatch) FROM cln_energy)
UNION ALL SELECT 'double counting avoided: naive SUM of primary energy over ALL rows in 2023, % of World',
       (SELECT CAST(ROUND(100.0 * SUM(primary_energy_consumption) / (SELECT primary_energy_consumption FROM cln_energy WHERE entity = 'World' AND year = 2023), 0) AS BIGINT)
        FROM cln_energy WHERE year = 2023)
UNION ALL SELECT 'RI: clean energy rows lost in dim joins', (SELECT COUNT(*) FROM cln_energy WHERE has_energy_data = 1) - (SELECT COUNT(*) FROM fact_energy_year);

-- Reconciliation checks (sum of countries = World / OWID continent rows) only make sense on the full file: on the committed sample
-- (about a quarter of the countries) they are reported as SKIP instead of PASS. full_data = 1 when >= 200 real countries are present.
CREATE OR REPLACE TABLE dq_assertions AS
WITH l AS (SELECT * FROM cln_latest_year),
fd AS (SELECT CASE WHEN COUNT(*) >= 200 THEN 1 ELSE 0 END AS full_data FROM cln_entity WHERE entity_type = 'country'),
c AS (
  SELECT 'clean rows = distinct raw rows (energy)' AS check_name,
         ABS((SELECT COUNT(*) FROM cln_energy) - (SELECT COUNT(*) FROM (SELECT DISTINCT * FROM stg_energy) d)) AS failed_rows
  UNION ALL SELECT 'one row per entity x year (energy)', (SELECT COUNT(*) FROM (SELECT entity, year FROM cln_energy GROUP BY entity, year HAVING COUNT(*) > 1) x)
  UNION ALL SELECT 'one row per entity x year (CO2)', (SELECT COUNT(*) FROM (SELECT entity, year FROM cln_co2 GROUP BY entity, year HAVING COUNT(*) > 1) x)
  UNION ALL SELECT 'year parsed and within 1900..2030', (SELECT COUNT(*) FROM cln_energy WHERE year IS NULL OR year < 1900 OR year > 2030)
  UNION ALL SELECT 'entity_key unique', (SELECT COUNT(*) - COUNT(DISTINCT entity_key) FROM dim_entity)
  UNION ALL SELECT 'every entity classified (country / historical / aggregate)', (SELECT COUNT(*) FROM cln_entity
         WHERE entity_type NOT IN ('country', 'historical_country', 'aggregate') OR entity_type IS NULL)
  UNION ALL SELECT 'every real country has a continent', (SELECT SUM(dq_no_continent) FROM cln_entity)
  UNION ALL SELECT 'country ISO codes are 3 letters (OWID_KOS for Kosovo)', (SELECT COUNT(*) FROM cln_entity WHERE entity_type = 'country'
         AND NOT (regexp_like(iso_code, '^[A-Z]{3}$') OR iso_code = 'OWID_KOS'))
  UNION ALL SELECT 'no aggregate carries a plain ISO code', (SELECT COUNT(*) FROM cln_entity WHERE entity_type = 'aggregate' AND regexp_like(COALESCE(iso_code, ''), '^[A-Z]{3}$'))
  UNION ALL SELECT 'one ISO code per entity and no ISO code shared', (SELECT COUNT(*) FROM cln_entity WHERE n_iso > 1)
         + (SELECT COUNT(*) FROM (SELECT iso_code FROM cln_entity WHERE iso_code IS NOT NULL GROUP BY iso_code HAVING COUNT(*) > 1) x)
  UNION ALL SELECT 'CO2 ISO codes agree with energy ISO codes', (SELECT SUM(dq_co2_iso_mismatch) FROM cln_energy)
  UNION ALL SELECT 'shares within 0..100', (SELECT SUM(dq_share_out_of_range) FROM cln_energy)
  UNION ALL SELECT 'fossil + low-carbon share of energy = 100 (+/- 0.5)', (SELECT SUM(dq_mix_sum_mismatch) FROM cln_energy)
  UNION ALL SELECT 'renewables share <= low-carbon share (energy and electricity)', (SELECT COUNT(*) FROM cln_energy
         WHERE renewables_share_energy > low_carbon_share_energy + 0.01 OR renewables_share_elec > low_carbon_share_elec + 0.01)
  UNION ALL SELECT 'no negative consumption or generation', (SELECT COUNT(*) FROM cln_energy WHERE primary_energy_consumption < 0 OR electricity_generation < 0
         OR coal_consumption < 0 OR oil_consumption < 0 OR gas_consumption < 0 OR solar_electricity < 0 OR wind_electricity < 0)
  UNION ALL SELECT 'countries 2000+: electricity sources sum to generation (+/- 2%)', (SELECT SUM(dq_elec_sources_incomplete) FROM cln_energy
         WHERE entity_type = 'country' AND year >= 2000)
  UNION ALL SELECT 'countries 2000+: fossil + low-carbon electricity = generation (+/- 1%)', (SELECT COUNT(*) FROM cln_energy WHERE entity_type = 'country'
         AND year >= 2000 AND electricity_generation > 0 AND ABS(COALESCE(fossil_electricity, 0) + COALESCE(low_carbon_electricity, 0) - electricity_generation)
         > GREATEST(0.01 * electricity_generation, 0.05))
  UNION ALL SELECT 'nine source shares of energy sum to 100 (+/- 0.5) where all present', (SELECT COUNT(*) FROM (SELECT entity_key, year FROM fact_energy_mix
         GROUP BY entity_key, year HAVING COUNT(share_energy_pct) = 9 AND ABS(SUM(share_energy_pct) - 100) > 0.5) x)
  UNION ALL SELECT 'sum of countries = World electricity (+/- 1%), 2000..latest [full data only]', (SELECT COUNT(*) FROM cln_energy w JOIN (SELECT year, SUM(electricity_generation) AS s
         FROM cln_energy WHERE entity_type = 'country' GROUP BY year) s ON w.year = s.year
         WHERE w.entity = 'World' AND w.year BETWEEN 2000 AND (SELECT y_electricity FROM l) AND ABS(s.s - w.electricity_generation) > 0.01 * w.electricity_generation)
  UNION ALL SELECT 'sum of countries = World primary energy (+/- 1%), 2000..latest all-country year [full data only]', (SELECT COUNT(*) FROM cln_energy w JOIN (SELECT year,
         SUM(primary_energy_consumption) AS s FROM cln_energy WHERE entity_type = 'country' GROUP BY year) s ON w.year = s.year
         WHERE w.entity = 'World' AND w.year BETWEEN 2000 AND (SELECT y_primary_all FROM l) AND ABS(s.s - w.primary_energy_consumption) > 0.01 * w.primary_energy_consumption)
  UNION ALL SELECT 'bottom-up continent low-carbon electricity share = OWID continent row (+/- 0.05 pp) [full data only]', (SELECT COUNT(*) FROM a_region_elec_trend
         WHERE ABS(low_carbon_share_elec - owid_region_low_carbon_share_elec) > 0.05 OR owid_region_low_carbon_share_elec IS NULL)
  UNION ALL SELECT 'World row has primary energy for every year 1965..latest mix year', (SELECT (SELECT y_energy_mix FROM l) - 1965 + 1 - COUNT(*) FROM cln_energy
         WHERE entity = 'World' AND year BETWEEN 1965 AND (SELECT y_energy_mix FROM l) AND primary_energy_consumption IS NOT NULL)
  UNION ALL SELECT 'all six OWID continent rows present', (SELECT 6 - COUNT(*) FROM cln_entity WHERE entity_group = 'Continent (OWID)')
  UNION ALL SELECT 'fact_energy_year keeps every clean row with energy data (RI)', (SELECT ABS((SELECT COUNT(*) FROM cln_energy WHERE has_energy_data = 1)
         - (SELECT COUNT(*) FROM fact_energy_year)))
  UNION ALL SELECT 'fact keys exist in dim_entity, dim_year, dim_source', (SELECT COUNT(*) FROM fact_energy_year f LEFT JOIN dim_entity d ON f.entity_key = d.entity_key
         LEFT JOIN dim_year y ON f.year = y.year WHERE d.entity_key IS NULL OR y.year IS NULL)
         + (SELECT COUNT(*) FROM fact_energy_mix f LEFT JOIN dim_entity d ON f.entity_key = d.entity_key LEFT JOIN dim_source s ON f.source_key = s.source_key
            WHERE d.entity_key IS NULL OR s.source_key IS NULL)
  UNION ALL SELECT 'country rankings contain no aggregates or historical states', (SELECT COUNT(*) FROM (
         SELECT entity FROM a_transitions UNION ALL SELECT entity FROM a_coal_phaseout UNION ALL SELECT entity FROM a_top_consumers
         UNION ALL SELECT entity FROM a_carbon_intensity UNION ALL SELECT entity FROM a_energy_gdp UNION ALL SELECT entity FROM a_decoupling) r
         JOIN cln_entity n ON r.entity = n.entity WHERE n.entity_type <> 'country')
  UNION ALL SELECT 'every analysed raw column is documented in the codebook', (SELECT COUNT(*) FROM information_schema.columns ic
         LEFT JOIN stg_energy_codebook cb ON ic.column_name = cb.column
         WHERE ic.table_name = 'cln_energy_typed' AND ic.column_name NOT IN ('entity', 'iso_code_raw', 'dq_bad_year') AND cb.column IS NULL)
)
SELECT check_name, COALESCE(failed_rows, 0) AS failed_rows,
       CASE WHEN check_name LIKE '%[full data only]' AND (SELECT full_data FROM fd) = 0 THEN 'SKIP'
            WHEN COALESCE(failed_rows, 0) = 0 THEN 'PASS' ELSE 'FAIL' END AS status
FROM c;
