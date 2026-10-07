"""Prepares the real OST time series of comet 67P/Churyumov-Gerasimenko (2015-08-13, STF8300M)
for the bonus round: splits the GIF from the OST gallery into frames, turns them into white
stars on black with a common stretch, and finds the comet in every frame (difference to the
median of all frames, smoothed). License of the source: CC BY-NC-SA 3.0 (OST, Uni Potsdam).
Output: godot/assets/comet/67p_<n>.jpg, godot/assets/data/comet/67p.json

    uv run comet/build_67p.py
"""

import json
import urllib.request
from pathlib import Path

import numpy as np
from PIL import Image, ImageSequence

TOOLS = Path(__file__).resolve().parents[1]
REPO = TOOLS.parent
URL = "https://polaris.astro.physik.uni-potsdam.de/gallery/media/original/2015.08.13/67p.gif"
CACHE = TOOLS / ".cache/67p/67p.gif"
OUT_IMG = REPO / "godot/assets/comet"
OUT_JSON = REPO / "godot/assets/data/comet/67p.json"
BOX = 9


def smooth(a: np.ndarray, k: int) -> np.ndarray:
    c = np.cumsum(np.cumsum(np.pad(a, ((1, 0), (1, 0))), 0), 1)
    out = (c[k:, k:] - c[:-k, k:] - c[k:, :-k] + c[:-k, :-k]) / (k * k)
    return np.pad(out, ((k // 2, k - 1 - k // 2), (k // 2, k - 1 - k // 2)))


def main() -> None:
    if not CACHE.exists():
        CACHE.parent.mkdir(parents=True, exist_ok=True)
        CACHE.write_bytes(urllib.request.urlopen(URL, timeout=120).read())
    gif = Image.open(CACHE)
    frames = [255.0 - np.asarray(f.convert("L"), dtype=float) for f in ImageSequence.Iterator(gif)]
    med = np.median(np.stack(frames), 0)
    OUT_IMG.mkdir(parents=True, exist_ok=True)
    out = []
    for i, f in enumerate(frames):
        # Comet: strongest smoothed excess over the median (the stars cancel out).
        diff = smooth(f - med, BOX)
        y, x = np.unravel_index(np.argmax(diff), diff.shape)
        # Common look: background to dark grey, stars bright, noise softened a bit.
        sm = smooth(f, 3)
        lo, hi = np.percentile(sm, 50), np.percentile(sm, 99.95)
        img = np.clip((sm - lo) / (hi - lo), 0, 1) ** 0.6
        Image.fromarray((img * 255).astype(np.uint8)).save(OUT_IMG / f"67p_{i}.jpg", quality=88)
        out.append({"image": f"res://assets/comet/67p_{i}.jpg", "comet": [int(x), int(y)]})
        print(i, x, y)
    OUT_JSON.parent.mkdir(parents=True, exist_ok=True)
    OUT_JSON.write_text(json.dumps({"size": list(gif.size), "date": "2015-08-13", "frames": out}, indent=1))


if __name__ == "__main__":
    main()
