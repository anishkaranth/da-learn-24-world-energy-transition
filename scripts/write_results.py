#!/usr/bin/env python3
"""Write results/RESULTS.md from results/metrics.json + results/tables/*.csv (every number comes from the full-data run)."""
import csv, json, pathlib

ROOT = pathlib.Path(__file__).resolve().parents[1]
RES = ROOT / "results"
T = RES / "tables"


def rd(name):
    with open(T / f"{name}.csv", newline="", encoding="utf-8") as fh:
        return list(csv.DictReader(fh))


def f(x):
    return float(x) if x not in ("", None) else 0.0


def i(x):
    return int(f(x))


def num(v):
    if v in ("", None):
        return ""
    try:
        x = float(v)
    except ValueError:
        return str(v).replace("|", "/")
    return f"{int(x):,}" if x.is_integer() and abs(x) >= 1000 else (str(int(x)) if x.is_integer() else f"{x:,.2f}".rstrip("0").rstrip("."))


YEARS = {"year", "peak_year", "first_year", "last_year", "latest_year", "peak_coal_year"}


def table(rows, cols, heads=None):
    out = ["| " + " | ".join(heads or cols) + " |", "|" + "---|" * len(cols)]
    for r in rows:
        out.append("| " + " | ".join(str(r[c]) if c in YEARS else num(r[c]) for c in cols) + " |")
    return "\n".join(out)


m = json.loads((RES / "metrics.json").read_text())
k = m["kpis"]
ym, ye, yg = i(k["latest_energy_mix_year"]), i(k["latest_electricity_year"]), i(k["latest_gdp_year"])
W = {i(r["year"]): r for r in rd("a_world_mix")}
R = {(r["region"], r["snapshot"]): r for r in rd("a_region_mix")}
tr = sorted(rd("a_transitions"), key=lambda r: i(r["rnk"])); TR = {r["entity"]: r for r in tr}
et = sorted(rd("a_energy_transitions"), key=lambda r: i(r["rnk"]))
ci = sorted(rd("a_carbon_intensity"), key=lambda r: i(r["rnk"]))
ct = {(r["entity"], i(r["year"])): f(r["carbon_intensity_elec"]) for r in rd("a_ci_trend")}
cp = sorted(rd("a_coal_phaseout"), key=lambda r: i(r["rnk"])); CP = {r["entity"]: r for r in cp}
cc = {(r["entity"], i(r["year"])): f(r["coal_twh"]) for r in rd("a_coal_consumption")}
sw = sorted(rd("a_solar_wind_leaders"), key=lambda r: i(r["rnk"]))
st = {(r["entity"], i(r["year"])): f(r["solar_wind_share_elec"]) for r in rd("a_solar_wind_trend")}
tc = sorted(rd("a_top_consumers"), key=lambda r: i(r["rnk"]))
eg = {r["entity"]: r for r in rd("a_energy_gdp")}; fit = rd("a_energy_gdp_fit")[0]
dc = rd("a_decoupling"); DC = {r["entity"]: r for r in dc}
ent = rd("a_entity_types")
dq_i = rd("dq_issues"); dq_n = rd("dq_null_rates"); dq_r = rd("dq_row_counts"); asr = rd("dq_assertions")
npass = sum(1 for r in asr if r["status"] == "PASS")
phased = [r for r in cp if r["status"].startswith("phased")]; rising = [r for r in cp if r["status"].startswith("flat")]


def added(a, b, col):
    return f(W[b]["primary_energy_twh"]) * f(W[b][col]) / 100 - f(W[a]["primary_energy_twh"]) * f(W[a][col]) / 100


f1520, l1520 = added(2015, 2020, "fossil_share_energy"), added(2015, 2020, "low_carbon_share_energy")
f20, l20 = added(2020, ym, "fossil_share_energy"), added(2020, ym, "low_carbon_share_energy")
dcount = {s: sum(1 for r in dc if r["status"] == s) for s in ["absolute decoupling", "relative decoupling", "CO2 grew faster than GDP", "GDP fell"]}

ins = [
    f"**The share of fossil fuels is falling, the amount is not.** Fossil fuels supplied {f(k['world_fossil_share_energy_2000']):.2f}% of world "
    f"primary energy in 2000 and {f(k['world_fossil_share_energy_latest']):.2f}% in {ym}; renewables doubled from "
    f"{f(k['world_renewables_share_energy_2000']):.2f}% to {f(k['world_renewables_share_energy_latest']):.2f}%. But demand grew from "
    f"{f(k['world_primary_energy_twh_2000']):,.0f} to {f(k['world_primary_energy_twh_latest']):,.0f} TWh, so fossil use still rose by "
    f"{f(k['world_fossil_twh_added_since_2000']):,.0f} TWh against {f(k['world_low_carbon_twh_added_since_2000']):,.0f} TWh of new low-carbon "
    f"energy. Low-carbon additions only beat fossil additions in 2015-2020 ({l1520:,.0f} vs {f1520:,.0f} TWh, with the 2020 Covid dip); "
    f"in 2020-{ym} fossil added {f20:,.0f} TWh and low-carbon {l20:,.0f} TWh.",
    f"**Electricity is where the transition is fastest.** Renewables went from {f(k['world_renewables_share_elec_2000']):.2f}% of world "
    f"electricity in 2000 to {f(k['world_renewables_share_elec_latest']):.2f}% in {ye} ({f(k['world_renewables_share_elec_provisional']):.2f}% in the "
    f"part-year {ye + 1} release), and solar + wind from {f(k['world_solar_wind_share_elec_2000']):.2f}% to {f(k['world_solar_wind_share_elec_latest']):.2f}%. "
    f"In {ye}, {i(k['countries_low_carbon_elec_50pct'])} of {i(k['countries_with_elec_mix_latest'])} countries made at least half their power "
    f"from low-carbon sources and {i(k['countries_low_carbon_elec_90pct'])} made at least 90%. Coal still made {f(k['world_coal_share_elec_latest']):.2f}% "
    f"of world power (2000: {f(k['world_coal_share_elec_2000']):.2f}%).",
    f"**Regions start from very different places.** In {ym} fossil fuels were {f(R[('South America', 'latest')]['fossil_share_energy']):.1f}% of "
    f"South America's primary energy (hydro-rich) and {f(R[('Europe', 'latest')]['fossil_share_energy']):.1f}% of Europe's "
    f"(2000: {f(R[('Europe', '2000')]['fossil_share_energy']):.1f}%), but {f(R[('Asia', 'latest')]['fossil_share_energy']):.1f}% in Asia and "
    f"{f(R[('Africa', 'latest')]['fossil_share_energy']):.1f}% in Africa. Asia now uses {f(R[('Asia', 'latest')]['pct_world_energy']):.1f}% of the "
    f"world's energy (2000: {f(R[('Asia', '2000')]['pct_world_energy']):.1f}%) and coal's share of its energy rose from "
    f"{f(R[('Asia', '2000')]['coal_share_energy']):.1f}% to {f(R[('Asia', 'latest')]['coal_share_energy']):.1f}%. Europe's low-carbon share of "
    f"electricity climbed from {f(R[('Europe', '2000')]['low_carbon_share_elec']):.1f}% to {f(R[('Europe', 'latest')]['low_carbon_share_elec']):.1f}%.",
    f"**The fastest power transitions since 2000.** Among countries generating at least 10 TWh, {tr[0]['entity']} raised its low-carbon share of "
    f"electricity from {f(tr[0]['low_carbon_2000']):.1f}% to {f(tr[0]['low_carbon_latest']):.1f}% (+{f(tr[0]['change_pp']):.1f} pp, solar + wind "
    f"+{f(tr[0]['solar_wind_change_pp']):.1f} pp), followed by {tr[1]['entity']} (+{f(tr[1]['change_pp']):.1f} pp), {tr[2]['entity']} "
    f"(+{f(tr[2]['change_pp']):.1f} pp, main driver {tr[2]['main_driver']}) and {tr[3]['entity']} (+{f(tr[3]['change_pp']):.1f} pp). The United Arab Emirates went "
    f"from {f(TR['United Arab Emirates']['low_carbon_2000']):.0f}% to {f(TR['United Arab Emirates']['low_carbon_latest']):.1f}% "
    f"(nuclear +{f(TR['United Arab Emirates']['nuclear_change_pp']):.1f} pp). In primary energy, {et[0]['entity']} cut its fossil "
    f"share the most ({f(et[0]['fossil_2000']):.1f}% -> {f(et[0]['fossil_latest']):.1f}%).",
    f"**Coal: phased out in the West, booming in Asia.** World coal use rose from {cc[('World', 2000)]:,.0f} TWh in 2000 to "
    f"{cc[('World', ym)]:,.0f} TWh in {ym} (+{100 * (cc[('World', ym)] / cc[('World', 2000)] - 1):.0f}%), driven by China "
    f"({cc[('China', 2000)]:,.0f} -> {cc[('China', ym)]:,.0f}) and India ({cc[('India', 2000)]:,.0f} -> {cc[('India', ym)]:,.0f}), while the USA "
    f"({cc[('United States', 2000)]:,.0f} -> {cc[('United States', ym)]:,.0f}) and the EU-27 ({cc[('European Union (27)', 2000)]:,.0f} -> "
    f"{cc[('European Union (27)', ym)]:,.0f}) fell by about two-thirds. Of the {len(cp)} countries where coal made at least 20% of power in 2000, "
    f"{len(phased)} are now below 5% ({', '.join(r['entity'] + ' ' + format(f(r['coal_share_2000']), '.1f') + '% -> ' + format(f(r['coal_share_latest']), '.2f') + '%' for r in phased)}) "
    f"and {len(rising)} are flat or rising, including India ({f(CP['India']['coal_share_2000']):.1f}% -> {f(CP['India']['coal_share_latest']):.1f}%) "
    f"and Indonesia ({f(CP['Indonesia']['coal_share_2000']):.1f}% -> {f(CP['Indonesia']['coal_share_latest']):.1f}%).",
    f"**Grid carbon intensity.** The world's electricity got cleaner from {ct[('World', 2000)]:.0f} to {ct[('World', ye)]:.0f} gCO2e/kWh "
    f"(2000-{ye}); the UK fell from {ct[('United Kingdom', 2000)]:.0f} to {ct[('United Kingdom', ye)]:.0f}, the EU-27 from "
    f"{ct[('European Union (27)', 2000)]:.0f} to {ct[('European Union (27)', ye)]:.0f}, the USA from {ct[('United States', 2000)]:.0f} to "
    f"{ct[('United States', ye)]:.0f} and China from {ct[('China', 2000)]:.0f} to {ct[('China', ye)]:.0f}, while India barely moved "
    f"({ct[('India', 2000)]:.0f} -> {ct[('India', ye)]:.0f}). Among {len(ci)} grids generating at least 50 TWh the cleanest are "
    f"{', '.join(r['entity'] + ' (' + format(f(r['carbon_intensity_elec']), '.0f') + ')' for r in ci[:4])} and the most carbon-intensive "
    f"{', '.join(r['entity'] + ' (' + format(f(r['carbon_intensity_elec']), '.0f') + ')' for r in ci[::-1][:3])}.",
    f"**Energy follows income, but emissions can decouple.** Across {i(fit['countries'])} countries with at least 1 million people in {yg}, log "
    f"energy per person and log GDP per person correlate at {f(fit['corr_log']):.3f}; 1% more GDP per person goes with about "
    f"{f(fit['elasticity']):.2f}% more energy. An American used {f(eg['United States']['energy_per_capita_kwh']):,.0f} kWh, an Indian "
    f"{f(eg['India']['energy_per_capita_kwh']):,.0f} and an Ethiopian {f(eg['Ethiopia']['energy_per_capita_kwh']):,.0f}. Yet from 2005 to {yg}, "
    f"{dcount['absolute decoupling']} of {len(dc)} countries grew GDP while cutting territorial CO2: the UK (GDP +{f(DC['United Kingdom']['gdp_change_pct']):.1f}%, "
    f"CO2 {f(DC['United Kingdom']['co2_change_pct']):.1f}%), Germany (+{f(DC['Germany']['gdp_change_pct']):.1f}%, {f(DC['Germany']['co2_change_pct']):.1f}%) "
    f"and the USA (+{f(DC['United States']['gdp_change_pct']):.1f}%, {f(DC['United States']['co2_change_pct']):.1f}%); China's GDP grew "
    f"{f(DC['China']['gdp_change_pct']):.1f}% and its CO2 {f(DC['China']['co2_change_pct']):.1f}%.",
]

md = f"""# RESULTS · da-learn-24 · World energy transition (Our World in Data)

All numbers below come from the **full** dataset ({i(k['raw_rows']):,} raw energy rows plus {i(k['raw_rows_co2']):,} CO2 rows) run through
`sql/01`-`sql/05` on DuckDB ({m['engine']['duckdb']}); nothing is estimated or hand-typed. Databricks was skipped because the workspace hit its
resource quota, so there is no live Lakeview dashboard; the SQL stays Databricks-compatible. Charts: `results/images/` (SVG + PNG).

![Dashboard](images/dashboard.png)

## Headline KPIs
| KPI | Value |
|---|---|
| Raw rows (energy / CO2) | {i(k['raw_rows']):,} / {i(k['raw_rows_co2']):,} |
| Entities in the `country` column | {i(k['entities'])} = {i(k['countries'])} countries + {i(k['historical_countries'])} historical + {i(k['aggregates'])} aggregates |
| Clean entity-years / with energy data (fact) / country-years with energy | {i(k['clean_entity_years']):,} / {i(k['fact_entity_years']):,} / {i(k['country_years_with_energy']):,} |
| Years | {i(k['first_year'])}-{i(k['last_year'])} (latest complete: energy mix {ym}, electricity {ye}, GDP {yg}) |
| World primary energy 2000 / {ym} | {f(k['world_primary_energy_twh_2000']):,.0f} / {f(k['world_primary_energy_twh_latest']):,.0f} TWh |
| Fossil share of primary energy 2000 / {ym} | {f(k['world_fossil_share_energy_2000']):.2f}% / {f(k['world_fossil_share_energy_latest']):.2f}% |
| Renewables share of primary energy 2000 / {ym} | {f(k['world_renewables_share_energy_2000']):.2f}% / {f(k['world_renewables_share_energy_latest']):.2f}% |
| Fossil vs low-carbon energy added since 2000 | +{f(k['world_fossil_twh_added_since_2000']):,.0f} vs +{f(k['world_low_carbon_twh_added_since_2000']):,.0f} TWh |
| Renewables share of electricity 2000 / {ye} / {ye + 1} (part-year) | {f(k['world_renewables_share_elec_2000']):.2f}% / {f(k['world_renewables_share_elec_latest']):.2f}% / {f(k['world_renewables_share_elec_provisional']):.2f}% |
| Solar + wind share of electricity 2000 / {ye} | {f(k['world_solar_wind_share_elec_2000']):.2f}% / {f(k['world_solar_wind_share_elec_latest']):.2f}% |
| Coal share of electricity 2000 / {ye} | {f(k['world_coal_share_elec_2000']):.2f}% / {f(k['world_coal_share_elec_latest']):.2f}% |
| World coal use 2000 / {ym} | {f(k['world_coal_twh_2000']):,.0f} / {f(k['world_coal_twh_latest']):,.0f} TWh |
| Grid carbon intensity 2000 / {ye} | {f(k['world_carbon_intensity_2000']):.1f} / {f(k['world_carbon_intensity_latest']):.1f} gCO2e/kWh |
| Countries with >= 50% / >= 90% low-carbon power ({ye}) | {i(k['countries_low_carbon_elec_50pct'])} / {i(k['countries_low_carbon_elec_90pct'])} of {i(k['countries_with_elec_mix_latest'])} |
| log energy vs log GDP per person (corr / elasticity, {yg}) | {f(k['corr_log_energy_vs_log_gdp_pc']):.3f} / {f(k['energy_gdp_elasticity']):.2f} |
| Countries with absolute decoupling (2005-{yg}) | {i(k['countries_absolute_decoupling'])} of {i(k['countries_in_decoupling_test'])} |
| Assertions | {npass}/{len(asr)} PASS |

## Insights
""" + "\n".join(f"{n}. {t}" for n, t in enumerate(ins, 1)) + f"""

## World mix
![World primary energy mix](images/world_energy_mix.png)
![World electricity mix](images/world_elec_mix.png)
![Energy added](images/energy_added.png)

{table([W[y] for y in (1965, 1980, 2000, 2010, 2015, 2020, ym)], ['year', 'primary_energy_twh', 'fossil_share_energy', 'low_carbon_share_energy',
       'renewables_share_energy', 'coal_share_energy', 'renewables_share_elec', 'solar_wind_share_elec', 'carbon_intensity_elec'],
       ['Year', 'Primary energy TWh', 'Fossil %', 'Low-carbon %', 'Renewables %', 'Coal % energy', 'Renewables % power', 'Solar+wind % power', 'gCO2e/kWh'])}

## Fossil vs low-carbon by region
![Region mix](images/region_mix.png)
![Region electricity trend](images/region_elec_trend.png)

{table(sorted(rd('a_region_mix'), key=lambda r: (r['region'], r['year'])), ['region', 'year', 'primary_energy_twh', 'pct_world_energy',
       'energy_per_capita_kwh', 'fossil_share_energy', 'nuclear_share_energy', 'renewables_share_energy', 'coal_share_energy', 'low_carbon_share_elec'],
       ['Region', 'Year', 'TWh', '% world', 'kWh/person', 'Fossil %', 'Nuclear %', 'Renewables %', 'Coal %', 'Low-carbon % power'])}

## Fastest transitions since 2000
![Fastest transitions](images/fastest_transitions.png)
![Fossil share change](images/fossil_share_change.png)

{table(tr[:15], ['rnk', 'entity', 'electricity_twh_latest', 'low_carbon_2000', 'low_carbon_latest', 'change_pp', 'solar_wind_change_pp', 'coal_change_pp',
       'nuclear_change_pp', 'other_renewables_change_pp', 'main_driver'], ['#', 'Country', f'TWh {ye}', 'Low-carbon % 2000', f'Low-carbon % {ye}', 'Change pp',
       'Solar+wind pp', 'Coal pp', 'Nuclear pp', 'Geo/bio/other pp', 'Main driver'])}

## Solar and wind
![Solar + wind leaders](images/solar_wind_leaders.png)
![Solar + wind trend](images/solar_wind_trend.png)
![Renewables heatmap](images/renewables_heatmap.png)

{table(sw[:10], ['rnk', 'entity', 'electricity_twh', 'wind_share_elec', 'solar_share_elec', 'solar_wind_share_elec', 'solar_wind_twh'],
       ['#', 'Country', 'TWh', 'Wind %', 'Solar %', 'Solar+wind %', 'Solar+wind TWh'])}

## Energy per person vs GDP, and the biggest users
![Energy vs GDP](images/energy_vs_gdp.png)
![Top consumers](images/top_consumers.png)

{table(tc[:15], ['rnk', 'entity', 'primary_energy_twh', 'pct_world', 'energy_per_capita_kwh', 'x_world_per_capita', 'fossil_share_energy', 'renewables_share_energy'],
       ['#', 'Country', 'TWh', '% world', 'kWh/person', 'x world avg', 'Fossil %', 'Renewables %'])}

## Carbon intensity of electricity
![Carbon intensity](images/carbon_intensity.png)
![Carbon intensity trend](images/carbon_intensity_trend.png)

{table(ci[:8] + ci[-8:], ['rnk', 'entity', 'electricity_twh', 'carbon_intensity_elec', 'low_carbon_share_elec', 'coal_share_elec', 'gas_share_elec'],
       ['#', 'Country', 'TWh', 'gCO2e/kWh', 'Low-carbon %', 'Coal %', 'Gas %'])}

## Coal phase-out
![Coal phase-out](images/coal_phaseout.png)
![Coal consumption](images/coal_consumption.png)

{table(cp, ['rnk', 'entity', 'coal_share_2000', 'coal_share_peak', 'peak_year', 'coal_share_latest', 'change_pp', 'coal_twh_latest', 'status'],
       ['#', 'Country', 'Coal % 2000', 'Peak %', 'Peak year', f'Coal % {ye}', 'Change pp', f'Coal TWh {ye}', 'Status'])}

## Decoupling GDP from CO2 (2005-{yg})
![Decoupling](images/decoupling.png)

{table([{'status': s, 'countries': n} for s, n in dcount.items()], ['status', 'countries'], ['Status', 'Countries'])}

## Data quality
![Data quality](images/data_quality.png)

**What the `country` column contains** (the key cleaning step: only `country` rows enter country rankings)

{table(sorted(ent, key=lambda r: (r['entity_type'], r['entity_group'])), ['entity_type', 'entity_group', 'entities', 'entity_years', 'entity_years_with_energy', 'first_year', 'last_year'])}

**Row counts**

{table(dq_r, ['entity', 'raw_rows', 'distinct_rows', 'clean_rows', 'grain'])}

**Issues found and how they were handled**

{table(dq_i, ['check_name', 'affected_rows'])}

**Null rates (real countries)**

{table(dq_n, ['entity', 'column_name', 'null_pct', 'treatment'])}

**Assertions ({npass}/{len(asr)} PASS)**

{table(asr, ['check_name', 'failed_rows', 'status'])}

## How the images were made
`scripts/make_charts.py` reads the DuckDB query results exported to `results/tables/*.csv` and writes every chart as a plain-vector SVG with the
small custom writer `scripts/svgcharts.py` (rect, line, polyline, polygon, circle and text only; no plotting library, no embedded raster).
`scripts/render_png.py` then rasterises each SVG to a PNG at 2x with headless Google Chrome. Both versions are committed in `results/images/`.

## Files
`metrics.json` (KPIs, data-quality evidence, engine, SQL timings), `JSON.shot` (headline snapshot + run config), `tables/` (every `a_*` and
`dq_*` table as CSV), `images/` (SVG + PNG), `sample/` (the same pipeline on the committed raw sample).
"""
(RES / "RESULTS.md").write_text(md)
print("wrote", RES / "RESULTS.md")
