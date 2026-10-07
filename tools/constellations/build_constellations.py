"""Builds the star and constellation data for the constellation game from d3-celestial
(Olaf Frohn, BSD-3-Clause): Hipparcos stars to 6 mag, constellation stick figures, star and
constellation names. Facts per constellation come from facts.yaml (de/en/es).
Output: godot/assets/data/constellations/sky.json

    uv run constellations/build_constellations.py
"""

import json
import math
import urllib.request
from pathlib import Path

import yaml

TOOLS = Path(__file__).resolve().parents[1]
REPO = TOOLS.parent
CACHE = TOOLS / ".cache/d3c"
OUT = REPO / "godot/assets/data/constellations/sky.json"
BASE = "https://raw.githubusercontent.com/ofrohn/d3-celestial/master/data/"
FILES = ["constellations.lines.json", "stars.6.json", "starnames.json", "constellations.json"]
MAG_LIMIT = 6.0
# Curated, visible from Potsdam (52.4 N), by difficulty.
LEVELS = {
    "explorer": ["Dip", "Cas", "Cyg", "Lyr", "Leo", "UMi", "CrB", "Del", "Aql"],
    "researcher": ["Ori", "Gem", "Tau", "Boo", "Peg", "Aur", "Cep", "CMa"],
    "pro": ["UMa", "Per", "Dra", "Her", "And", "Vir", "Cnc"],
}
# Asterisms: a well-known part of a constellation, used as an easy target.
ASTERISMS = {
    "Dip": {"of": "UMa", "hips": [53910, 54061, 58001, 59774, 62956, 65378, 67301],
            "name": {"de": "Großer Wagen", "en": "Big Dipper", "es": "Carro Mayor", "la": "Ursa Major"}},
}


def load(name: str):
    path = CACHE / name
    if not path.exists():
        CACHE.mkdir(parents=True, exist_ok=True)
        path.write_bytes(urllib.request.urlopen(BASE + name, timeout=60).read())
    return json.loads(path.read_text())


def unit(ra: float, dec: float) -> tuple[float, float, float]:
    r, d = math.radians(ra), math.radians(dec)
    return (math.cos(d) * math.cos(r), math.cos(d) * math.sin(r), math.sin(d))


def sep(a, b) -> float:
    dot = sum(x * y for x, y in zip(a, b))
    return math.degrees(math.acos(max(-1.0, min(1.0, dot))))


def main() -> None:
    lines = {f["id"]: f for f in load("constellations.lines.json")["features"]}
    stars_raw = load("stars.6.json")["features"]
    names = load("starnames.json")
    cons = {f["id"]: f["properties"] for f in load("constellations.json")["features"]}
    facts = yaml.safe_load((Path(__file__).parent / "facts.yaml").read_text())

    stars = []
    for f in stars_raw:
        mag = f["properties"]["mag"]
        if mag is None or mag > MAG_LIMIT:
            continue
        ra, dec = f["geometry"]["coordinates"]
        try:
            bv = float(f["properties"].get("bv") or 0.6)
        except ValueError:
            bv = 0.6
        stars.append({"hip": f["id"], "ra": round(ra % 360.0, 4), "dec": round(dec, 4), "mag": mag, "bv": round(bv, 2)})
    vec = {s["hip"]: unit(s["ra"], s["dec"]) for s in stars}

    def nearest(ra: float, dec: float) -> int:
        u = unit(ra % 360.0, dec)
        best, best_d = None, 1e9
        for s in stars:
            if abs(s["dec"] - dec) > 0.2:
                continue
            d = sep(u, vec[s["hip"]])
            if d < best_d:
                best, best_d = s["hip"], d
        if best_d > 0.1:
            raise ValueError(f"no star at {ra} {dec} ({best_d:.3f} deg)")
        return best

    out_cons = []
    for level, ids in LEVELS.items():
        for cid in ids:
            ast = ASTERISMS.get(cid)
            edges = set()
            for path in lines[ast["of"] if ast else cid]["geometry"]["coordinates"]:
                hips = [nearest(ra, dec) for ra, dec in path]
                for a, b in zip(hips, hips[1:]):
                    if a != b and (not ast or (a in ast["hips"] and b in ast["hips"])):
                        edges.add(tuple(sorted((a, b))))
            members = sorted({h for e in edges for h in e})
            cx = [sum(vec[h][i] for h in members) for i in range(3)]
            n = math.sqrt(sum(c * c for c in cx))
            cx = [c / n for c in cx]
            center_ra = math.degrees(math.atan2(cx[1], cx[0])) % 360.0
            center_dec = math.degrees(math.asin(cx[2]))
            radius = max(sep(cx, vec[h]) for h in members)
            brightest = min(members, key=lambda h: next(s["mag"] for s in stars if s["hip"] == h))
            p = cons[ast["of"] if ast else cid]
            out_cons.append({
                "id": cid, "level": level,
                "name": ast["name"] if ast else {"de": p["de"], "en": p["en"], "es": p["es"], "la": p["name"]},
                "center": [round(center_ra, 3), round(center_dec, 3)], "radius": round(radius, 3),
                "edges": [list(e) for e in sorted(edges)], "brightest": brightest,
                "fact": facts[cid],
            })
            print(f"{cid} ({level}): {len(edges)} lines, {len(members)} stars, r = {radius:.1f} deg")

    star_names = {}
    for s in stars:
        nm = names.get(str(s["hip"]))
        if nm and nm.get("name") and s["mag"] < 3.5:
            star_names[s["hip"]] = {"en": nm["name"], "de": nm.get("de") or nm["name"]}
    OUT.parent.mkdir(parents=True, exist_ok=True)
    OUT.write_text(json.dumps({"stars": [[s["hip"], s["ra"], s["dec"], s["mag"], s["bv"]] for s in stars],
                               "names": star_names, "constellations": out_cons}, ensure_ascii=False))
    print(len(stars), "stars,", len(out_cons), "constellations ->", OUT, f"{OUT.stat().st_size // 1024} KB")


if __name__ == "__main__":
    main()
