# Dashboard spec · da-learn-24 World energy transition

One report page, 16:9, plus a drill-through page. Report-level filter: `dim_year[is_partial_year] = 0`.

| # | Visual | Fields | Matches repo chart |
|---|---|---|---|
| 1 | KPI cards | [World Fossil Share of Energy %], [World Renewables Share of Power %], [Solar + Wind Share of Power %], [World Carbon Intensity g/kWh], [Countries >= 50% Low-carbon Power], [Countries] (year slicer = 2024) | dashboard.svg header |
| 2 | 100% stacked area: world energy mix | Axis dim_year[year] (>= 1965), legend dim_source[source_label], value [Source Share of Energy %]; filter dim_entity[entity] = "World" (swap the measure's country filter for the World row) | world_energy_mix.svg |
| 3 | 100% stacked area: world electricity mix | as 2 with [Source Share of Power %], year >= 2000 | world_elec_mix.svg |
| 4 | Line: low-carbon share of power by continent | Axis year (2000+), legend dim_entity[continent], value [Low-carbon Share of Power %] | region_elec_trend.svg |
| 5 | 100% stacked bar: fossil / nuclear / renewables by region | Axis dim_entity[continent], legend dim_source[category], value [Source Share of Energy %]; year = 2024 | region_mix.svg |
| 6 | Bar: fastest transitions | Axis dim_entity[entity], value [Low-carbon Change since 2000 pp]; Top N 15; filter [Electricity TWh] >= 10; year = 2024 | fastest_transitions.svg |
| 7 | Scatter: energy vs GDP | X AVERAGE(fact_energy_year[gdp_per_capita]) (log), Y [Energy per Person kWh] (log), details entity, legend continent; year = 2022, population >= 1M | energy_vs_gdp.svg |
| 8 | Bar: grid carbon intensity | Axis entity, value [Carbon Intensity g/kWh]; filter [Electricity TWh] >= 50; year = 2024; sort ascending | carbon_intensity.svg |
| 9 | Table: coal phase-out | entity, [Coal Share of Power 2000 %], [Coal Share of Power %], [Coal Change since 2000 pp]; filter 2000 share >= 20% | coal_phaseout.svg |
| 10 | Line: solar + wind share | Axis year, legend entity (World, China, USA, EU-27, India, Germany, UK, Brazil), value [Solar + Wind Share of Power %] | solar_wind_trend.svg |

Slicers: dim_year[year], dim_entity[continent], dim_entity[entity] (countries), dim_source[category].
Drill-through page "Country": electricity mix over time, energy per person vs world, coal share, carbon intensity and CO2 for the selected country.
