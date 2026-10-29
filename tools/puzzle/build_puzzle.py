"""Copies the OST puzzle images (with de/en/es name and description) into the Godot app:
the images of the old puzzle app, and those listed in ost_gallery.json, which are downloaded
from the OST gallery (cached in tools/.cache/puzzle).

Images are scaled to at most 2400 px (the old PNGs were up to 84 MB) and saved as JPEG.
Output: godot/assets/puzzle/images/<id>.jpg (+ _thumb.jpg), godot/assets/data/puzzle/images.json

    uv run puzzle/build_puzzle.py
"""

import json
import urllib.request
from pathlib import Path

from PIL import Image, ImageOps

TOOLS = Path(__file__).resolve().parents[1]
REPO = TOOLS.parent
SRC = Path("/home/schedar/projects/astro_mini_games/astro_mini_games/apps/astro_puzzle/images")
OUT_IMG = REPO / "godot/assets/puzzle/images"
OUT_JSON = REPO / "godot/assets/data/puzzle/images.json"
MAX_PX = 2400
THUMB_PX = 560
GALLERY = Path(__file__).with_name("ost_gallery.json")
CACHE = TOOLS / ".cache/puzzle"


def add_image(im: Image.Image, stem: str, meta: dict, out: list) -> None:
    w, h = im.size
    im.thumbnail((MAX_PX, MAX_PX), Image.Resampling.LANCZOS)
    im.save(OUT_IMG / f"{stem}.jpg", "JPEG", quality=90, optimize=True)
    thumb = im.copy()
    thumb.thumbnail((THUMB_PX, THUMB_PX), Image.Resampling.LANCZOS)
    thumb.save(OUT_IMG / f"{stem}_thumb.jpg", "JPEG", quality=85)
    out.append({
        "id": stem,
        "image": f"res://assets/puzzle/images/{stem}.jpg",
        "thumb": f"res://assets/puzzle/images/{stem}_thumb.jpg",
        "size": [im.size[0], im.size[1]],
        "name": meta.get("name", {}),
        "description": meta.get("description", {}),
    })
    print(f"{stem}: {w}x{h} -> {im.size[0]}x{im.size[1]}")


def gallery_image(entry: dict) -> Image.Image:
    CACHE.mkdir(parents=True, exist_ok=True)
    path = CACHE / f"{entry['id']}{Path(entry['url']).suffix}"
    if not path.exists():
        with urllib.request.urlopen(entry["url"], timeout=120) as r:
            if not r.headers.get("Content-Type", "").startswith("image/"):
                raise RuntimeError(f"not an image: {entry['url']}")
            path.write_bytes(r.read())
    im = ImageOps.exif_transpose(Image.open(path)).convert("RGB")
    if entry.get("rotate"):
        im = im.rotate(-entry["rotate"], expand=True)   # clockwise
    if entry.get("crop"):
        im = im.crop(tuple(entry["crop"]))
    return im


def main() -> None:
    Image.MAX_IMAGE_PIXELS = None  # the original astro images are huge
    OUT_IMG.mkdir(parents=True, exist_ok=True)
    out = []
    for meta_path in sorted(SRC.glob("*.json")):
        stem = meta_path.stem
        img_path = next((p for p in (SRC / f"{stem}.jpg", SRC / f"{stem}.png") if p.exists()), None)
        if img_path is None:
            print("  no image for", stem)
            continue
        meta = json.loads(meta_path.read_text())
        add_image(Image.open(img_path).convert("RGB"), stem, meta, out)
    for entry in json.loads(GALLERY.read_text())["images"]:
        add_image(gallery_image(entry), entry["id"], entry, out)
    OUT_JSON.parent.mkdir(parents=True, exist_ok=True)
    OUT_JSON.write_text(json.dumps({"images": out}, ensure_ascii=False, indent=1))
    print(len(out), "puzzle images")


if __name__ == "__main__":
    main()
