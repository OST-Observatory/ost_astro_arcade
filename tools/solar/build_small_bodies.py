"""Small bodies for the solar-system explorer: a reproducible sample of numbered asteroids
(main belt, Jupiter Trojans, near-Earth objects) and trans-Neptunian objects with their
orbital elements from the JPL Small-Body Database (sbdb_query API).
Output: godot/assets/data/solar/small_bodies.json
  {"columns": [...], "data": [[a, e, i, om, w, ma, n, epoch_jd, class], ...]}

    uv run solar/build_small_bodies.py
"""

import json
import random
from pathlib import Path

import requests

TOOLS = Path(__file__).resolve().parents[1]
REPO = TOOLS.parent
CACHE = TOOLS / ".cache/solar"
OUT = REPO / "godot/assets/data/solar/small_bodies.json"
SEED = 2026
# (SBDB orbit class, H min, H max, how many) – H limits keep the larger, known objects.
SAMPLE = [
    ("MBA", 0, 14.0, 8000), ("IMB", 0, 15.0, 500), ("OMB", 0, 13.0, 1500),
    ("TJN", 0, 14.0, 1500), ("TNO", 0, 8.0, 800), ("APO", 0, 18.0, 250),
    ("ATE", 0, 20.0, 60), ("AMO", 0, 18.0, 150), ("CEN", 0, 12.0, 80),
]
FIELDS = "a,e,i,om,w,ma,n,epoch,class"


def query(cls: str, hmin: float, hmax: float) -> list:
    path = CACHE / f"sbdb_{cls}_{hmin}_{hmax}.json"
    if path.exists():
        return json.loads(path.read_text())
    r = requests.get("https://ssd-api.jpl.nasa.gov/sbdb_query.api", params={
        "fields": FIELDS, "sb-kind": "a", "sb-class": cls,
        "sb-cdata": json.dumps({"AND": [f"H|RG|{hmin}|{hmax}"]}), "limit": 60000}, timeout=180)
    r.raise_for_status()
    rows = r.json().get("data", [])
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(rows))
    return rows


def main() -> None:
    rnd = random.Random(SEED)
    out = []
    for cls, hmin, hmax, n in SAMPLE:
        rows = [r for r in query(cls, hmin, hmax) if all(v is not None for v in r[:8])]
        pick = rnd.sample(rows, min(n, len(rows)))
        for r in pick:
            a, e, i, om, w, ma, mm, epoch = (float(x) for x in r[:8])
            if not (0.0 <= e < 1.0) or a <= 0.0:
                continue
            out.append([round(a, 5), round(e, 5), round(i, 4), round(om, 4), round(w, 4), round(ma, 4),
                        round(mm, 7), round(epoch, 1), cls])
        print(f"{cls}: {len(rows)} available, {len(pick)} taken")
    OUT.parent.mkdir(parents=True, exist_ok=True)
    OUT.write_text(json.dumps({"columns": FIELDS.split(","), "source": "JPL Small-Body Database", "data": out},
                              separators=(",", ":")))
    print(len(out), "small bodies ->", OUT, f"{OUT.stat().st_size // 1024} KB")


if __name__ == "__main__":
    main()
