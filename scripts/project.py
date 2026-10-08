"""Project-specific settings used by run_pipeline.py (raw files, exports, JSON.shot content)."""
NAME = "da-learn-24-world-energy-transition"
DATASET = ("Our World in Data energy dataset (legacy release), the source of Kaggle 'World Energy Consumption' (pralabhpoudel), CC BY 4.0. "
           "GitHub mirror owid/energy-data @ f8de88a4: owid-energy-data.csv (23,377 rows x 130 columns, 9,229,369 B, 314 entities, 1900-2025) "
           "+ owid-energy-codebook.csv; joined with owid/co2-data @ 382ee6c6: owid-co2-data.csv (50,411 rows x 79 columns, 14,377,942 B, 1750-2024)")
RAW_FILES = ["owid-energy-data.csv", "owid-energy-codebook.csv", "owid-co2-data.csv", "owid-co2-codebook.csv"]
STAR = ["dim_entity", "dim_year", "dim_source", "fact_energy_year", "fact_energy_mix"]
METRIC_TABLES = ["a_kpi_headline", "a_world_mix", "a_region_mix", "a_region_elec_trend", "a_transitions", "a_energy_transitions", "a_energy_gdp",
                 "a_energy_gdp_fit", "a_carbon_intensity", "a_ci_trend", "a_coal_phaseout", "a_coal_consumption", "a_solar_wind_leaders",
                 "a_solar_wind_trend", "a_top_consumers", "a_decoupling", "a_renewables_heatmap", "a_entity_types"]


def export_full(con, export, root):
    """Full run: the whole star schema is small enough (fact_energy_year 13,840 rows, fact_energy_mix 75,193 rows) to export in full.
    Same files go to data/clean/star/ and powerbi/data/. The year-coverage table goes to data/clean/ as well."""
    for t in STAR:
        export(con, t, root / "data/clean/star" / f"{t}.csv")
        export(con, t, root / "powerbi/data" / f"{t}.csv")
    export(con, "cln_year_coverage", root / "data/clean/year_coverage.csv")


def build_shot(q, kpi):
    """Headline snapshot written to results/JSON.shot."""
    return {
        "config": {"sql_dialect": "Spark SQL style (+ DuckDB shims in sql/00), run on DuckDB; Databricks skipped (workspace quota)",
                   "grain": "fact_energy_year = one entity x year with any energy value; fact_energy_mix = entity x year x source (9 sources)",
                   "entity_rule": "3-letter ISO code = country; USSR, Yugoslavia, Czechoslovakia, East/West Germany, Serbia and Montenegro = historical; "
                                  "Kosovo (no ISO) = country OWID_KOS; empty iso_code / OWID_ prefix = aggregate (World, continents, income groups, "
                                  "EI / EIA / Ember / Shift regions). Country rankings use countries only; World/continent figures use OWID's aggregate rows",
                   "latest_year_rule": "per metric, the last year with >= 90% of peak country coverage: energy mix 2024 (Energy Institute, ~79 countries), "
                                       "electricity + carbon intensity 2024, GDP 2022, all-country primary energy 2023; 2025 is part-year (provisional)",
                   "thresholds": "transitions >= 10 TWh generated; carbon-intensity ranking >= 50 TWh; coal phase-out = coal >= 20% of power in 2000 "
                                 "and >= 5 TWh now; energy vs GDP and decoupling = countries >= 1 million people",
                   "outlier_rules": "energy per capita > 3x the year's country p95 flagged; grid carbon intensity > 900 g/kWh and above a fuel-mix "
                                    "ceiling (coal 1,100 / oil 900 / gas 700 / other 50) flagged and left out of the intensity ranking",
                   "sample_rule": "data/raw: every 4th ISO country + 9 large systems + historical states + 16 aggregates, all years "
                                  "(CO2 from 1900); scripts/make_sample.py"},
        "headline": kpi,
        "world_mix_milestones": q("SELECT year, fossil_share_energy, low_carbon_share_energy, renewables_share_energy, renewables_share_elec, "
                                  "solar_wind_share_elec, coal_share_elec, carbon_intensity_elec FROM a_world_mix "
                                  "WHERE year IN (1965, 1980, 2000, 2010, 2015, 2020, 2024) ORDER BY year"),
        "region_mix_latest": q("SELECT region, year, fossil_share_energy, nuclear_share_energy, renewables_share_energy, low_carbon_share_elec "
                               "FROM a_region_mix WHERE snapshot = 'latest' ORDER BY fossil_share_energy"),
        "fastest_transitions_top5": q("SELECT rnk, entity, low_carbon_2000, low_carbon_latest, change_pp FROM a_transitions WHERE rnk <= 5 ORDER BY rnk"),
        "lowest_carbon_grids_top5": q("SELECT rnk, entity, carbon_intensity_elec, low_carbon_share_elec FROM a_carbon_intensity WHERE rnk <= 5 ORDER BY rnk"),
        "coal_phaseout_top5": q("SELECT rnk, entity, coal_share_2000, coal_share_latest, change_pp, status FROM a_coal_phaseout WHERE rnk <= 5 ORDER BY rnk"),
        "energy_gdp_fit": q("SELECT * FROM a_energy_gdp_fit"),
        "decoupling_status": q("SELECT status, COUNT(*) AS countries FROM a_decoupling GROUP BY status ORDER BY countries DESC"),
    }
