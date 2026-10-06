"""Builds the quiz data for the Godot app.

Sources (owned by this repo): tools/quiz/source/questions.<lang>.yaml (copied from the old
astro_mini_games quiz) and tools/quiz/explanations.yaml. Images are taken from the old
project, scaled to at most 1400 px and saved as JPEG (GIFs: first frame for now).

Output: godot/assets/data/quiz/questions.json, godot/assets/quiz/images/*.jpg

    uv run quiz/build_quiz.py [--images /path/to/old/quiz/data/images]
"""

import argparse
import json
from pathlib import Path

import yaml
from PIL import Image

TOOLS = Path(__file__).resolve().parents[1]
REPO = TOOLS.parent
SRC = TOOLS / "quiz/source"
OUT_JSON = REPO / "godot/assets/data/quiz/questions.json"
OUT_IMG = REPO / "godot/assets/quiz/images"
OLD_IMAGES = Path("/home/schedar/projects/astro_mini_games/astro_mini_games/apps/quiz/data/images")
LANGS = ("de", "en", "es")
MAX_PX = 1400
DIFFICULTY = {"laie": 1, "amateur": 2, "astronom": 3, 1: 1, 2: 2, 3: 3}


def convert_image(src: Path, dst: Path) -> bool:
    if not src.exists():
        print("  missing image:", src.name)
        return False
    if src.suffix.lower() == ".svg":
        alt = src.with_name(src.name + ".png")
        if not alt.exists():
            print("  svg without png fallback:", src.name)
            return False
        src = alt
    im = Image.open(src)
    im.seek(0)
    im = im.convert("RGB")
    im.thumbnail((MAX_PX, MAX_PX), Image.Resampling.LANCZOS)
    im.save(dst, "JPEG", quality=86, optimize=True)
    return True


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--images", type=Path, default=OLD_IMAGES)
    args = ap.parse_args()

    data = {l: yaml.safe_load((SRC / f"questions.{l}.yaml").read_text()) for l in LANGS}
    expl = yaml.safe_load((TOOLS / "quiz/explanations.yaml").read_text())
    by_lang = {l: {q["id"]: q for q in data[l]["questions"]} for l in LANGS}
    categories = {c["id"]: {l: next(x["name"] for x in data[l]["categories"] if x["id"] == c["id"]) for l in LANGS}
                  for c in data["de"]["categories"]}

    OUT_IMG.mkdir(parents=True, exist_ok=True)
    out = []
    for q in data["de"]["questions"]:
        qid = q["id"]
        entry = {
            "id": qid,
            "category": q["category"],
            "difficulty": DIFFICULTY[q["difficulty"]],
            "correct": q["correct"],
            "text": {l: by_lang[l][qid]["text"] for l in LANGS},
            "answers": {l: by_lang[l][qid]["answers"] for l in LANGS},
            "explain": expl.get(qid, {}),
        }
        for l in LANGS:
            assert by_lang[l][qid]["correct"] == q["correct"], f"{qid}: correct index differs in {l}"
            assert len(by_lang[l][qid]["answers"]) == 4, f"{qid}: needs 4 answers in {l}"
        if q.get("image"):
            name = Path(q["image"]).stem + ".jpg"
            if convert_image(args.images / Path(q["image"]).name, OUT_IMG / name):
                entry["image"] = f"res://assets/quiz/images/{name}"
                entry["credit"] = q.get("image_credit", "")
        out.append(entry)

    OUT_JSON.parent.mkdir(parents=True, exist_ok=True)
    OUT_JSON.write_text(json.dumps({"categories": categories, "questions": out}, ensure_ascii=False, indent=1))
    missing = [e["id"] for e in out if set(e["explain"]) != set(LANGS)]
    print(f"{len(out)} questions, {sum('image' in e for e in out)} images; missing explanations: {missing}")


if __name__ == "__main__":
    main()
