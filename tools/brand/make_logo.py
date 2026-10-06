"""Builds the in-game logo textures from the OST T-shirt artwork.

Source: white-on-black PNG (7087x7087) from the OST cloud. Output: white strokes on a
transparent background (alpha = luminance), so the hub can tint it and make it glow.

    uv run brand/make_logo.py [source.png]
"""

import sys
from pathlib import Path

from PIL import Image

REPO = Path(__file__).resolve().parents[2]
DEFAULT_SRC = Path.home() / "OST_cloud/OST/Outreach/tshirts_2025/back_sketch1_inverted.png"
OUT_DIR = REPO / "godot/assets/brand"
SIZES = {"ost_logo_2048.png": 2048, "ost_logo_512.png": 512}


def white_on_alpha(src: Image.Image) -> Image.Image:
    lum = src.convert("L")
    out = Image.new("RGBA", src.size, (255, 255, 255, 0))
    out.putalpha(lum)
    return out


def main() -> None:
    src_path = Path(sys.argv[1]) if len(sys.argv) > 1 else DEFAULT_SRC
    src = Image.open(src_path)
    if src.mode == "RGBA":
        # Composite onto black first, in case parts of the artwork are transparent.
        bg = Image.new("RGBA", src.size, (0, 0, 0, 255))
        src = Image.alpha_composite(bg, src)
    logo = white_on_alpha(src)
    for name, size in SIZES.items():
        logo.resize((size, size), Image.Resampling.LANCZOS).save(OUT_DIR / name, optimize=True)
        print("wrote", OUT_DIR / name)


if __name__ == "__main__":
    main()
