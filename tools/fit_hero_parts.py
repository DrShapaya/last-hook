"""Fit generated hero parts onto their rig canvases (CHARACTER_PLAN.md, stage 8 tool).

Image generators do not hit exact pixels. This takes each raw part from
game/assets/hero/pioneer/raw/<id>.png, trims it to its visible pixels and
places it on the canvas that game/assets/hero/skeleton.json gives the part, so
the painted joints land on the rig's joints:

- limbs (sleeve, pant_leg) are painted straight and hanging down: they are
  scaled to the canvas height between the margins and centred horizontally;
- gloves hang from the wrist: scaled to the canvas, wrist at the top;
- upright parts (head, torso, boot, ...) are scaled into the canvas box.

The result goes to game/assets/hero/pioneer/<id>.png. A report lists how much
each part had to be squeezed or stretched against the template's width, so a
part drawn too thick or too thin is caught before it reaches the rig.

Run: python tools/fit_hero_parts.py [part ...]
"""
import json
import os
import sys

from PIL import Image

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
HERO = os.path.join(ROOT, "game", "assets", "hero")
RAW = os.path.join(HERO, "pioneer", "raw")
OUT = os.path.join(HERO, "pioneer")
EYES_CANVAS = (160, 240)  # Matches the eyes quad aspect in hero_rig.gd.
MARGIN = 0.02  # Transparent border kept around every part (hero units).
# Parts that are the top layer paint no hidden continuation: their visible
# outline is the canvas box minus the overlap as well.
NO_OVERLAP = {"head"}
WIDTH_STRETCH = 1.35  # Most a limb may be widened or narrowed to its template width.
# Parts that fill their box width as well (within WIDTH_STRETCH): the head's
# front face carries the eyes, so it must reach the template's face edge.
FILL_WIDTH = {"head"}


def visible(image):
    alpha = image.getchannel("A").point(lambda v: 255 if v > 12 else 0)
    return image.crop(alpha.getbbox())


def place(part_image, canvas, box, align_top, width=None):
    """Scale to fit box (x0, y0, x1, y1) keeping the aspect; centre it.

    width: a limb's visible thickness from the template. Generators paint
    sleeves too thin or too thick; the length stays bound to the joints and
    only the thickness is brought to the template, within WIDTH_STRETCH.
    """
    x0, y0, x1, y1 = box
    k = min((x1 - x0) / part_image.width, (y1 - y0) / part_image.height)
    kx = k
    if width:
        kx = min(max(width / part_image.width, k / WIDTH_STRETCH), k * WIDTH_STRETCH)
    scaled = part_image.resize((max(1, round(part_image.width * kx)), max(1, round(part_image.height * k))), Image.LANCZOS)
    out = Image.new("RGBA", canvas, (0, 0, 0, 0))
    x = round((x0 + x1 - scaled.width) / 2)
    y = y0 if align_top else round((y0 + y1 - scaled.height) / 2)
    out.alpha_composite(scaled, (x, y))
    return out, scaled.size


def main(only):
    with open(os.path.join(HERO, "skeleton.json"), encoding="utf-8") as f:
        data = json.load(f)
    master = data["master_px"]
    margin = round(MARGIN * master)
    parts = {p["id"]: p for p in data["parts"]}
    names = only or sorted(n[:-4] for n in os.listdir(RAW) if n.endswith(".png"))
    for name in names:
        raw = os.path.join(RAW, name + ".png")
        if not os.path.exists(raw):
            print(f"{name}: no raw picture")
            continue
        image = visible(Image.open(raw).convert("RGBA"))
        if name == "eyes":
            fitted, size = place(image, EYES_CANVAS, (4, 4, EYES_CANVAS[0] - 4, EYES_CANVAS[1] - 4), False)
            fitted.save(os.path.join(OUT, "eyes.png"))
            print(f"eyes: {image.size} -> {size} on {EYES_CANVAS}")
            continue
        part = parts.get(name)
        if part is None:
            print(f"{name}: not in skeleton.json")
            continue
        w, h = part["canvas_px"]
        inset = margin + (part["overlap_px"] if name in NO_OVERLAP else 0)
        box = (inset, inset, w - inset, h - inset)
        limb = "width" in part or part.get("painted", "").startswith("straight")
        bone_width = part["width"] * master if "width" in part else (2 * part["radius"] * master if "radius" in part else None)
        if name in FILL_WIDTH:
            bone_width = box[2] - box[0]
        fitted, size = place(image, (w, h), box, align_top=limb or name == "glove", width=bone_width)
        fitted.save(os.path.join(OUT, name + ".png"))
        expected_w = bone_width or box[2] - box[0]
        what = "target width" if bone_width else "template box"
        print(f"{name}: {image.size} -> {size} on {w}x{h}; width {size[0] / expected_w:.0%} of the {what}")


if __name__ == "__main__":
    main(sys.argv[1:])
