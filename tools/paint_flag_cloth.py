"""Paints the flag cloth textures of Last Hook.

    python tools/paint_flag_cloth.py

Writes game/assets/sprites/flags/cloth_<design>.png, 512 px masks: R the
fabric's light (weave and soft folds), G the gold trim, stitched seam and
emblem, B the deeper accent, A the cloth (fringes cut out). The game paints
R in the flag's colour, G in gold and B in a deeper shade of that colour, so
one mask serves every colour. Drawn at 4x and reduced; fixed seeds.
"""
import math
import os
import random

from PIL import Image, ImageDraw

ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "game", "assets", "sprites")
SS = 4  # supersampling

# --- flag cloth ----------------------------------------------------------------------

CLOTH = 512


def cloth_mask(design):
    """R: fabric light (weave, folds), G: gold trim and emblem, B: deep accent,
    A: the cloth. UV (0,0) is the corner at the pole or the cord."""
    size = CLOTH * SS
    rng = random.Random(f"cloth-{design}")
    r = Image.new("L", (size, size), 0)
    g = Image.new("L", (size, size), 0)
    b = Image.new("L", (size, size), 0)
    a = Image.new("L", (size, size), 255)
    dr, dg, db, da = (ImageDraw.Draw(img) for img in (r, g, b, a))
    # Fabric: light base with soft vertical folds and a fine weave.
    for x in range(0, size, SS):
        fold = 0.5 + 0.5 * math.sin(x / size * math.tau * 2.3 + 0.7)
        value = int(205 + 38 * fold)
        dr.line([(x, 0), (x, size)], fill=value, width=SS)
    weave = Image.effect_noise((size // 8, size // 8), 40).resize((size, size), Image.BILINEAR)
    r = Image.blend(r, Image.merge("L", (weave,)).point(lambda v: 160 + v // 3), 0.18)
    dr = ImageDraw.Draw(r)
    for y in range(0, size, 6 * SS):
        dr.line([(0, y), (size, y)], fill=200, width=1)
    border = int(size * 0.055)
    stitch = int(size * 0.085)
    # Trim along the edges, stitched seam inside it.
    dg.rectangle([0, 0, size, border], fill=255)
    dg.rectangle([0, size - border, size, size], fill=255)
    dg.rectangle([size - border, 0, size, size], fill=255)
    for x in range(stitch, size - stitch, 10 * SS):
        dg.line([(x, stitch), (x + 6 * SS, stitch)], fill=200, width=SS * 2)
        dg.line([(x, size - stitch), (x + 6 * SS, size - stitch)], fill=200, width=SS * 2)
    cx, cy = size * 0.52, size * 0.5
    if design == "peak":
        db.polygon([(cx - size * 0.3, cy + size * 0.22), (cx - size * 0.05, cy - size * 0.24), (cx + size * 0.07, cy - size * 0.04),
                    (cx + size * 0.15, cy - size * 0.16), (cx + size * 0.32, cy + size * 0.22)], fill=255)
        dg.polygon([(cx - size * 0.05, cy - size * 0.24), (cx - size * 0.12, cy - size * 0.11), (cx - size * 0.06, cy - size * 0.13),
                    (cx, cy - size * 0.09), (cx + size * 0.04, cy - size * 0.1)], fill=255)
        dg.ellipse([cx + size * 0.12, cy - size * 0.36, cx + size * 0.24, cy - size * 0.24], fill=255)
    elif design == "sun":
        for i in range(12):
            ang = math.tau * i / 12
            p1 = (cx + math.cos(ang - 0.12) * size * 0.16, cy + math.sin(ang - 0.12) * size * 0.16)
            p2 = (cx + math.cos(ang) * size * 0.31, cy + math.sin(ang) * size * 0.31)
            p3 = (cx + math.cos(ang + 0.12) * size * 0.16, cy + math.sin(ang + 0.12) * size * 0.16)
            dg.polygon([p1, p2, p3], fill=255)
        dg.ellipse([cx - size * 0.15, cy - size * 0.15, cx + size * 0.15, cy + size * 0.15], fill=255)
        db.ellipse([cx - size * 0.09, cy - size * 0.09, cx + size * 0.09, cy + size * 0.09], fill=255)
    elif design == "stripes":
        for y0 in (0.3, 0.62):
            db.rectangle([0, size * y0, size, size * (y0 + 0.09)], fill=255)
        dg.rectangle([0, size * 0.465, size, size * 0.52], fill=255)
    elif design == "chevron":
        for k in range(2):
            off = k * size * 0.17
            db.polygon([(size * 0.12 + off, size * 0.18), (size * 0.24 + off, size * 0.18), (size * 0.52 + off, cy),
                        (size * 0.24 + off, size * 0.82), (size * 0.12 + off, size * 0.82), (size * 0.4 + off, cy)], fill=255)
        dg.ellipse([size * 0.72, cy - size * 0.07, size * 0.86, cy + size * 0.07], fill=255)
    elif design == "hook":
        # The expedition's sign: a climbing hook over two crossed ropes.
        db.line([(size * 0.2, size * 0.78), (size * 0.84, size * 0.22)], fill=255, width=int(size * 0.05))
        db.line([(size * 0.2, size * 0.22), (size * 0.84, size * 0.78)], fill=255, width=int(size * 0.05))
        dg.arc([cx - size * 0.16, cy - size * 0.05, cx + size * 0.16, cy + size * 0.3], 0, 200, fill=255, width=int(size * 0.06))
        dg.line([(cx + size * 0.16, cy + size * 0.12), (cx + size * 0.16, cy - size * 0.3)], fill=255, width=int(size * 0.06))
        dg.ellipse([cx + size * 0.1, cy - size * 0.38, cx + size * 0.22, cy - size * 0.26], outline=255, width=int(size * 0.03))
    elif design == "plain":
        pass
    # Fringe along the free edge: tassels cut into the alpha.
    if design in ("sun", "hook"):
        for y in range(0, size, 9 * SS):
            da.rectangle([size - int(size * 0.035), y + 5 * SS, size, y + 9 * SS], fill=0)
    image = Image.merge("RGBA", (r, g, b, a)).resize((CLOTH, CLOTH), Image.LANCZOS)
    return image


DESIGNS = ["peak", "sun", "stripes", "chevron", "hook", "plain"]


def main():
    flags = os.path.join(ROOT, "flags")
    os.makedirs(flags, exist_ok=True)
    for design in DESIGNS:
        cloth_mask(design).save(os.path.join(flags, f"cloth_{design}.png"))
        print("cloth", design)


if __name__ == "__main__":
    main()
