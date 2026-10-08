-- 03_model.sql  Star schema: fact_energy_year (entity x year), fact_energy_mix (entity x year x source) + dim_entity, dim_year, dim_source

CREATE OR REPLACE TABLE dim_entity AS
SELECT entity_key, entity, iso_code, entity_type, entity_group, continent, first_year, last_year,
       CASE WHEN entity_type = 'country' THEN 1 ELSE 0 END AS is_country
FROM cln_entity;

CREATE OR REPLACE TABLE dim_year AS
SELECT DISTINCT year,
       CAST(FLOOR(year / 10) * 10 AS INT) AS decade,
       CASE WHEN year < 1965 THEN 'pre-1965' WHEN year < 2000 THEN '1965-1999' WHEN year < 2015 THEN '2000-2014' ELSE '2015+ (Paris era)' END AS period,
       CASE WHEN year > (SELECT y_electricity FROM cln_latest_year) THEN 1 ELSE 0 END AS is_partial_year
FROM cln_energy;

CREATE OR REPLACE TABLE dim_source AS
SELECT * FROM VALUES
  (1, 'coal', 'Coal', 'fossil', 0, 0),
  (2, 'oil', 'Oil', 'fossil', 0, 0),
  (3, 'gas', 'Gas', 'fossil', 0, 0),
  (4, 'nuclear', 'Nuclear', 'nuclear', 1, 0),
  (5, 'hydro', 'Hydropower', 'renewable', 1, 1),
  (6, 'solar', 'Solar', 'renewable', 1, 1),
  (7, 'wind', 'Wind', 'renewable', 1, 1),
  (8, 'biofuel', 'Biofuels', 'renewable', 1, 1),
  (9, 'other_renewable', 'Other renewables (geothermal, biomass ...)', 'renewable', 1, 1)
  AS t(source_key, source, source_label, category, is_low_carbon, is_renewable);

-- one row per entity x year that carries any energy or electricity value (population/GDP-only years are left out)
CREATE OR REPLACE TABLE fact_energy_year AS
SELECT entity_key, year, population, gdp, gdp_per_capita,
       primary_energy_consumption AS primary_energy_twh, energy_per_capita AS energy_per_capita_kwh, energy_per_gdp AS energy_per_gdp_kwh,
       fossil_fuel_consumption AS fossil_twh, low_carbon_consumption AS low_carbon_twh, renewables_consumption AS renewables_twh,
       fossil_share_energy, low_carbon_share_energy, renewables_share_energy, coal_share_energy,
       electricity_generation AS electricity_twh, electricity_demand AS electricity_demand_twh, per_capita_electricity AS electricity_per_capita_kwh,
       fossil_electricity AS fossil_elec_twh, low_carbon_electricity AS low_carbon_elec_twh, renewables_electricity AS renewables_elec_twh,
       coal_electricity AS coal_elec_twh, solar_electricity AS solar_elec_twh, wind_electricity AS wind_elec_twh,
       fossil_share_elec, low_carbon_share_elec, renewables_share_elec, coal_share_elec, solar_wind_share_elec,
       carbon_intensity_elec AS carbon_intensity_g_per_kwh, greenhouse_gas_emissions AS power_ghg_mt,
       co2_mt, co2_per_capita_t, coal_co2_mt,
       is_partial_year, dq_epc_outlier, dq_ci_implausible, dq_elec_sources_incomplete
FROM cln_energy
WHERE has_energy_data = 1;

CREATE OR REPLACE TABLE fact_energy_mix AS
SELECT m.entity_key, m.year, s.source_key, m.energy_twh, m.share_energy_pct, m.elec_twh, m.share_elec_pct
FROM cln_mix_long m JOIN dim_source s ON m.source = s.source;
