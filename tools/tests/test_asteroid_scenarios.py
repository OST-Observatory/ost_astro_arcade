"""Sanity checks for the generated asteroid scenarios (run after build_scenarios.py)."""

import json
import math
from pathlib import Path

import pytest

DATA = Path(__file__).resolve().parents[2] / "godot/assets/data/asteroid"
INDEX = json.loads((DATA / "index.json").read_text()) if (DATA / "index.json").exists() else {"scenarios": []}
FIELD_HALF_W, FIELD_HALF_H = 35.7 * 60 / 2, 23.8 * 60 / 2  # arcsec


def scenarios():
    return [json.loads((DATA / "scenarios" / f"{e['id']}.json").read_text()) for e in INDEX["scenarios"]]


def test_index_not_empty_and_files_exist():
    assert len(INDEX["scenarios"]) >= 10
    for e in INDEX["scenarios"]:
        assert (DATA / "scenarios" / f"{e['id']}.json").exists()


def test_all_difficulties_available():
    diffs = {e["difficulty"] for e in INDEX["scenarios"]}
    assert {"explorer", "researcher"} <= diffs


@pytest.mark.parametrize("sc", scenarios(), ids=lambda s: s["id"])
def test_scenario_is_observable_and_consistent(sc):
    best = sc["track"][sc["best_index"]]
    assert best["sun_alt"] < -12, "best time must be dark"
    assert best["alt"] > 30, "target well above the horizon"
    assert 7.0 <= sc["v_best"] <= 17.5
    # Field centre is the target at the best time.
    assert abs(best["xi"]) < 1.0 and abs(best["eta"]) < 1.0
    # Frames 1..3 (best-2 .. best+2 in 10-min steps) stay within the fetched star field.
    r_field = sc["field"]["radius_deg"] * 3600
    for i in range(max(0, sc["best_index"] - 2), min(len(sc["track"]), sc["best_index"] + 3)):
        t = sc["track"][i]
        assert math.hypot(t["xi"], t["eta"]) + math.hypot(FIELD_HALF_W, FIELD_HALF_H) <= r_field + 60
    # Stars: plausible count and magnitudes, most within the radius.
    stars = sc["field"]["stars"]
    assert len(stars) >= 40
    assert all(s[2] < 18.01 for s in stars)
    assert sc["facts"]["fullname"]
    assert sc["elements"]["a"] > 0.5


def test_moon_values_plausible():
    for sc in scenarios():
        for t in sc["track"]:
            assert 0.0 <= t["moon_illum"] <= 1.0
            assert 0.0 <= t["moon_sep"] <= 180.0
