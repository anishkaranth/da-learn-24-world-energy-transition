#!/usr/bin/env python3
"""Render SVG charts (pure vector shapes, no raster) from the KPI tables exported by run_pipeline.py."""
import csv, math, pathlib, sys
sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))
import svgcharts as S

BLUE, ORANGE, GREEN, SAND, NAVY, BROWN, PURPLE, ROSE, TEAL, GOLD = S.PALETTE[:10]
SRC = {"coal": "#4a3b33", "oil": "#8d6e63", "gas": "#e07a5f", "nuclear": "#6d597a", "hydro": "#1f6f8b", "wind": "#2a9d8f",
       "solar": "#e9b949", "other": "#81b29a"}
CONT = ["Africa", "Asia", "Europe", "North America", "Oceania", "South America"]


def rd(t, name):
    with open(pathlib.Path(t) / f"{name}.csv", newline="", encoding="utf-8") as fh:
        return list(csv.DictReader(fh))


def f(x):
    return float(x) if x not in ("", None) else 0.0


def fn(x):
    return float(x) if x not in ("", None) else None


def i(x):
    return int(f(x))


def short(s, n=22):
    s = s.replace("European Union (27)", "EU-27").replace("United States", "USA").replace("United Kingdom", "UK")
    return s if len(s) <= n else s[: n - 1] + "."


def make_all(tables, out):
    out = pathlib.Path(out); out.mkdir(parents=True, exist_ok=True)
    P = {}
    kpi = rd(tables, "a_kpi_headline")[0]
    ym, ye, yg = i(kpi["latest_energy_mix_year"]), i(kpi["latest_electricity_year"]), i(kpi["latest_gdp_year"])
    wm = sorted(rd(tables, "a_world_mix"), key=lambda r: i(r["year"]))
    W = {i(r["year"]): r for r in wm}

    # 1 world primary-energy mix, stacked shares
    em = [r for r in wm if r["fossil_share_energy"] != ""]
    ex = [r["year"] for r in em]
    oth = [max(0.0, 100 - sum(f(r[c]) for c in ["coal_share_energy", "oil_share_energy", "gas_share_energy", "nuclear_share_energy",
                                                  "hydro_share_energy", "wind_share_energy", "solar_share_energy"])) for r in em]
    P["world_energy_mix"] = S.stacked_area(
        f"World primary energy mix, 1965-{ym}", ex,
        [("Coal", [f(r["coal_share_energy"]) for r in em]), ("Oil", [f(r["oil_share_energy"]) for r in em]),
         ("Gas", [f(r["gas_share_energy"]) for r in em]), ("Nuclear", [f(r["nuclear_share_energy"]) for r in em]),
         ("Hydro", [f(r["hydro_share_energy"]) for r in em]), ("Wind", [f(r["wind_share_energy"]) for r in em]),
         ("Solar", [f(r["solar_share_energy"]) for r in em]), ("Other renewables + biofuels", oth)],
        colors=[SRC[k] for k in ["coal", "oil", "gas", "nuclear", "hydro", "wind", "solar", "other"]], w=900, h=380, every=5,
        subtitle=f"% of primary energy (substitution method); fossil fuels {f(W[1965]['fossil_share_energy']):.1f}% in 1965, "
                 f"{f(W[2000]['fossil_share_energy']):.1f}% in 2000, {f(W[ym]['fossil_share_energy']):.1f}% in {ym}")
    # 2 world electricity mix
    el = [r for r in wm if 2000 <= i(r["year"]) <= ye]
    P["world_elec_mix"] = S.stacked_area(
        f"World electricity mix, 2000-{ye}", [r["year"] for r in el],
        [("Coal", [f(r["coal_share_elec"]) for r in el]), ("Oil", [f(r["oil_share_elec"]) for r in el]), ("Gas", [f(r["gas_share_elec"]) for r in el]),
         ("Nuclear", [f(r["nuclear_share_elec"]) for r in el]), ("Hydro", [f(r["hydro_share_elec"]) for r in el]),
         ("Wind", [f(r["wind_share_elec"]) for r in el]), ("Solar", [f(r["solar_share_elec"]) for r in el]),
         ("Other renewables + bio", [f(r["other_renewables_share_elec"]) for r in el])],
        colors=[SRC[k] for k in ["coal", "oil", "gas", "nuclear", "hydro", "wind", "solar", "other"]], w=900, h=380, every=2,
        subtitle=f"% of generation; solar + wind {f(W[2000]['solar_wind_share_elec']):.1f}% -> {f(W[ye]['solar_wind_share_elec']):.1f}%, "
                 f"coal {f(W[2000]['coal_share_elec']):.1f}% -> {f(W[ye]['coal_share_elec']):.1f}% (part-year 2025 not shown)")
    # 3 energy added per period: fossil vs low-carbon TWh
    cuts = [2000, 2005, 2010, 2015, 2020, ym]
    labs, fos, low = [], [], []
    for a, b in zip(cuts, cuts[1:]):
        fa = f(W[a]["primary_energy_twh"]) * f(W[a]["fossil_share_energy"]) / 100; fb = f(W[b]["primary_energy_twh"]) * f(W[b]["fossil_share_energy"]) / 100
        la = f(W[a]["primary_energy_twh"]) * f(W[a]["low_carbon_share_energy"]) / 100; lb = f(W[b]["primary_energy_twh"]) * f(W[b]["low_carbon_share_energy"]) / 100
        labs.append(f"{a}-{str(b)[2:]}"); fos.append(round(fb - fa)); low.append(round(lb - la))
    P["energy_added"] = S.grouped_vbar("New energy demand: fossil vs low-carbon additions (TWh)", labs,
                                       [("fossil fuels", [max(v, 0) for v in fos]), ("low-carbon (nuclear + renewables)", low)], fmt="{:,.0f}",
                                       subtitle=f"change in world primary energy by period; since 2000 fossil +{f(kpi['world_fossil_twh_added_since_2000']):,.0f} TWh "
                                                f"vs low-carbon +{f(kpi['world_low_carbon_twh_added_since_2000']):,.0f} TWh"
                                                + ("; 2005-10 / 2015-20 incl. 2009 + 2020 dips" if any(v < 0 for v in fos) else ""),
                                       w=640, h=340, ylabel="TWh added")
    # 4 region mix (latest)
    rm = [r for r in rd(tables, "a_region_mix") if r["snapshot"] == "latest"]
    r0 = {r["region"]: r for r in rd(tables, "a_region_mix") if r["snapshot"] == "2000"}
    rm.sort(key=lambda r: f(r["fossil_share_energy"]))
    P["region_mix"] = S.stacked_hbar(f"Fossil vs low-carbon primary energy by region, {ym}", [r["region"] for r in rm],
                                     [[f(r["fossil_share_energy"]), f(r["nuclear_share_energy"]), f(r["renewables_share_energy"])] for r in rm],
                                     ["fossil", "nuclear", "renewables"], colors=["#4a3b33", PURPLE, GREEN], w=700,
                                     notes=[f"2000: {f(r0[r['region']]['fossil_share_energy']):.0f}% fossil" for r in rm],
                                     subtitle="% of each region's primary energy (OWID continent aggregates); right: fossil share in 2000")
    # 5 region electricity trend (bottom-up)
    rt = rd(tables, "a_region_elec_trend"); yrs = sorted({i(r["year"]) for r in rt})
    rv = {(r["region"], i(r["year"])): f(r["low_carbon_share_elec"]) for r in rt}
    P["region_elec_trend"] = S.line(f"Low-carbon share of electricity by continent, 2000-{ye}", [str(y) for y in yrs],
                                    [(c, [rv.get((c, y)) for y in yrs]) for c in CONT] + [("World", [f(W[y]["low_carbon_share_elec"]) for y in yrs])],
                                    fmt="{:.0f}%", every=4, end_labels=True, colors=[ORANGE, ROSE, BLUE, NAVY, GOLD, GREEN, "#111111"],
                                    subtitle="nuclear + renewables, % of generation; bottom-up sum of countries (reconciles to OWID continent rows)")
    # 6 fastest transitions
    tr = sorted(rd(tables, "a_transitions"), key=lambda r: i(r["rnk"]))[:15]
    P["fastest_transitions"] = S.dumbbell(f"Fastest power-sector transitions, 2000 -> {ye}", [r["entity"] for r in tr],
                                          [f(r["low_carbon_2000"]) for r in tr], [f(r["low_carbon_latest"]) for r in tr],
                                          names=("low-carbon share 2000", f"{ye}"), w=760,
                                          notes=[f"+{f(r['change_pp']):.0f} pp ({r['main_driver']})" for r in tr],
                                          subtitle="countries generating >= 10 TWh; change in nuclear + renewables share of electricity, main driver on the right")
    # 7 primary-energy fossil share change
    et = sorted(rd(tables, "a_energy_transitions"), key=lambda r: f(r["fossil_change_pp"]))
    sel = et[:12] + et[-6:]
    P["fossil_share_change"] = S.dbar(f"Change in fossil share of primary energy, 2000 -> {ym} (pp)", [r["entity"] for r in sel],
                                      [f(r["fossil_change_pp"]) for r in sel], fmt="{:+.1f}", pos_color=BROWN, neg_color=TEAL, w=700,
                                      subtitle=f"12 biggest falls and 6 biggest rises among {len(et)} countries using >= 100 TWh (Energy Institute coverage)")
    # 8 energy vs GDP
    eg = [r for r in rd(tables, "a_energy_gdp") if i(r["dq_epc_outlier"]) == 0]
    fit = rd(tables, "a_energy_gdp_fit")[0]
    pts = [(f(r["gdp_per_capita"]), f(r["energy_per_capita_kwh"]), CONT.index(r["continent"]) if r["continent"] in CONT else 0) for r in eg]
    lab = {"United States", "China", "India", "Qatar", "Iceland", "Norway", "Germany", "Brazil", "Nigeria", "Ethiopia", "Japan", "Russia",
           "Saudi Arabia", "Switzerland", "Bangladesh", "Canada", "Ireland", "Kenya"}
    P["energy_vs_gdp"] = S.scatter(f"Energy use per person vs GDP per person, {yg}", pts, logx=True, logy=True,
                                   fit=(f(fit["intercept"]), f(fit["elasticity"])), groups=CONT, w=760, h=470,
                                   labels={k: short(r["entity"], 14) for k, r in enumerate(eg) if r["entity"] in lab},
                                   xticks=[1000, 2000, 5000, 10000, 20000, 50000, 100000], yticks=[300, 1000, 3000, 10000, 30000, 100000, 300000],
                                   ytick_fmt="{:,.0f}", xlabel="GDP per person (2011 int-$, log scale)", ylabel="primary energy per person (kWh, log)",
                                   subtitle=f"{i(fit['countries'])} countries >= 1 million people; log-log fit: corr {f(fit['corr_log']):.2f}, "
                                            f"1% more GDP per person ~ {f(fit['elasticity']):.2f}% more energy")
    # 9 carbon intensity ranking
    ci = sorted(rd(tables, "a_carbon_intensity"), key=lambda r: i(r["rnk"]))
    sel = ci[:10] + ci[-10:]
    P["carbon_intensity"] = S.hbar(f"Carbon intensity of electricity, {ye}: cleanest and dirtiest grids", [r["entity"] for r in sel],
                                   [f(r["carbon_intensity_elec"]) for r in sel], fmt="{:.0f}", color=[TEAL] * 10 + [BROWN] * 10, w=720, vmax=900,
                                   notes=[f"g/kWh, {f(r['low_carbon_share_elec']):.0f}% low-carbon" for r in sel],
                                   subtitle=f"gCO2e per kWh generated, {len(ci)} countries generating >= 50 TWh; World {f(W[ye]['carbon_intensity_elec']):.0f} g/kWh")
    # 10 carbon intensity trend
    ct = rd(tables, "a_ci_trend"); ents = ["World", "China", "United States", "India", "European Union (27)", "United Kingdom", "Brazil"]
    cy = [y for y in range(2000, ye + 1)]
    cv = {(r["entity"], i(r["year"])): f(r["carbon_intensity_elec"]) for r in ct}
    P["carbon_intensity_trend"] = S.line(f"Carbon intensity of electricity, 2000-{ye} (gCO2e/kWh)", [str(y) for y in cy],
                                         [(short(e), [cv.get((e, y)) for y in cy]) for e in ents], fmt="{:.0f}", every=4, end_labels=True,
                                         colors=["#111111", ROSE, NAVY, ORANGE, BLUE, PURPLE, GREEN],
                                         subtitle=f"UK {cv[('United Kingdom', 2000)]:.0f} -> {cv[('United Kingdom', ye)]:.0f}; "
                                                  f"China {cv[('China', 2000)]:.0f} -> {cv[('China', ye)]:.0f}; India {cv[('India', 2000)]:.0f} -> {cv[('India', ye)]:.0f}")
    # 11 coal phase-out dumbbell
    cp = sorted(rd(tables, "a_coal_phaseout"), key=lambda r: i(r["rnk"]))[:16]
    P["coal_phaseout"] = S.dumbbell(f"Coal phase-out: coal share of electricity, 2000 -> {ye}", [r["entity"] for r in cp],
                                    [f(r["coal_share_2000"]) for r in cp], [f(r["coal_share_latest"]) for r in cp], names=("2000", str(ye)),
                                    ca=BROWN, cb=TEAL, w=760,
                                    notes=[f"{f(r['change_pp']):+.0f} pp, peak {f(r['coal_share_peak']):.0f}% ({r['peak_year']})" for r in cp],
                                    subtitle=f"16 biggest falls among {len(rd(tables, 'a_coal_phaseout'))} countries where coal was >= 20% of power in 2000 (>= 5 TWh now)")
    # 12 coal consumption
    cc = rd(tables, "a_coal_consumption"); cyrs = sorted({i(r["year"]) for r in cc})
    ccv = {(r["entity"], i(r["year"])): f(r["coal_twh"]) / 1000 for r in cc}
    ce = ["World", "China", "India", "United States", "European Union (27)"]
    P["coal_consumption"] = S.line(f"Coal consumption, 1965-{ym} (thousand TWh)", [str(y) for y in cyrs],
                                   [(short(e), [ccv.get((e, y)) for y in cyrs]) for e in ce], fmt="{:.0f}", every=5, end_labels=True,
                                   colors=["#111111", ROSE, ORANGE, NAVY, BLUE],
                                   subtitle=f"world coal use {f(kpi['world_coal_twh_2000']):,.0f} TWh in 2000 -> {f(kpi['world_coal_twh_latest']):,.0f} TWh in {ym}: "
                                            f"China's growth outweighs US/EU declines")
    # 13 solar + wind leaders
    sw = sorted(rd(tables, "a_solar_wind_leaders"), key=lambda r: i(r["rnk"]))[:15]
    P["solar_wind_leaders"] = S.stacked_hbar(f"Solar + wind share of electricity, top 15 countries, {ye}", [r["entity"] for r in sw],
                                             [[f(r["wind_share_elec"]), f(r["solar_share_elec"])] for r in sw], ["wind", "solar"],
                                             colors=[SRC["wind"], SRC["solar"]], total=80, w=700, min_label=5,
                                             notes=[f"{f(r['solar_wind_share_elec']):.1f}%" for r in sw],
                                             subtitle=f"countries generating >= 10 TWh; World {f(W[ye]['solar_wind_share_elec']):.1f}% (bar scale 0-80%)")
    # 14 solar + wind trend
    st = rd(tables, "a_solar_wind_trend"); se = ["World", "China", "United States", "European Union (27)", "India", "Germany", "United Kingdom", "Brazil"]
    sy = list(range(2000, ye + 1)); sv = {(r["entity"], i(r["year"])): f(r["solar_wind_share_elec"]) for r in st}
    P["solar_wind_trend"] = S.line(f"Solar + wind share of electricity, 2000-{ye}", [str(y) for y in sy],
                                   [(short(e), [sv.get((e, y)) for y in sy]) for e in se], fmt="{:.0f}%", every=4, end_labels=True,
                                   colors=["#111111", ROSE, NAVY, BLUE, ORANGE, GOLD, PURPLE, GREEN],
                                   subtitle=f"provisional part-year {ye + 1}: World {f(W[ye + 1]['solar_wind_share_elec']):.1f}%" if (ye + 1) in W else None)
    # 15 top consumers
    tc = sorted(rd(tables, "a_top_consumers"), key=lambda r: i(r["rnk"]))[:15]
    P["top_consumers"] = S.hbar(f"Largest energy users, {ym}: primary energy (TWh)", [r["entity"] for r in tc], [f(r["primary_energy_twh"]) for r in tc],
                                fmt="{:,.0f}", color=NAVY, w=860, vmax=90000,
                                notes=[f"{f(r['pct_world']):.1f}% of world · {f(r['energy_per_capita_kwh']) / 1000:.0f}k kWh/person · {f(r['fossil_share_energy']):.0f}% fossil" for r in tc],
                                subtitle=f"top 15 = {sum(f(r['pct_world']) for r in tc):.0f}% of world primary energy ({f(W[ym]['primary_energy_twh']):,.0f} TWh); "
                                         f"world average {f(W[ym]['energy_per_capita_kwh']):,.0f} kWh/person")
    # 16 decoupling
    dc = rd(tables, "a_decoupling"); stl = ["absolute decoupling", "relative decoupling", "CO2 grew faster than GDP", "GDP fell"]
    pts = [(1 + f(r["gdp_change_pct"]) / 100, 1 + f(r["co2_change_pct"]) / 100, [TEAL, SAND, BROWN, NAVY].index if False else stl.index(r["status"])) for r in dc]
    labd = {"China", "India", "United States", "United Kingdom", "Germany", "France", "Japan", "Brazil", "Denmark", "Vietnam", "Ukraine", "Bangladesh"}
    cnt = {s: sum(1 for r in dc if r["status"] == s) for s in stl}
    old = S.PALETTE[:]
    S.PALETTE[:4] = [TEAL, GOLD, BROWN, NAVY]
    P["decoupling"] = S.scatter(f"Decoupling: change in GDP vs change in CO2, 2005 -> {yg}", pts, logx=True, logy=True, w=760, h=470,
                                groups=[f"{s} ({cnt[s]})" for s in stl], refs=[("x", 1), ("y", 1)],
                                labels={k: short(r["entity"], 12) for k, r in enumerate(dc) if r["entity"] in labd},
                                xticks=[0.6, 0.8, 1, 1.5, 2, 3, 4, 5], xtick_fmt="{:.1f}x", yticks=[0.5, 0.7, 1, 1.5, 2, 3, 5, 10, 16], ytick_fmt="{:g}x",
                                xlabel="GDP in latest year / GDP in 2005 (log)", ylabel="territorial CO2 latest / 2005 (log)",
                                subtitle=f"{len(dc)} countries >= 1 million people; {cnt['absolute decoupling']} grew GDP while cutting CO2")
    S.PALETTE[:] = old
    # 17 renewables heatmap
    hm = rd(tables, "a_renewables_heatmap"); hy = sorted({i(r["year"]) for r in hm})
    order = sorted({(r["entity"], f(r["electricity_twh_latest"])) for r in hm}, key=lambda x: -x[1])
    hv = {(r["entity"], i(r["year"])): fn(r["renewables_share_elec"]) for r in hm}
    P["renewables_heatmap"] = S.heatmap("Renewables share of electricity, 15 largest power systems", [f"{e} ({t:,.0f} TWh)" for e, t in order],
                                        [str(y) for y in hy], [[hv.get((e, y)) for y in hy] for e, _ in order], fmt="{:.0f}%", w=640,
                                        lo_color="#f7f4ea", hi_color="#2a9d8f", vmin=0, vmax=90,
                                        subtitle=f"% of generation from hydro, wind, solar, bioenergy, geothermal; ordered by {ye} generation")
    # 18 data quality
    dq = sorted([r for r in rd(tables, "dq_issues") if i(r["affected_rows"]) > 0 and "% of World" not in r["check_name"]],
                key=lambda r: -i(r["affected_rows"]))
    def dq_label(c):
        for k, v in [("population/GDP only", "no energy value (pop/GDP only)"), ("aggregate rows", "aggregate rows (World, regions ...)"),
                     ("no CO2 row", "no CO2 row to join"), ("breakdown incomplete", "power-source breakdown incomplete"),
                     ("historical-country", "historical-country rows"), ("carbon intensity", "implausible grid carbon intensity"),
                     ("part-year", "part-year 2025 rows (provisional)"), ("empty iso_code", "aggregate entities, empty iso_code"),
                     ("Antarctica", "Antarctica rows (continent override)"), ("Kosovo", "Kosovo rows (no ISO -> OWID_KOS)"),
                     ("energy per capita", "energy/person outlier (> 3x p95)")]:
            if k in c:
                return v
        return short(c, 36)
    P["data_quality"] = S.hbar("Data-quality issues found and handled", [dq_label(r["check_name"]) for r in dq], [i(r["affected_rows"]) for r in dq],
                               fmt="{:,.0f}", color=ROSE, w=720, subtitle="rows (or entities) affected in the raw / clean data; see sql/05_quality_checks.sql")
    for k, p in P.items():
        S.save(p, out / f"{k}.svg")
    cards = [("countries (+ 6 historical, 87 aggregates)", f"{i(kpi['countries'])}"), (f"fossil share of energy {ym}", f"{f(kpi['world_fossil_share_energy_latest']):.1f}%"),
             (f"renewables share of power {ye}", f"{f(kpi['world_renewables_share_elec_latest']):.1f}%"),
             (f"solar + wind share of power {ye}", f"{f(kpi['world_solar_wind_share_elec_latest']):.1f}%"),
             (f"grid gCO2e/kWh {ye} (2000: {f(kpi['world_carbon_intensity_2000']):.0f})", f"{f(kpi['world_carbon_intensity_latest']):.0f}"),
             (f"countries >= 50% low-carbon power", f"{i(kpi['countries_low_carbon_elec_50pct'])}/{i(kpi['countries_with_elec_mix_latest'])}")]
    small = dict(w=640, h=360)
    S.dashboard(out / "dashboard.svg", "da-learn-24 · World energy transition (Our World in Data, 1900-2025)",
                f"{i(kpi['raw_rows']):,} raw entity-year rows -> {i(kpi['country_years_with_energy']):,} country-years with energy data; "
                f"OWID aggregates separated from {i(kpi['countries'])} countries; DuckDB SQL pipeline; Databricks skipped (quota)",
                cards, [
                    S.stacked_area(f"World primary energy mix, 1965-{ym}", ex,
                                   [("Coal", [f(r["coal_share_energy"]) for r in em]), ("Oil", [f(r["oil_share_energy"]) for r in em]),
                                    ("Gas", [f(r["gas_share_energy"]) for r in em]), ("Nuclear", [f(r["nuclear_share_energy"]) for r in em]),
                                    ("Hydro", [f(r["hydro_share_energy"]) for r in em]), ("Wind", [f(r["wind_share_energy"]) for r in em]),
                                    ("Solar", [f(r["solar_share_energy"]) for r in em]), ("Other ren.", oth)],
                                   colors=[SRC[k] for k in ["coal", "oil", "gas", "nuclear", "hydro", "wind", "solar", "other"]], every=10, **small),
                    P["energy_added"],
                    S.line(f"Low-carbon share of electricity by continent", [str(y) for y in yrs],
                           [(c, [rv.get((c, y)) for y in yrs]) for c in CONT] + [("World", [f(W[y]["low_carbon_share_elec"]) for y in yrs])],
                           fmt="{:.0f}%", every=6, end_labels=True, colors=[ORANGE, ROSE, BLUE, NAVY, GOLD, GREEN, "#111111"], **small),
                    S.dumbbell(f"Fastest power transitions, 2000 -> {ye}", [r["entity"] for r in tr[:10]], [f(r["low_carbon_2000"]) for r in tr[:10]],
                               [f(r["low_carbon_latest"]) for r in tr[:10]], names=("low-carbon 2000", str(ye)), w=640, h=360),
                    S.dumbbell(f"Coal share of power, 2000 -> {ye}", [r["entity"] for r in cp[:10]], [f(r["coal_share_2000"]) for r in cp[:10]],
                               [f(r["coal_share_latest"]) for r in cp[:10]], names=("2000", str(ye)), ca=BROWN, cb=TEAL, w=640, h=360),
                    S.line(f"Grid carbon intensity (gCO2e/kWh)", [str(y) for y in cy], [(short(e), [cv.get((e, y)) for y in cy]) for e in ents],
                           fmt="{:.0f}", every=6, end_labels=True, colors=["#111111", ROSE, NAVY, ORANGE, BLUE, PURPLE, GREEN], **small),
                ], cols=2)
    print(f"wrote {len(P) + 1} SVG charts to {out}")


if __name__ == "__main__":
    root = pathlib.Path(__file__).resolve().parents[1]
    make_all(root / "results/tables", root / "results/images")
