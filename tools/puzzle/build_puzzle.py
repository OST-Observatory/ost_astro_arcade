"""Copies the OST puzzle images (with de/en/es name and description) into the Godot app.

Images are scaled to at most 2400 px (the old PNGs were up to 84 MB) and saved as JPEG.
Output: godot/assets/puzzle/images/<id>.jpg (+ _thumb.jpg), godot/assets/data/puzzle/images.json

    uv run puzzle/build_puzzle.py
"""

import json
from pathlib import Path

from PIL import Image

TOOLS = Path(__file__).resolve().parents[1]
REPO = TOOLS.parent
SRC = Path("/home/schedar/projects/astro_mini_games/astro_mini_games/apps/astro_puzzle/images")
OUT_IMG = REPO / "godot/assets/puzzle/images"
OUT_JSON = REPO / "godot/assets/data/puzzle/images.json"
MAX_PX = 2400
THUMB_PX = 560


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
        im = Image.open(img_path).convert("RGB")
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
    OUT_JSON.parent.mkdir(parents=True, exist_ok=True)
    OUT_JSON.write_text(json.dumps({"images": out}, ensure_ascii=False, indent=1))
    print(len(out), "puzzle images")


if __name__ == "__main__":
    main()
