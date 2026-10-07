"""Downloads the target images for the galaxy builder (ESA/Hubble, ESA/Webb; CC BY 4.0)
and scales them to at most 1600 px. The Antennae use the OST's own image (puzzle set).
Output: godot/assets/galaxy/images/<id>.jpg

    uv run galaxy/fetch_images.py
"""

import io
import urllib.request
from pathlib import Path

from PIL import Image

REPO = Path(__file__).resolve().parents[2]
OUT = REPO / "godot/assets/galaxy/images"
CACHE = REPO / "tools/.cache/galaxy"
MAX_PX = 1600
IMAGES = {
    "mice": "https://esahubble.org/media/archives/images/large/heic0206h.jpg",
    "whirlpool": "https://esahubble.org/media/archives/images/large/heic0506a.jpg",
}


def main() -> None:
    Image.MAX_IMAGE_PIXELS = None
    OUT.mkdir(parents=True, exist_ok=True)
    CACHE.mkdir(parents=True, exist_ok=True)
    for name, url in IMAGES.items():
        raw = CACHE / url.rsplit("/", 1)[1]
        if not raw.exists():
            print("downloading", url)
            req = urllib.request.Request(url, headers={"User-Agent": "ost-astro-arcade/0.1"})
            raw.write_bytes(urllib.request.urlopen(req, timeout=120).read())
        im = Image.open(io.BytesIO(raw.read_bytes())).convert("RGB")
        w, h = im.size
        im.thumbnail((MAX_PX, MAX_PX), Image.Resampling.LANCZOS)
        im.save(OUT / f"{name}.jpg", "JPEG", quality=88, optimize=True)
        print(f"{name}: {w}x{h} -> {im.size[0]}x{im.size[1]}")


if __name__ == "__main__":
    main()
