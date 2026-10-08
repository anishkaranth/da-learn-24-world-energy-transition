#!/usr/bin/env python3
"""Build the git-sized raw sample data/raw/ from data/raw_full/ (deterministic, no randomness).

Entities kept (all their years, lines copied byte-for-byte in the original order, same header and quoting):
  * every 4th real country in ISO-code order (3-letter ISO codes sorted, index % 4 = 0)
  * the large systems used by the fixed trend charts: China, United States, India, Germany, United Kingdom, Japan, Brazil, France, Russia
  * every historical country (USSR, Yugoslavia ...), Kosovo (no ISO code) and Antarctica, so the classification rules are exercised
  * aggregates: World, the six OWID continents, European Union (27), the four income groups, and the Africa row of each source
    (Africa (EI), Africa (EIA), Africa (Ember), Africa (Shift))
owid-co2-data.csv: the same entities, years >= 1900 only (the CO2 file starts in 1750). Both codebooks are copied unchanged."""
import csv, pathlib, shutil

ROOT = pathlib.Path(__file__).resolve().parents[1]
SRC, OUT = ROOT / "data/raw_full", ROOT / "data/raw"
OUT.mkdir(parents=True, exist_ok=True)
FIXED = {"China", "United States", "India", "Germany", "United Kingdom", "Japan", "Brazil", "France", "Russia",
         "USSR", "Yugoslavia", "Czechoslovakia", "East Germany", "West Germany", "Serbia and Montenegro", "Kosovo", "Antarctica",
         "World", "Africa", "Asia", "Europe", "North America", "South America", "Oceania", "European Union (27)",
         "High-income countries", "Upper-middle-income countries", "Lower-middle-income countries", "Low-income countries",
         "Africa (EI)", "Africa (EIA)", "Africa (Ember)", "Africa (Shift)"}


def rows(path):
    with open(path, newline="", encoding="utf-8") as fh:
        return fh.read().splitlines(keepends=True)


energy = rows(SRC / "owid-energy-data.csv")
recs = list(csv.reader(energy))
hdr = recs[0]; ci, ii = hdr.index("country"), hdr.index("iso_code")
isos = sorted({r[ii] for r in recs[1:] if len(r[ii]) == 3 and not r[ii].startswith("OWID")})
keep_iso = {c for k, c in enumerate(isos) if k % 4 == 0}
keep = FIXED | {r[ci] for r in recs[1:] if r[ii] in keep_iso}
for name, lines, year_min in [("owid-energy-data.csv", energy, None), ("owid-co2-data.csv", rows(SRC / "owid-co2-data.csv"), 1900)]:
    rr = list(csv.reader(lines))
    h = rr[0]; c, y = h.index("country"), h.index("year")
    n = 0
    with open(OUT / name, "w", encoding="utf-8", newline="") as fo:
        fo.write(lines[0])
        for ln, r in zip(lines[1:], rr[1:]):
            if r[c] in keep and (year_min is None or int(r[y]) >= year_min):
                fo.write(ln); n += 1
    print(f"{name}: {n:,} of {len(lines) - 1:,} rows, {(OUT / name).stat().st_size:,} B")
for name in ["owid-energy-codebook.csv", "owid-co2-codebook.csv"]:
    shutil.copyfile(SRC / name, OUT / name)
print(f"entities kept: {len(keep)} ({len(keep_iso)} sampled ISO countries + {len(FIXED)} fixed); codebooks copied")
