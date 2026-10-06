"""Builds the scenario library for the asteroid hunt.

For real asteroids this script finds good observing nights from the OST in Golm, then
stores per scenario:
  * the night's ephemeris in 10-minute steps (JPL Horizons): RA/Dec, alt/az, V, rates
  * Sun and Moon altitude, Moon illumination and separation (Skyfield, DE421)
  * osculating orbital elements (Horizons) and facts (JPL SBDB: class, size, discovery)
  * the real star field around the target (Gaia DR3, G < 18) in tangent-plane arcsec

Output: godot/assets/data/asteroid/index.json and scenarios/<id>.json
Raw query results are cached in tools/.cache/ so re-runs work offline.

    uv run asteroid/build_scenarios.py [--max 40] [--only 433,1036]
"""

from __future__ import annotations

import argparse
import multiprocessing as mp
import json
import math
from datetime import date, datetime, timedelta
from pathlib import Path

import numpy as np
import requests
from astroquery.gaia import Gaia
from astroquery.jplhorizons import Horizons
from skyfield import almanac
from skyfield.api import Loader, wgs84

from candidates import AUTO_SAMPLE, AUTO_SEED, CANDIDATES

TOOLS = Path(__file__).resolve().parents[1]
REPO = TOOLS.parent
CACHE = TOOLS / ".cache"
OUT = REPO / "godot/assets/data/asteroid"

SITE = {"lon": 12.9733, "lat": 52.4092, "elevation": 0.08}  # km
SURVEY_START = date(2026, 10, 1)
SURVEY_END = date(2028, 3, 31)

# Instrument: Planewave CDK20 + QHY600 -> 35.7' x 23.8' field.
FIELD_HALF_DIAG_DEG = math.hypot(35.7 / 2, 23.8 / 2) / 60.0
GAIA_G_LIMIT = 18.0
GAIA_TIMEOUT_S = 180

# Night selection
MIN_ALT = 35.0
V_RANGE = (7.0, 17.8)
MIN_ELONG = 90.0
MAX_SUN_ALT = -15.0


def cached_json(name: str, fetch):
    path = CACHE / name
    if path.exists():
        return json.loads(path.read_text())
    data = fetch()
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(data))
    return data


def horizons_ephem(number: int, start: str, stop: str, step: str, quantities: str) -> dict:
    def fetch():
        eph = Horizons(id=f"{number};", location=SITE,
                       epochs={"start": start, "stop": stop, "step": step}).ephemerides(quantities=quantities)
        cols = [c for c in eph.colnames if eph[c].dtype.kind in "fiu" or c in ("datetime_str", "targetname")]
        return {c: [v if not hasattr(v, "item") else v.item() for v in eph[c].tolist()] for c in cols}
    return cached_json(f"horizons/{number}_{start}_{stop}_{step}_{quantities.replace(',', '-')}.json", fetch)


def horizons_elements(number: int, jd: float) -> dict:
    def fetch():
        el = Horizons(id=f"{number};", location="500@10", epochs=jd).elements()
        keys = ["a", "e", "incl", "Omega", "w", "M", "n", "P", "datetime_jd"]
        return {k: float(el[k][0]) for k in keys}
    return cached_json(f"elements/{number}_{jd:.1f}.json", fetch)


def sbdb_facts(number: int) -> dict:
    def fetch():
        r = requests.get("https://ssd-api.jpl.nasa.gov/sbdb.api",
                         params={"sstr": str(number), "phys-par": "1", "discovery": "1"}, timeout=60)
        r.raise_for_status()
        return r.json()
    raw = cached_json(f"sbdb/{number}.json", fetch)
    obj = raw.get("object", {})
    phys = {p["name"]: p.get("value") for p in raw.get("phys_par", [])}
    disc = raw.get("discovery", {}) or {}
    return {
        "fullname": obj.get("fullname", str(number)).strip(),
        "name": obj.get("shortname", "").split(" ", 1)[-1] if obj.get("shortname") else "",
        "class_code": obj.get("orbit_class", {}).get("code", ""),
        "class_name": obj.get("orbit_class", {}).get("name", ""),
        "neo": bool(obj.get("neo")),
        "pha": bool(obj.get("pha")),
        "H": _num(phys.get("H")),
        "diameter_km": _num(phys.get("diameter")),
        "rot_per_h": _num(phys.get("rot_per")),
        "discovery": {
            "who": disc.get("who"),
            "date": disc.get("date"),
            "location": disc.get("location"),
            "site": disc.get("site"),
        },
    }


def _num(v):
    try:
        return float(v)
    except (TypeError, ValueError):
        return None


def gaia_field(ra0: float, dec0: float, radius: float) -> list:
    key = f"gaia/{ra0:.4f}_{dec0:.4f}_{radius:.3f}_{GAIA_G_LIMIT}.json"

    def fetch():
        q = f"""SELECT TOP 30000 ra, dec, phot_g_mean_mag, bp_rp, phot_variable_flag
                FROM gaiadr3.gaia_source
                WHERE 1 = CONTAINS(POINT(ra, dec), CIRCLE({ra0}, {dec0}, {radius}))
                  AND phot_g_mean_mag < {GAIA_G_LIMIT}
                ORDER BY phot_g_mean_mag"""
        return _run_with_timeout(_gaia_query, (q,), GAIA_TIMEOUT_S)
    return cached_json(key, fetch)


def _gaia_query(q: str) -> list:
    Gaia.ROW_LIMIT = -1
    t = Gaia.launch_job_async(q).get_results()
    return [[float(r["ra"]), float(r["dec"]), float(r["phot_g_mean_mag"]),
             float(r["bp_rp"]) if r["bp_rp"] is not np.ma.masked else 0.8,
             1 if r["phot_variable_flag"] == "VARIABLE" else 0] for r in t]


def _worker(fn, args, queue):
    try:
        queue.put(("ok", fn(*args)))
    except Exception as ex:  # report to the parent instead of dying silently
        queue.put(("err", repr(ex)))


def _run_with_timeout(fn, args, timeout_s: float):
    """Runs fn in a child process and kills it if it hangs (the Gaia archive sometimes does)."""
    queue = mp.Queue()
    proc = mp.Process(target=_worker, args=(fn, args, queue), daemon=True)
    proc.start()
    try:
        status, value = queue.get(timeout=timeout_s)
    except Exception:
        proc.kill()
        raise TimeoutError(f"{fn.__name__} took longer than {timeout_s}s")
    proc.join(5)
    if status != "ok":
        raise RuntimeError(value)
    return value


def gnomonic(ra, dec, ra0, dec0):
    """Tangent-plane projection in arcsec (xi east, eta north)."""
    ra, dec, ra0, dec0 = map(np.radians, (ra, dec, ra0, dec0))
    cosc = np.sin(dec0) * np.sin(dec) + np.cos(dec0) * np.cos(dec) * np.cos(ra - ra0)
    xi = np.cos(dec) * np.sin(ra - ra0) / cosc
    eta = (np.cos(dec0) * np.sin(dec) - np.sin(dec0) * np.cos(dec) * np.cos(ra - ra0)) / cosc
    return np.degrees(xi) * 3600.0, np.degrees(eta) * 3600.0


class SkyCalc:
    def __init__(self):
        load = Loader(CACHE / "skyfield")
        de421 = Path("/home/schedar/projects/astro_mini_games/de421.bsp")
        self.eph = load(str(de421)) if de421.exists() else load("de421.bsp")
        self.ts = load.timescale()
        self.site = self.eph["earth"] + wgs84.latlon(SITE["lat"], SITE["lon"], SITE["elevation"] * 1000)

    def sun_moon(self, times: list[datetime], ra=None, dec=None):
        t = self.ts.from_datetimes(times)
        sun = self.site.at(t).observe(self.eph["sun"]).apparent().altaz()[0].degrees
        moon_app = self.site.at(t).observe(self.eph["moon"]).apparent()
        moon_alt = moon_app.altaz()[0].degrees
        illum = almanac.fraction_illuminated(self.eph, "moon", t)
        sep = None
        if ra is not None:
            mra, mdec, _ = moon_app.radec()
            sep = _sep_deg(np.asarray(ra), np.asarray(dec), mra.hours * 15.0, mdec.degrees)
        return sun, moon_alt, illum, sep


def _sep_deg(ra1, dec1, ra2, dec2):
    ra1, dec1, ra2, dec2 = map(np.radians, (ra1, dec1, ra2, dec2))
    c = np.sin(dec1) * np.sin(dec2) + np.cos(dec1) * np.cos(dec2) * np.cos(ra1 - ra2)
    return np.degrees(np.arccos(np.clip(c, -1, 1)))


def parse_dt(s: str) -> datetime:
    from datetime import timezone
    for fmt in ("%Y-%b-%d %H:%M", "%Y-%b-%d %H:%M:%S.%f", "%Y-%b-%d %H:%M:%S"):
        try:
            return datetime.strptime(s, fmt).replace(tzinfo=timezone.utc)
        except ValueError:
            pass
    raise ValueError(s)


def auto_candidates() -> list[tuple[int, str]]:
    """Reproducible random sample per orbit class from JPL SBDB (see candidates.AUTO_SAMPLE)."""
    import random
    rnd = random.Random(AUTO_SEED)
    out = []
    for cls, hmin, hmax, n in AUTO_SAMPLE:
        def fetch(cls=cls, hmin=hmin, hmax=hmax):
            r = requests.get("https://ssd-api.jpl.nasa.gov/sbdb_query.api", params={
                "fields": "pdes,name,H,class", "sb-kind": "a", "sb-ns": "n", "sb-class": cls,
                "sb-cdata": json.dumps({"AND": [f"H|RG|{hmin}|{hmax}"]}), "limit": 5000}, timeout=60)
            r.raise_for_status()
            return r.json()["data"]
        rows = cached_json(f"sbdb_query/{cls}_{hmin}_{hmax}.json", fetch)
        for row in rnd.sample(rows, min(n, len(rows))):
            out.append((int(row[0]), f"{row[1] or row[0]} ({cls}, H={row[2]}) – auto"))
    return out


def survey(number: int, sky: SkyCalc) -> list[dict]:
    """Candidate nights (keyed by evening date): best dark sample every 2 h."""
    e = horizons_ephem(number, f"{SURVEY_START} 17:00", f"{SURVEY_END} 07:00", "2h", "1,4,9,20,23")
    times = [parse_dt(s) for s in e["datetime_str"]]
    sun, _, illum, _ = sky.sun_moon(times)
    best: dict[date, dict] = {}
    for i, t in enumerate(times):
        v = e["V"][i]
        if not (sun[i] <= MAX_SUN_ALT and e["EL"][i] >= MIN_ALT and V_RANGE[0] <= v <= V_RANGE[1]
                and e["elong"][i] >= MIN_ELONG):
            continue
        night = (t - timedelta(hours=12)).date()
        if night not in best or e["EL"][i] > best[night]["alt"]:
            best[night] = {"date": night, "alt": e["EL"][i], "V": v, "moon": float(illum[i])}
    return sorted(best.values(), key=lambda n: n["date"])


def pick_nights(nights: list[dict], k: int = 2) -> list[dict]:
    """Best dark night, plus a bright-moon night at least 60 days away (variety)."""
    if not nights:
        return []
    dark = [n for n in nights if n["moon"] < 0.35] or nights
    first = max(dark, key=lambda n: n["alt"] - 0.5 * max(0.0, n["V"] - 15))
    picks = [first]
    bright = [n for n in nights if n["moon"] > 0.6 and abs((n["date"] - first["date"]).days) > 60]
    if bright and k > 1:
        picks.append(max(bright, key=lambda n: n["alt"]))
    return picks


def build_scenario(number: int, night: date, sky: SkyCalc) -> dict | None:
    start = f"{night} 15:00"
    stop = f"{night + timedelta(days=1)} 06:00"
    e = horizons_ephem(number, start, stop, "10m", "1,3,4,9,19,20,23")
    times = [parse_dt(s) for s in e["datetime_str"]]
    ra, dec = np.array(e["RA"]), np.array(e["DEC"])
    sun, moon_alt, illum, sep = sky.sun_moon(times, ra, dec)

    dark = (np.array(sun) < -12.0) & (np.array(e["EL"]) > 20.0)
    if dark.sum() < 6:
        return None
    best = int(np.argmax(np.where(dark, np.array(e["EL"]), -99)))
    ra0, dec0 = float(ra[best]), float(dec[best])
    # Star field must cover the target's path during the usable part of the night.
    path = _sep_deg(ra[dark], dec[dark], ra0, dec0).max()
    radius = min(1.2, FIELD_HALF_DIAG_DEG + 0.05 + float(path))
    stars = gaia_field(round(ra0, 4), round(dec0, 4), round(radius, 3))
    if len(stars) < 40:
        return None
    s = np.array(stars)
    xi, eta = gnomonic(s[:, 0], s[:, 1], ra0, dec0)
    txi, teta = gnomonic(ra, dec, ra0, dec0)

    facts = sbdb_facts(number)
    jd_mid = 2440587.5 + times[best].timestamp() / 86400.0
    elements = horizons_elements(number, round(jd_mid, 1))

    track = []
    for i, t in enumerate(times):
        track.append({
            "t": t.strftime("%Y-%m-%dT%H:%M:%SZ"),
            "ra": round(float(ra[i]), 6), "dec": round(float(dec[i]), 6),
            "xi": round(float(txi[i]), 2), "eta": round(float(teta[i]), 2),
            "alt": round(e["EL"][i], 2), "az": round(e["AZ"][i], 2),
            "v": e["V"][i],
            "rate_ra": e["RA_rate"][i], "rate_dec": e["DEC_rate"][i],  # arcsec/h (RA*cos(dec))
            "delta_au": round(e["delta"][i], 6), "r_au": round(e["r"][i], 6),
            "sun_alt": round(float(sun[i]), 2), "moon_alt": round(float(moon_alt[i]), 2),
            "moon_illum": round(float(illum[i]), 3), "moon_sep": round(float(sep[i]), 2),
        })
    rate = math.hypot(e["RA_rate"][best], e["DEC_rate"][best])
    return {
        "id": f"{number}_{night.isoformat()}",
        "number": number,
        "facts": facts,
        "night": night.isoformat(),
        "best_index": best,
        "v_best": e["V"][best],
        "rate_arcsec_h": round(rate, 2),
        "elements": elements,
        "field": {
            "ra0": ra0, "dec0": dec0, "radius_deg": radius,
            "g_limit": GAIA_G_LIMIT,
            # [xi_arcsec, eta_arcsec, G, bp_rp, variable]
            "stars": [[round(float(a), 1), round(float(b), 1), round(float(g), 2), round(float(c), 2), int(v)]
                      for a, b, g, c, v in zip(xi, eta, s[:, 2], s[:, 3], s[:, 4])],
        },
        "track": track,
    }


def difficulty_hint(sc: dict) -> str:
    """explorer: bright and/or fast; pro: faint or slow."""
    px_per_20min = sc["rate_arcsec_h"] / 3.0 / 1.394
    if sc["v_best"] <= 13.5 and px_per_20min >= 6:
        return "explorer"
    if sc["v_best"] >= 15.8 or px_per_20min < 4:
        return "pro"
    return "researcher"


def _write_index(index: list) -> None:
    (OUT / "index.json").write_text(json.dumps({"generated": datetime.now().isoformat(timespec="seconds"),
                                                "site": SITE, "scenarios": index}, indent=1))


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--max", type=int, default=40)
    ap.add_argument("--only", default="")
    ap.add_argument("--auto", action="store_true", help="add the random SBDB sample")
    args = ap.parse_args()
    only = {int(x) for x in args.only.split(",") if x}

    sky = SkyCalc()
    (OUT / "scenarios").mkdir(parents=True, exist_ok=True)
    index = []
    candidates = list(CANDIDATES) + (auto_candidates() if args.auto else [])
    for number, note in candidates:
        if only and number not in only:
            continue
        if len(index) >= args.max:
            break
        try:
            nights = survey(number, sky)
        except Exception as ex:  # one bad object must not stop the build
            print(f"  ({number}) survey failed: {ex}")
            continue
        picks = pick_nights(nights)
        print(f"({number}) {note}: {len(nights)} good nights -> {[str(p['date']) for p in picks]}")
        for p in picks:
            try:
                sc = build_scenario(number, p["date"], sky)
            except Exception as ex:
                print(f"  {p['date']}: failed: {ex}")
                continue
            if sc is None:
                print(f"  {p['date']}: skipped (no dark window or too few stars)")
                continue
            sc["difficulty"] = difficulty_hint(sc)
            (OUT / "scenarios" / f"{sc['id']}.json").write_text(json.dumps(sc, separators=(",", ":")))
            index.append({
                "id": sc["id"], "number": number, "name": sc["facts"]["name"],
                "class_code": sc["facts"]["class_code"], "night": sc["night"],
                "v": sc["v_best"], "rate_arcsec_h": sc["rate_arcsec_h"],
                "stars": len(sc["field"]["stars"]), "difficulty": sc["difficulty"],
            })
            _write_index(index)
            print(f"  {sc['id']}: V={sc['v_best']:.1f} rate={sc['rate_arcsec_h']:.0f}\"/h "
                  f"stars={len(sc['field']['stars'])} -> {sc['difficulty']}")
    _write_index(index)
    print(f"{len(index)} scenarios written to {OUT}")


if __name__ == "__main__":
    main()
