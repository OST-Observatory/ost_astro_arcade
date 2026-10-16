"""Measured rotation curves and reference mass models for the galaxy builder.

Targets:
  milkyway  Gaia/APOGEE circular velocities, Eilers et al. 2019, ApJ 871, 120 (Table 1,
            5–21 kpc; statistical errors plus the 3 % systematic error stated in the paper)
  ngc3198   SPARC, Lelli, McGaugh & Schombert 2016, AJ 152, 157 (HI rotation curve)
  ddo154    SPARC (gas-rich dwarf galaxy)

Reference models use the components of the game (all formulas match
godot/games/galaxy/physics/galaxy_potential.gd):
  bulge  Hernquist           v^2 = G M r / (r + a)^2
  disk   Miyamoto–Nagai      v^2 = G M R^2 / (R^2 + (a + b)^2)^1.5   (stars and gas)
  halo   cored logarithmic   v^2 = vh^2 r^2 / (r^2 + rc^2)
The visible matter is set independently of the observed curve: for the Milky Way from the
literature (Bland-Hawthorn & Gerhard 2016), for SPARC galaxies by fitting the measured gas
and stellar contributions (3.6 µm mass-to-light ratio 0.5). Only the dark halo is fitted to
the observed rotation curve, just as astronomers found that something is missing.
Output: godot/assets/data/galaxy/rotation_curves.json (kpc, km/s, solar masses)

    uv run galaxy/build_rotation_curves.py
"""

import io
import json
import re
import tarfile
import urllib.request
import zipfile
from pathlib import Path

import numpy as np

TOOLS = Path(__file__).resolve().parents[1]
REPO = TOOLS.parent
CACHE = TOOLS / ".cache/rotcurves"
OUT = REPO / "godot/assets/data/galaxy/rotation_curves.json"
G = 4.30091e-6          # kpc (km/s)^2 / Msun
EILERS_URL = "https://arxiv.org/e-print/1810.09466"
SPARC_URL = "https://astroweb.case.edu/SPARC/Rotmod_LTG.zip"
UPSILON_DISK = 0.5      # SPARC stellar mass-to-light ratio at 3.6 µm
UPSILON_BULGE = 0.7


def fetch(url: str, path: Path) -> bytes:
    if not path.exists():
        path.parent.mkdir(parents=True, exist_ok=True)
        req = urllib.request.Request(url, headers={"User-Agent": "ost-space-lab/0.1"})
        path.write_bytes(urllib.request.urlopen(req, timeout=120).read())
    return path.read_bytes()


# --- model curves (km/s) -------------------------------------------------------------

def v2_hernquist(r, m, a):
    return G * m * r / (r + a) ** 2


def v2_mn(r, m, a, b):
    return G * m * r**2 / (r**2 + (a + b) ** 2) ** 1.5


def v2_halo(r, vh, rc):
    return vh**2 * r**2 / (r**2 + rc**2)


def nelder_mead(f, x0, step, iters=4000):
    """Small Nelder–Mead minimiser (scipy is not a dependency)."""
    n = len(x0)
    pts = [np.array(x0, float)] + [np.array(x0, float) + np.eye(n)[i] * step[i] for i in range(n)]
    vals = [f(p) for p in pts]
    for _ in range(iters):
        order = np.argsort(vals)
        pts = [pts[i] for i in order]
        vals = [vals[i] for i in order]
        centroid = np.mean(pts[:-1], axis=0)
        xr = centroid + (centroid - pts[-1])
        fr = f(xr)
        if fr < vals[0]:
            xe = centroid + 2 * (centroid - pts[-1])
            fe = f(xe)
            pts[-1], vals[-1] = (xe, fe) if fe < fr else (xr, fr)
        elif fr < vals[-2]:
            pts[-1], vals[-1] = xr, fr
        else:
            xc = centroid + 0.5 * (pts[-1] - centroid)
            fc = f(xc)
            if fc < vals[-1]:
                pts[-1], vals[-1] = xc, fc
            else:
                pts = [pts[0] + 0.5 * (p - pts[0]) for p in pts]
                vals = [f(p) for p in pts]
        if np.std(vals) < 1e-12:
            break
    i = int(np.argmin(vals))
    return pts[i], vals[i]


def fit_mn(r, v2_target, a0):
    """Fits a Miyamoto–Nagai disk (b = 0.1 a) to a measured v^2 contribution."""
    w = np.abs(v2_target).max() or 1.0

    def cost(p):
        m, a = np.exp(p)
        return float(np.mean((v2_mn(r, m, a, 0.1 * a) - v2_target) ** 2)) / w**2

    best, _ = nelder_mead(cost, [np.log(max(np.max(v2_target), 1.0) * r[-1] / G), np.log(a0)], [1.0, 0.5])
    m, a = np.exp(best)
    return {"m": float(m), "a": float(a), "b": float(0.1 * a)}


def fit_halo(r, v, err, v2_baryons):
    def cost(p):
        vh, rc = np.exp(p)
        model = np.sqrt(np.maximum(v2_baryons + v2_halo(r, vh, rc), 0.0))
        return float(np.mean(((model - v) / err) ** 2))

    best, chi2 = nelder_mead(cost, [np.log(np.max(v)), np.log(r[len(r) // 3])], [0.3, 0.5])
    vh, rc = np.exp(best)
    return {"vh": float(vh), "rc": float(rc)}, chi2


def match(v_model, v_obs, err) -> float:
    """100 % = within the error bars everywhere; deviations beyond them cost 2.5 % per 1 %."""
    excess = np.maximum(np.abs(v_model - v_obs) - err, 0.0) / v_obs
    return float(np.clip(100.0 - 250.0 * np.mean(excess), 0.0, 100.0))


# --- data ------------------------------------------------------------------------------

def eilers():
    raw = fetch(EILERS_URL, CACHE / "eilers.tar.gz")
    with tarfile.open(fileobj=io.BytesIO(raw)) as tar:
        tex = tar.extractfile("main.tex").read().decode()
    body = tex[tex.index(r"\startdata"):tex.index(r"\enddata")]
    rows = []
    for line in body.splitlines():
        line = line.strip()
        if not line or line.startswith("%") or "&" not in line:
            continue
        r, v, lo, hi = (float(x) for x in line.rstrip("\\ ").split("&"))
        stat = 0.5 * (lo + hi)
        if stat < 10.0:      # the last few bins have very large errors
            rows.append((r, v, float(np.hypot(stat, 0.03 * v))))
    return np.array(rows)


def sparc(name: str):
    raw = fetch(SPARC_URL, CACHE / "Rotmod_LTG.zip")
    with zipfile.ZipFile(io.BytesIO(raw)) as z:
        txt = z.read(f"{name}_rotmod.dat").decode()
    dist = float(re.search(r"Distance = ([\d.]+)", txt).group(1))
    rows = np.array([[float(x) for x in l.split()[:6]] for l in txt.splitlines() if l and not l.startswith("#")])
    return dist, rows


def signed_sq(v):
    return v * np.abs(v)


def build_milky_way():
    d = eilers()
    r, v, err = d[:, 0], d[:, 1], d[:, 2]
    comp = {
        "bh": 4.3e6,                                    # Sgr A* (GRAVITY 2019)
        "bulge": {"m": 1.5e10, "a": 0.6},               # bulge/bar, Bland-Hawthorn & Gerhard 2016
        "disk": {"m": 3.5e10, "a": 3.0, "b": 0.3},      # thin + thick stellar disk
        "gas": {"m": 1.0e10, "a": 7.0, "b": 0.1},       # cold gas (HI + H2)
    }
    v2b = v2_hernquist(r, comp["bulge"]["m"], comp["bulge"]["a"]) + v2_mn(r, **comp["disk"]) + v2_mn(r, **comp["gas"])
    halo, chi2 = fit_halo(r, v, err, v2b)
    comp["halo"] = {**halo, "rt": 100.0}
    return {
        "id": "milkyway", "distance_mpc": 0.0, "source": "Eilers et al. 2019 (Gaia/APOGEE); Bland-Hawthorn & Gerhard 2016",
        "data": d.round(2).tolist(), "model": comp, "chi2": chi2,
    }


def build_sparc(gid: str, name: str, rt: float):
    dist, d = sparc(name)
    r, v, err, vgas, vdisk, vbul = d.T
    err = np.maximum(err, 0.03 * v)
    comp = {"bh": 0.0}
    comp["gas"] = fit_mn(r, signed_sq(vgas), r[-1] / 3.0)
    comp["disk"] = fit_mn(r, UPSILON_DISK * signed_sq(vdisk), r[len(r) // 4])
    if np.any(vbul > 0):
        comp["bulge"] = {"m": 1e9, "a": 0.5}  # not needed for the chosen galaxies
    else:
        comp["bulge"] = {"m": 0.0, "a": 0.5}
    v2b = v2_mn(r, **comp["gas"]) + v2_mn(r, **comp["disk"]) + v2_hernquist(r, comp["bulge"]["m"], comp["bulge"]["a"])
    halo, chi2 = fit_halo(r, v, err, v2b)
    comp["halo"] = {**halo, "rt": rt}
    data = np.stack([r, v, err], axis=1)
    return {"id": gid, "distance_mpc": dist, "source": "SPARC, Lelli, McGaugh & Schombert 2016", "data": data.round(2).tolist(),
            "model": comp, "chi2": chi2}


def model_curve(comp, r):
    v2 = (G * comp["bh"] / r + v2_hernquist(r, comp["bulge"]["m"], comp["bulge"]["a"]) + v2_mn(r, **comp["disk"])
          + v2_mn(r, **comp["gas"]) + v2_halo(r, comp["halo"]["vh"], comp["halo"]["rc"]))
    return np.sqrt(v2)


def main() -> None:
    targets = [build_milky_way(), build_sparc("ngc3198", "NGC3198", 90.0), build_sparc("ddo154", "DDO154", 25.0)]
    for t in targets:
        d = np.array(t["data"])
        comp = t["model"]
        full = match(model_curve(comp, d[:, 0]), d[:, 1], d[:, 2])
        no_halo = dict(comp, halo={"vh": 0.0, "rc": 1.0, "rt": 1.0})
        t["match_reference"] = round(full, 1)
        t["match_without_halo"] = round(match(model_curve(no_halo, d[:, 0]), d[:, 1], d[:, 2]), 1)
        m = comp
        print(f"{t['id']}: {len(d)} points {d[0,0]:.1f}-{d[-1,0]:.1f} kpc; stars {m['disk']['m'] + m['bulge']['m']:.2e}, "
              f"gas {m['gas']['m']:.2e} Msun, halo vh {m['halo']['vh']:.0f} km/s rc {m['halo']['rc']:.1f} kpc; "
              f"match {full:.1f} %, without halo {t['match_without_halo']} %")
        for k in ("disk", "gas", "bulge"):
            m[k] = {kk: float(f"{vv:.4g}") for kk, vv in m[k].items()}
        m["halo"] = {kk: round(vv, 2) for kk, vv in m["halo"].items()}
        t.pop("chi2")
    OUT.parent.mkdir(parents=True, exist_ok=True)
    OUT.write_text(json.dumps({"units": {"r": "kpc", "v": "km/s", "m": "Msun"}, "targets": targets}, indent=1))
    print("->", OUT)


if __name__ == "__main__":
    main()
