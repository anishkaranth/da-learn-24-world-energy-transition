# Data

| Folder | What | In git? |
|---|---|---|
| `raw/` | Deterministic sample of the raw files (`scripts/make_sample.py`): `owid-energy-data.csv` 6,937 of 23,377 rows (86 of 314 entities, all years), `owid-co2-data.csv` 8,625 of 50,411 rows (same entities, 1900+), both codebooks unchanged | yes (6.4 MB) |
| `raw_full/` | The full original files, downloaded with `python scripts/download_full_data.py` (pinned commits, SHA-256 checked) | no (`.gitignore`) |
| `reference/` | `owid_continents.csv`: OWID's country -> continent table (Our World in Data grapher "continents-according-to-our-world-in-data", CC BY 4.0, 271 entities); `entity_overrides.csv`: hand-made list of the 6 historical states, Kosovo (no ISO code -> OWID_KOS) and Antarctica | yes |
| `clean/star/` | Star schema from the full run: `dim_entity`, `dim_year`, `dim_source`, `fact_energy_year`, `fact_energy_mix` (all complete) | yes |
| `clean/year_coverage.csv` | Countries with each metric per year: shows why "latest year" differs by metric (EIA ends 2023, Energy Institute covers ~79 countries in 2024, 2025 is part-year) | yes |

**Raw layout.** `owid-energy-data.csv` has one row per *entity* x year and 130 columns (`country`, `year`, `iso_code`, `population`, `gdp`, then
consumption / share / per-capita / change columns per source for primary energy and electricity, `carbon_intensity_elec`, ...). The `country`
column mixes 221 real countries (3-letter `iso_code`) with 6 historical states and 87 aggregates (empty `iso_code`): World, the six continents,
EU-27, four World Bank income groups and source-specific regions such as `Africa (EI)`, `Europe (EIA)`, `Asia (Ember)`, `OPEC (Shift)`.
Missing values are empty strings. Units: TWh, kWh per person, % (shares, substitution method for primary energy), gCO2e/kWh, GDP in
2011 international-$ (Maddison, to 2022). `owid-co2-data.csv` has the same key layout (79 columns, 1750-2024, CO2 in million tonnes).
Column definitions and sources are in the two codebooks.

Rebuild the sample with `python scripts/make_sample.py` after downloading the full data.
