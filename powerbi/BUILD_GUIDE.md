# Build guide · Power BI Desktop (Windows)

There is no `.pbix` in this repo: Power BI Desktop only runs on Windows and this project was built on Linux. Everything needed to build the
report in about 20 minutes is here.

1. **Get the data.** Either use the committed CSVs in `powerbi/data/`, or regenerate them: `python scripts/download_full_data.py` then
   `python run_pipeline.py --source full`.
2. **Load.** Home > Get data > Text/CSV, load the five files from `powerbi/data/`. In Power Query check types: `entity_key`, `year`,
   `source_key`, `population`, `decade` and the 0/1 flags as Whole number; every TWh, kWh, share, GDP, CO2 and intensity column as Decimal;
   names, codes, types and groups as Text. Empty cells are nulls (not zero). Close & Apply.
3. **Model.** In Model view create the relationships in `model.md` (many-to-one, single direction): `fact_energy_year` and `fact_energy_mix`
   to `dim_entity` (entity_key) and `dim_year` (year); `fact_energy_mix` to `dim_source` (source_key).
4. **Measures.** Create a blank table called `_Measures` and paste each measure from `measures.dax`. Format shares as percentages.
5. **Visuals.** Build the page in `dashboard_spec.md`. Add the report-level filter `dim_year[is_partial_year] = 0`.
6. **Check against the repo** (year = 2024, no other slicers): [World Renewables Share of Power %] = 31.94%, [World Carbon Intensity g/kWh]
   = 471.08, [Electricity TWh] (countries) = 30,819.7 vs the World row's 30,930.2 TWh, [Countries >= 50% Low-carbon Power] = 77.
   For 2000 the World fossil share of energy is 86.05%. These match `results/metrics.json` and `results/RESULTS.md`.
