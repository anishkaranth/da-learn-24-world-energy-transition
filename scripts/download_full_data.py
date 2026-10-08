#!/usr/bin/env python3
"""Download the full Our World in Data energy (+ CO2) files into data/raw_full/ and verify SHA-256.

Dataset: "Data on Energy by Our World in Data" (legacy release, owid/energy-data) - the source of the Kaggle dataset
"World Energy Consumption" (pralabhpoudel). Licence CC BY 4.0. Joined with "Data on CO2 and Greenhouse Gas Emissions by Our World in Data"
(owid/co2-data, CC BY 4.0). There is no Kaggle API key, so the canonical GitHub mirror is used, pinned to a commit so the checksums hold:
  Kaggle page: https://www.kaggle.com/datasets/pralabhpoudel/world-energy-consumption
  Energy:      https://github.com/owid/energy-data   (commit f8de88a4, file last changed 2026-04-27)
  CO2:         https://github.com/owid/co2-data      (commit 382ee6c6, 2026-06-02)
Use --latest to fetch the moving `master` branch instead (checksums will then differ and are only reported).
"""
import hashlib, pathlib, sys, urllib.request

ENERGY = "https://raw.githubusercontent.com/owid/energy-data/f8de88a4f6f9cab44f1cf606047cbd6c4414042c"
CO2 = "https://raw.githubusercontent.com/owid/co2-data/382ee6c662b0ece26e111f263b44c029afad7787"
FILES = {  # name: (base, sha256, bytes)
    "owid-energy-data.csv": (ENERGY, "266f2e2baad7975351bc9bb4aa061d22b1da9fe4c47d51d2ac6071e01e171f76", 9229369),
    "owid-energy-codebook.csv": (ENERGY, "3cc9b7db0d921496e2988568ce3aee5ed41f50431dd234a0663b5f0a4b2e32bb", 45793),
    "owid-co2-data.csv": (CO2, "7f78e2b218ce4bb8c538bbec04fdc9a7982e8d40bff972e650df603899edd5f6", 14377942),
    "owid-co2-codebook.csv": (CO2, "33b4f5e00efd58c7b83863f736beba1af4df946b43642b0400c3ec38648e0e8e", 24149),
}
latest = "--latest" in sys.argv
out = pathlib.Path(__file__).resolve().parents[1] / "data" / "raw_full"
out.mkdir(parents=True, exist_ok=True)
bad = 0
for name, (base, sha, size) in FILES.items():
    p = out / name
    if latest:
        base = base.rsplit("/", 1)[0] + "/master"
    if latest or not p.exists() or p.stat().st_size != size:
        url = f"{base}/{name}"
        print("downloading", url, f"({size / 1e6:.1f} MB)")
        tmp = p.with_suffix(".part")
        urllib.request.urlretrieve(url, tmp)
        tmp.replace(p)
    got = hashlib.sha256(p.read_bytes()).hexdigest()
    ok = got == sha
    print(f"{name:26s} {p.stat().st_size:>12,} bytes  {'OK' if ok else ('changed upstream ' if latest else 'CHECKSUM MISMATCH ') + got}")
    bad += (not ok) and not latest
sys.exit(1 if bad else 0)
