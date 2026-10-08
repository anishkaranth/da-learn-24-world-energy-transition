-- 04_analysis.sql  KPIs and business questions (Spark SQL dialect).
-- Country rankings use real countries only (entity_type = 'country': ISO code, no OWID aggregates, no historical states).
-- World and continent figures use OWID's own aggregate rows unless a table says it is a bottom-up sum of countries.
-- 'Latest year' is chosen per metric from cln_latest_year (>= 90% of peak country coverage): energy mix 2024 (Energy Institute,
-- ~79 countries + World), electricity and carbon intensity 2024, GDP 2022, all-country primary energy 2023. 2025 is a part-year
-- Ember release (flagged is_partial_year) and is only shown where labelled as provisional.

CREATE OR REPLACE TEMP VIEW v_c AS
SELECT e.*, l.y_energy_mix, l.y_electricity, l.y_carbon_intensity, l.y_gdp, l.y_primary_all
FROM cln_energy e CROSS JOIN cln_latest_year l
WHERE e.entity_type = 'country' AND e.has_energy_data = 1;

CREATE OR REPLACE TEMP VIEW v_w AS
SELECT * FROM cln_energy WHERE entity = 'World';


-- Q2 world energy and electricity mix by year (OWID 'World' row)
CREATE OR REPLACE TABLE a_world_mix AS
SELECT year, ROUND(primary_energy_consumption, 0) AS primary_energy_twh, ROUND(energy_per_capita, 0) AS energy_per_capita_kwh,
       fossil_share_energy, low_carbon_share_energy, renewables_share_energy, coal_share_energy, oil_share_energy, gas_share_energy,
       nuclear_share_energy, hydro_share_energy, solar_share_energy, wind_share_energy,
       ROUND(electricity_generation, 0) AS electricity_twh, fossil_share_elec, low_carbon_share_elec, renewables_share_elec, coal_share_elec,
       gas_share_elec, oil_share_elec, nuclear_share_elec, hydro_share_elec, solar_share_elec, wind_share_elec, solar_wind_share_elec,
       ROUND(100 - COALESCE(fossil_share_elec, 0) - COALESCE(nuclear_share_elec, 0) - COALESCE(hydro_share_elec, 0)
                 - COALESCE(solar_share_elec, 0) - COALESCE(wind_share_elec, 0), 3) AS other_renewables_share_elec,
       carbon_intensity_elec, ROUND(coal_consumption, 0) AS coal_twh, ROUND(co2_mt, 0) AS co2_mt, is_partial_year
FROM v_w WHERE year >= 1965;

-- Q3 fossil vs low-carbon mix by region (OWID continent aggregates), 2000 vs latest
CREATE OR REPLACE TABLE a_region_mix AS
WITH l AS (SELECT * FROM cln_latest_year)
SELECT e.entity AS region, e.year,
       CASE WHEN e.year = 2000 THEN '2000' ELSE 'latest' END AS snapshot,
       ROUND(e.primary_energy_consumption, 0) AS primary_energy_twh, ROUND(e.energy_per_capita, 0) AS energy_per_capita_kwh,
       e.fossil_share_energy, e.nuclear_share_energy, e.renewables_share_energy, e.low_carbon_share_energy, e.coal_share_energy,
       e.oil_share_energy, e.gas_share_energy,
       ROUND(100.0 * e.primary_energy_consumption / w.primary_energy_consumption, 2) AS pct_world_energy,
       el.low_carbon_share_elec, el.coal_share_elec, el.carbon_intensity_elec
FROM cln_energy e
JOIN v_w w ON e.year = w.year
LEFT JOIN cln_energy el ON el.entity = e.entity AND el.year = e.year
WHERE (e.entity_group = 'Continent (OWID)' OR e.entity = 'World')
  AND e.year IN (2000, (SELECT y_energy_mix FROM l));

-- Q4 low-carbon share of electricity by continent, bottom-up from countries (2000..latest) vs OWID's continent row
CREATE OR REPLACE TABLE a_region_elec_trend AS
SELECT c.continent AS region, c.year,
       COUNT(*) AS countries,
       ROUND(SUM(c.electricity_generation), 1) AS electricity_twh,
       ROUND(100.0 * SUM(c.low_carbon_electricity) / SUM(c.electricity_generation), 2) AS low_carbon_share_elec,
       ROUND(100.0 * SUM(c.coal_electricity) / SUM(c.electricity_generation), 2) AS coal_share_elec,
       ROUND(100.0 * SUM(COALESCE(c.solar_electricity, 0) + COALESCE(c.wind_electricity, 0)) / SUM(c.electricity_generation), 2) AS solar_wind_share_elec,
       max(o.low_carbon_share_elec) AS owid_region_low_carbon_share_elec
FROM v_c c
LEFT JOIN cln_energy o ON o.entity = c.continent AND o.year = c.year
WHERE c.year BETWEEN 2000 AND c.y_electricity AND c.electricity_generation > 0 AND c.low_carbon_electricity IS NOT NULL
  AND c.continent <> 'Antarctica'
GROUP BY c.continent, c.year;

-- Q5 fastest electricity transitions since 2000: change in low-carbon share (countries generating >= 10 TWh in the latest year)
CREATE OR REPLACE TABLE a_transitions AS
WITH a AS (SELECT * FROM v_c WHERE year = 2000), b AS (SELECT * FROM v_c WHERE year = y_electricity)
SELECT ROW_NUMBER() OVER (ORDER BY b.low_carbon_share_elec - a.low_carbon_share_elec DESC) AS rnk,
       b.entity, b.continent, b.year AS latest_year, ROUND(b.electricity_generation, 1) AS electricity_twh_latest,
       ROUND(a.low_carbon_share_elec, 2) AS low_carbon_2000, ROUND(b.low_carbon_share_elec, 2) AS low_carbon_latest,
       ROUND(b.low_carbon_share_elec - a.low_carbon_share_elec, 2) AS change_pp,
       ROUND(b.solar_wind_share_elec - a.solar_wind_share_elec, 2) AS solar_wind_change_pp,
       ROUND(COALESCE(b.coal_share_elec, 0) - COALESCE(a.coal_share_elec, 0), 2) AS coal_change_pp,
       ROUND(COALESCE(b.nuclear_share_elec, 0) - COALESCE(a.nuclear_share_elec, 0), 2) AS nuclear_change_pp,
       ROUND(COALESCE(b.hydro_share_elec, 0) - COALESCE(a.hydro_share_elec, 0), 2) AS hydro_change_pp,
       -- geothermal, bioenergy and other renewables = the rest of the low-carbon change
       ROUND((b.low_carbon_share_elec - a.low_carbon_share_elec) - (COALESCE(b.solar_wind_share_elec, 0) - COALESCE(a.solar_wind_share_elec, 0))
             - (COALESCE(b.nuclear_share_elec, 0) - COALESCE(a.nuclear_share_elec, 0)) - (COALESCE(b.hydro_share_elec, 0) - COALESCE(a.hydro_share_elec, 0)), 2)
         AS other_renewables_change_pp,
       CASE GREATEST(COALESCE(b.solar_wind_share_elec, 0) - COALESCE(a.solar_wind_share_elec, 0), COALESCE(b.nuclear_share_elec, 0) - COALESCE(a.nuclear_share_elec, 0),
                     COALESCE(b.hydro_share_elec, 0) - COALESCE(a.hydro_share_elec, 0),
                     (b.low_carbon_share_elec - a.low_carbon_share_elec) - (COALESCE(b.solar_wind_share_elec, 0) - COALESCE(a.solar_wind_share_elec, 0))
                     - (COALESCE(b.nuclear_share_elec, 0) - COALESCE(a.nuclear_share_elec, 0)) - (COALESCE(b.hydro_share_elec, 0) - COALESCE(a.hydro_share_elec, 0)))
         WHEN COALESCE(b.solar_wind_share_elec, 0) - COALESCE(a.solar_wind_share_elec, 0) THEN 'solar + wind'
         WHEN COALESCE(b.nuclear_share_elec, 0) - COALESCE(a.nuclear_share_elec, 0) THEN 'nuclear'
         WHEN COALESCE(b.hydro_share_elec, 0) - COALESCE(a.hydro_share_elec, 0) THEN 'hydro'
         ELSE 'geothermal/bio' END AS main_driver
FROM a JOIN b ON a.entity_key = b.entity_key
WHERE b.electricity_generation >= 10 AND a.low_carbon_share_elec IS NOT NULL AND b.low_carbon_share_elec IS NOT NULL;

-- Q6 primary-energy transitions since 2000 (Energy Institute coverage, countries using >= 100 TWh)
CREATE OR REPLACE TABLE a_energy_transitions AS
WITH a AS (SELECT * FROM v_c WHERE year = 2000), b AS (SELECT * FROM v_c WHERE year = y_energy_mix)
SELECT ROW_NUMBER() OVER (ORDER BY b.fossil_share_energy - a.fossil_share_energy) AS rnk,
       b.entity, b.continent, b.year AS latest_year, ROUND(b.primary_energy_consumption, 0) AS primary_energy_twh_latest,
       ROUND(a.fossil_share_energy, 2) AS fossil_2000, ROUND(b.fossil_share_energy, 2) AS fossil_latest,
       ROUND(b.fossil_share_energy - a.fossil_share_energy, 2) AS fossil_change_pp,
       ROUND(a.renewables_share_energy, 2) AS renewables_2000, ROUND(b.renewables_share_energy, 2) AS renewables_latest,
       ROUND(100.0 * (b.fossil_fuel_consumption - a.fossil_fuel_consumption) / a.fossil_fuel_consumption, 1) AS fossil_twh_change_pct
FROM a JOIN b ON a.entity_key = b.entity_key
WHERE b.primary_energy_consumption >= 100 AND a.fossil_share_energy IS NOT NULL AND b.fossil_share_energy IS NOT NULL;

-- Q7 energy use per person vs GDP per person (latest GDP year, countries with >= 1 million people)
CREATE OR REPLACE TABLE a_energy_gdp AS
SELECT entity, iso_code, continent, year, population, gdp_per_capita, ROUND(energy_per_capita, 0) AS energy_per_capita_kwh,
       ROUND(co2_per_capita_t, 2) AS co2_per_capita_t, low_carbon_share_elec, dq_epc_outlier
FROM v_c
WHERE year = y_gdp AND population >= 1000000 AND gdp_per_capita > 0 AND energy_per_capita > 0;

CREATE OR REPLACE TABLE a_energy_gdp_fit AS
SELECT COUNT(*) AS countries, max(year) AS year,
       ROUND(corr(ln(energy_per_capita_kwh), ln(gdp_per_capita)), 3) AS corr_log,
       ROUND(regr_slope(ln(energy_per_capita_kwh), ln(gdp_per_capita)), 3) AS elasticity,
       ROUND(regr_intercept(ln(energy_per_capita_kwh), ln(gdp_per_capita)), 3) AS intercept,
       ROUND(percentile_approx(energy_per_capita_kwh, 0.5), 0) AS median_energy_per_capita_kwh,
       ROUND(percentile_approx(gdp_per_capita, 0.5), 0) AS median_gdp_per_capita
FROM a_energy_gdp WHERE dq_epc_outlier = 0;

-- Q8 carbon intensity of electricity, latest year, countries generating >= 50 TWh (implausible values flagged and excluded)
CREATE OR REPLACE TABLE a_carbon_intensity AS
SELECT ROW_NUMBER() OVER (ORDER BY carbon_intensity_elec) AS rnk, entity, continent, year, ROUND(electricity_generation, 1) AS electricity_twh,
       carbon_intensity_elec, low_carbon_share_elec, coal_share_elec, gas_share_elec, nuclear_share_elec, hydro_share_elec, solar_wind_share_elec
FROM v_c
WHERE year = y_carbon_intensity AND electricity_generation >= 50 AND carbon_intensity_elec IS NOT NULL AND dq_ci_implausible = 0;

CREATE OR REPLACE TABLE a_ci_trend AS
SELECT entity, year, carbon_intensity_elec, low_carbon_share_elec, coal_share_elec, is_partial_year
FROM cln_energy
WHERE entity IN ('World', 'China', 'United States', 'India', 'European Union (27)', 'Germany', 'United Kingdom', 'Japan', 'Brazil', 'France')
  AND year >= 2000 AND carbon_intensity_elec IS NOT NULL;

-- Q9 coal phase-out: countries where coal made >= 20% of electricity in 2000 (and >= 5 TWh generated in the latest year)
CREATE OR REPLACE TABLE a_coal_phaseout AS
WITH a AS (SELECT * FROM v_c WHERE year = 2000), b AS (SELECT * FROM v_c WHERE year = y_electricity),
pk AS (SELECT entity_key, max(coal_share_elec) AS peak_share, max_by(year, coal_share_elec) AS peak_year,
              max(coal_electricity) AS peak_coal_twh, max_by(year, coal_electricity) AS peak_coal_year
       FROM v_c WHERE year BETWEEN 2000 AND y_electricity GROUP BY entity_key)
SELECT ROW_NUMBER() OVER (ORDER BY COALESCE(b.coal_share_elec, 0) - a.coal_share_elec) AS rnk,
       b.entity, b.continent, ROUND(b.electricity_generation, 1) AS electricity_twh_latest,
       ROUND(a.coal_share_elec, 2) AS coal_share_2000, ROUND(pk.peak_share, 2) AS coal_share_peak, pk.peak_year,
       ROUND(COALESCE(b.coal_share_elec, 0), 2) AS coal_share_latest,
       ROUND(COALESCE(b.coal_share_elec, 0) - a.coal_share_elec, 2) AS change_pp,
       ROUND(a.coal_electricity, 1) AS coal_twh_2000, ROUND(pk.peak_coal_twh, 1) AS coal_twh_peak, pk.peak_coal_year,
       ROUND(COALESCE(b.coal_electricity, 0), 1) AS coal_twh_latest,
       CASE WHEN COALESCE(b.coal_share_elec, 0) < 5 THEN 'phased down (< 5%)'
            WHEN b.coal_share_elec <= a.coal_share_elec - 10 THEN 'falling (>= 10 pp)'
            WHEN b.coal_share_elec < a.coal_share_elec THEN 'slightly lower'
            ELSE 'flat or rising' END AS status
FROM a JOIN b ON a.entity_key = b.entity_key JOIN pk ON pk.entity_key = b.entity_key
WHERE a.coal_share_elec >= 20 AND b.electricity_generation >= 5;

CREATE OR REPLACE TABLE a_coal_consumption AS
SELECT entity, year, ROUND(coal_consumption, 0) AS coal_twh, coal_share_energy, coal_share_elec, ROUND(coal_co2_mt, 0) AS coal_co2_mt
FROM cln_energy
WHERE entity IN ('World', 'China', 'India', 'United States', 'European Union (27)') AND year BETWEEN 1965 AND (SELECT y_energy_mix FROM cln_latest_year)
  AND coal_consumption IS NOT NULL;

-- Q10 solar + wind leaders (latest year, >= 10 TWh generated) and trend for the largest systems
CREATE OR REPLACE TABLE a_solar_wind_leaders AS
SELECT ROW_NUMBER() OVER (ORDER BY solar_wind_share_elec DESC) AS rnk, entity, continent, year, ROUND(electricity_generation, 1) AS electricity_twh,
       solar_share_elec, wind_share_elec, solar_wind_share_elec, ROUND(COALESCE(solar_electricity, 0) + COALESCE(wind_electricity, 0), 1) AS solar_wind_twh
FROM v_c WHERE year = y_electricity AND electricity_generation >= 10;

CREATE OR REPLACE TABLE a_solar_wind_trend AS
SELECT entity, year, solar_share_elec, wind_share_elec, solar_wind_share_elec, ROUND(COALESCE(solar_electricity, 0) + COALESCE(wind_electricity, 0), 1) AS solar_wind_twh,
       is_partial_year
FROM cln_energy
WHERE entity IN ('World', 'China', 'United States', 'European Union (27)', 'India', 'Germany', 'United Kingdom', 'Brazil') AND year >= 2000
  AND electricity_generation IS NOT NULL;

-- Q11 largest energy users (latest energy-mix year), share of world, per person, mix
CREATE OR REPLACE TABLE a_top_consumers AS
SELECT ROW_NUMBER() OVER (ORDER BY c.primary_energy_consumption DESC) AS rnk, c.entity, c.continent, c.year,
       ROUND(c.primary_energy_consumption, 0) AS primary_energy_twh,
       ROUND(100.0 * c.primary_energy_consumption / w.primary_energy_consumption, 2) AS pct_world,
       ROUND(c.energy_per_capita, 0) AS energy_per_capita_kwh, ROUND(c.energy_per_capita / w.energy_per_capita, 2) AS x_world_per_capita,
       c.fossil_share_energy, c.low_carbon_share_energy, c.renewables_share_energy
FROM v_c c JOIN v_w w ON c.year = w.year
WHERE c.year = c.y_energy_mix AND c.primary_energy_consumption IS NOT NULL;

-- Q12 decoupling: GDP vs territorial CO2, 2005 -> latest GDP year (countries >= 1 million people)
CREATE OR REPLACE TABLE a_decoupling AS
WITH a AS (SELECT * FROM v_c WHERE year = 2005), b AS (SELECT * FROM v_c WHERE year = y_gdp)
SELECT b.entity, b.continent, b.year AS latest_year,
       ROUND(100.0 * (b.gdp - a.gdp) / a.gdp, 1) AS gdp_change_pct,
       ROUND(100.0 * (b.co2_mt - a.co2_mt) / a.co2_mt, 1) AS co2_change_pct,
       ROUND(a.co2_mt, 1) AS co2_mt_2005, ROUND(b.co2_mt, 1) AS co2_mt_latest,
       ROUND(b.low_carbon_share_elec - a.low_carbon_share_elec, 2) AS low_carbon_elec_change_pp,
       CASE WHEN b.gdp > a.gdp AND b.co2_mt < a.co2_mt THEN 'absolute decoupling'
            WHEN b.gdp > a.gdp AND (b.co2_mt - a.co2_mt) / a.co2_mt < (b.gdp - a.gdp) / a.gdp THEN 'relative decoupling'
            WHEN b.gdp > a.gdp THEN 'CO2 grew faster than GDP'
            ELSE 'GDP fell' END AS status
FROM a JOIN b ON a.entity_key = b.entity_key
WHERE b.population >= 1000000 AND a.gdp > 0 AND b.gdp > 0 AND a.co2_mt > 0 AND b.co2_mt > 0;

-- Q13 renewables share of electricity, 15 largest generators x milestone years
CREATE OR REPLACE TABLE a_renewables_heatmap AS
WITH top AS (SELECT entity_key, entity, electricity_generation FROM v_c WHERE year = y_electricity ORDER BY electricity_generation DESC LIMIT 15)
SELECT t.entity, ROUND(t.electricity_generation, 0) AS electricity_twh_latest, c.year, c.renewables_share_elec, c.low_carbon_share_elec
FROM top t JOIN v_c c ON c.entity_key = t.entity_key
WHERE c.year IN (2000, 2005, 2010, 2015, 2020, c.y_electricity);

-- Q14 what the raw file contains: entity types
CREATE OR REPLACE TABLE a_entity_types AS
SELECT n.entity_type, n.entity_group, COUNT(DISTINCT n.entity) AS entities, COUNT(*) AS entity_years,
       SUM(e.has_energy_data) AS entity_years_with_energy, min(e.year) AS first_year, max(e.year) AS last_year
FROM cln_entity n JOIN cln_energy e ON n.entity = e.entity
GROUP BY n.entity_type, n.entity_group;

-- Q1 headline KPIs (written last because it summarises the tables above)
CREATE OR REPLACE TABLE a_kpi_headline AS
WITH l AS (SELECT * FROM cln_latest_year),
w0 AS (SELECT * FROM v_w WHERE year = 2000),
wm AS (SELECT * FROM v_w WHERE year = (SELECT y_energy_mix FROM l)),
we AS (SELECT * FROM v_w WHERE year = (SELECT y_electricity FROM l)),
wp AS (SELECT * FROM v_w WHERE year = (SELECT y_max FROM l)),
ce AS (SELECT * FROM v_c WHERE year = y_electricity AND low_carbon_share_elec IS NOT NULL)
SELECT
  (SELECT COUNT(*) FROM stg_energy)                                          AS raw_rows,
  (SELECT COUNT(*) FROM stg_co2)                                             AS raw_rows_co2,
  (SELECT COUNT(*) FROM cln_energy)                                          AS clean_entity_years,
  (SELECT COUNT(*) FROM fact_energy_year)                                    AS fact_entity_years,
  (SELECT COUNT(*) FROM cln_energy WHERE entity_type = 'country' AND has_energy_data = 1) AS country_years_with_energy,
  (SELECT COUNT(*) FROM cln_entity)                                          AS entities,
  (SELECT COUNT(*) FROM cln_entity WHERE entity_type = 'country')            AS countries,
  (SELECT COUNT(*) FROM cln_entity WHERE entity_type = 'historical_country') AS historical_countries,
  (SELECT COUNT(*) FROM cln_entity WHERE entity_type = 'aggregate')          AS aggregates,
  (SELECT min(year) FROM cln_energy)                                         AS first_year,
  (SELECT max(year) FROM cln_energy)                                         AS last_year,
  (SELECT y_energy_mix FROM l)                                               AS latest_energy_mix_year,
  (SELECT y_electricity FROM l)                                              AS latest_electricity_year,
  (SELECT y_gdp FROM l)                                                      AS latest_gdp_year,
  (SELECT ROUND(primary_energy_consumption, 0) FROM w0)                      AS world_primary_energy_twh_2000,
  (SELECT ROUND(primary_energy_consumption, 0) FROM wm)                      AS world_primary_energy_twh_latest,
  (SELECT ROUND(fossil_share_energy, 2) FROM w0)                             AS world_fossil_share_energy_2000,
  (SELECT ROUND(fossil_share_energy, 2) FROM wm)                             AS world_fossil_share_energy_latest,
  (SELECT ROUND(low_carbon_share_energy, 2) FROM w0)                         AS world_low_carbon_share_energy_2000,
  (SELECT ROUND(low_carbon_share_energy, 2) FROM wm)                         AS world_low_carbon_share_energy_latest,
  (SELECT ROUND(renewables_share_energy, 2) FROM w0)                         AS world_renewables_share_energy_2000,
  (SELECT ROUND(renewables_share_energy, 2) FROM wm)                         AS world_renewables_share_energy_latest,
  (SELECT ROUND(fossil_fuel_consumption - (SELECT fossil_fuel_consumption FROM w0), 0) FROM wm) AS world_fossil_twh_added_since_2000,
  (SELECT ROUND(low_carbon_consumption - (SELECT low_carbon_consumption FROM w0), 0) FROM wm)   AS world_low_carbon_twh_added_since_2000,
  (SELECT ROUND(renewables_share_elec, 2) FROM w0)                           AS world_renewables_share_elec_2000,
  (SELECT ROUND(renewables_share_elec, 2) FROM we)                           AS world_renewables_share_elec_latest,
  (SELECT ROUND(renewables_share_elec, 2) FROM wp)                           AS world_renewables_share_elec_provisional,
  (SELECT ROUND(low_carbon_share_elec, 2) FROM w0)                           AS world_low_carbon_share_elec_2000,
  (SELECT ROUND(low_carbon_share_elec, 2) FROM we)                           AS world_low_carbon_share_elec_latest,
  (SELECT ROUND(solar_wind_share_elec, 2) FROM w0)                           AS world_solar_wind_share_elec_2000,
  (SELECT ROUND(solar_wind_share_elec, 2) FROM we)                           AS world_solar_wind_share_elec_latest,
  (SELECT ROUND(coal_share_elec, 2) FROM w0)                                 AS world_coal_share_elec_2000,
  (SELECT ROUND(coal_share_elec, 2) FROM we)                                 AS world_coal_share_elec_latest,
  (SELECT ROUND(coal_consumption, 0) FROM w0)                                AS world_coal_twh_2000,
  (SELECT ROUND(coal_consumption, 0) FROM wm)                                AS world_coal_twh_latest,
  (SELECT ROUND(carbon_intensity_elec, 1) FROM w0)                           AS world_carbon_intensity_2000,
  (SELECT ROUND(carbon_intensity_elec, 1) FROM we)                           AS world_carbon_intensity_latest,
  (SELECT ROUND(co2_mt, 0) FROM w0)                                          AS world_co2_mt_2000,
  (SELECT ROUND(co2_mt, 0) FROM v_w WHERE year = (SELECT max(year) FROM v_w WHERE co2_mt IS NOT NULL)) AS world_co2_mt_latest,
  (SELECT COUNT(*) FROM ce)                                                  AS countries_with_elec_mix_latest,
  (SELECT SUM(CASE WHEN low_carbon_share_elec >= 50 THEN 1 ELSE 0 END) FROM ce) AS countries_low_carbon_elec_50pct,
  (SELECT SUM(CASE WHEN low_carbon_share_elec >= 90 THEN 1 ELSE 0 END) FROM ce) AS countries_low_carbon_elec_90pct,
  (SELECT SUM(CASE WHEN status = 'phased down (< 5%)' THEN 1 ELSE 0 END) FROM a_coal_phaseout) AS countries_coal_phased_down,
  (SELECT COUNT(*) FROM a_coal_phaseout)                                     AS countries_coal_20pct_in_2000,
  (SELECT corr_log FROM a_energy_gdp_fit)                                    AS corr_log_energy_vs_log_gdp_pc,
  (SELECT elasticity FROM a_energy_gdp_fit)                                  AS energy_gdp_elasticity,
  (SELECT SUM(CASE WHEN status = 'absolute decoupling' THEN 1 ELSE 0 END) FROM a_decoupling) AS countries_absolute_decoupling,
  (SELECT COUNT(*) FROM a_decoupling)                                        AS countries_in_decoupling_test,
  (SELECT entity FROM a_transitions WHERE rnk = 1)                           AS fastest_transition_country,
  (SELECT change_pp FROM a_transitions WHERE rnk = 1)                        AS fastest_transition_pp
FROM (SELECT 1) x;
