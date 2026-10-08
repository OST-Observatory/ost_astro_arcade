"""Saturn's rings as a 1024 x 1 RGBA strip (inner edge of the C ring to the F ring), drawn
from the real ring boundaries (radii in km from Saturn's centre). Own work, no licence issues.
Output: godot/assets/solar/saturn_rings.png  (u = 0 at 74,500 km, u = 1 at 140,500 km)

    uv run solar/make_rings.py
"""

from pathlib import Path

import numpy as np
from PIL import Image

REPO = Path(__file__).resolve().parents[2]
OUT = REPO / "godot/assets/solar/saturn_rings.png"
R_IN, R_OUT = 74500.0, 140500.0
# (inner km, outer km, opacity, brightness)
RINGS = [
    (74500, 92000, 0.12, 0.55),      # C ring (faint)
    (92000, 117580, 0.85, 1.0),      # B ring (bright, dense)
    (117580, 122170, 0.06, 0.4),     # Cassini Division
    (122170, 133423, 0.55, 0.85),    # A ring (inner part)
    (133423, 133745, 0.0, 0.0),      # Encke Gap
    (133745, 136775, 0.5, 0.8),      # A ring (outer part)
    (140180, 140500, 0.35, 0.9),     # F ring (narrow)
]


def main() -> None:
    n = 1024
    r = R_IN + (np.arange(n) + 0.5) / n * (R_OUT - R_IN)
    alpha = np.zeros(n)
    bright = np.zeros(n)
    for a, b, op, br in RINGS:
        m = (r >= a) & (r < b)
        alpha[m] = op
        bright[m] = br
    rng = np.random.default_rng(7)
    ripple = 1.0 + 0.12 * rng.standard_normal(n).cumsum() / np.sqrt(np.arange(1, n + 1))
    alpha = np.clip(alpha * (0.85 + 0.15 * np.cos(r / 900.0)) * np.clip(ripple, 0.7, 1.3), 0, 1)
    base = np.array([226, 208, 176], float)
    rgb = np.clip(base[None, :] * (0.55 + 0.45 * bright[:, None]), 0, 255)
    img = np.concatenate([rgb, (alpha * 255)[:, None]], axis=1).astype(np.uint8)[None, :, :]
    OUT.parent.mkdir(parents=True, exist_ok=True)
    Image.fromarray(img, "RGBA").save(OUT)
    print("->", OUT)


if __name__ == "__main__":
    main()
