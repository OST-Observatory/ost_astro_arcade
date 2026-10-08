"""Planet textures for the solar-system explorer: Solar System Scope maps (CC BY 4.0), taken
from their copies on Wikimedia Commons. Every file is checked to be a real image (servers
sometimes answer with an HTML page) and scaled to at most MAX_W pixels wide.
Output: godot/assets/solar/textures/<body>.jpg and textures.json (credit per file)

    uv run solar/fetch_textures.py
"""

import io
import json
import time
import urllib.error
import urllib.parse
import urllib.request
from pathlib import Path

from PIL import Image

TOOLS = Path(__file__).resolve().parents[1]
REPO = TOOLS.parent
CACHE = TOOLS / ".cache/solar/textures"
OUT = REPO / "godot/assets/solar/textures"
MAX_W = 2048
CREDIT = "Solar System Scope (solarsystemscope.com), CC BY 4.0"
# body -> file name on Wikimedia Commons
FILES = {
    "sun": "Solarsystemscope_texture_2k_sun.jpg",
    "mercury": "Solarsystemscope_texture_2k_mercury.jpg",
    "venus": "Solarsystemscope_texture_2k_venus_atmosphere.jpg",
    "earth": "Solarsystemscope_texture_2k_earth_daymap.jpg",
    "moon": "Solarsystemscope_texture_2k_moon.jpg",
    "mars": "Solarsystemscope_texture_2k_mars.jpg",
    "jupiter": "Solarsystemscope_texture_2k_jupiter.jpg",
    "saturn": "Solarsystemscope_texture_2k_saturn.jpg",
    "uranus": "Solarsystemscope_texture_2k_uranus.jpg",
    "neptune": "Solarsystemscope_texture_2k_neptune.jpg",
}


def fetch(name: str) -> bytes:
    path = CACHE / name
    if path.exists():
        return path.read_bytes()
    headers = {"User-Agent": "ost-space-lab/0.1 (outreach kiosk, Uni Potsdam)"}
    # Resolve the direct file URL via the API (Special:FilePath sometimes loops on redirects).
    api = ("https://commons.wikimedia.org/w/api.php?action=query&prop=imageinfo&iiprop=url&format=json&titles="
           + urllib.parse.quote("File:" + name))
    with urllib.request.urlopen(urllib.request.Request(api, headers=headers), timeout=60) as r:
        pages = json.load(r)["query"]["pages"]
    url = next(iter(pages.values()))["imageinfo"][0]["url"]
    req = urllib.request.Request(url, headers=headers)
    for attempt in range(5):   # Wikimedia rate-limits bursts (HTTP 429): wait and retry
        try:
            with urllib.request.urlopen(req, timeout=120) as r:
                data = r.read()
                ctype = r.headers.get("Content-Type", "")
            break
        except urllib.error.HTTPError as e:
            if e.code != 429 or attempt == 4:
                raise
            time.sleep(20 * (attempt + 1))
    time.sleep(3)
    if not ctype.startswith("image/") or not (data[:3] == b"\xff\xd8\xff" or data[:8] == b"\x89PNG\r\n\x1a\n"):
        raise ValueError(f"{name}: not an image ({ctype})")
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_bytes(data)
    return data


def main() -> None:
    OUT.mkdir(parents=True, exist_ok=True)
    manifest = {}
    for body, name in FILES.items():
        try:
            im = Image.open(io.BytesIO(fetch(name))).convert("RGB")
        except Exception as e:  # keep going: the game falls back to plain colours
            print("  skipped", body, e)
            continue
        if im.width > MAX_W:
            im = im.resize((MAX_W, MAX_W // 2), Image.Resampling.LANCZOS)
        im.save(OUT / f"{body}.jpg", "JPEG", quality=88, optimize=True)
        manifest[body] = {"file": f"res://assets/solar/textures/{body}.jpg", "source": name, "credit": CREDIT}
        print(body, im.size)
    (OUT / "textures.json").write_text(json.dumps(manifest, indent=1))


if __name__ == "__main__":
    main()
