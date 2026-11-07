"""Placeholder art for the hero prototype slice (CHARACTER_PLAN.md, stage 2).

Paints whole parts (not cuts from the sprite) in the paint frames of
game/assets/hero/skeleton.json: head, eyes, torso, sleeve, glove and a soft
joint shadow. They only exist to test the rig technique (bending, seams, joint
shadows, layer order); real art goes to game/assets/hero/pioneer/ under the
same file names and canvas sizes and replaces them without code changes.

Run: python tools/hero_placeholders.py
"""
import json
import math
import os

from PIL import Image, ImageDraw, ImageFilter

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
HERO = os.path.join(ROOT, "game", "assets", "hero")
OUT = os.path.join(HERO, "placeholder")
SS = 3  # Supersampling for smooth edges.
OUTLINE = (52, 36, 24, 255)
LINE = 6  # Outline width at master scale (skeleton.json rules).


def lerp_color(a, b, t):
    return tuple(int(a[i] + (b[i] - a[i]) * t) for i in range(len(a)))


def shaded(mask, light, dark, top_left=True):
    """Fill a mask with soft top-left light: a gradient plus a blurred rim."""
    w, h = mask.size
    grad = Image.new("RGBA", (w, h))
    px = grad.load()
    for y in range(h):
        for x in range(w):
            t = (x / w * 0.55 + y / h * 0.45) if top_left else y / h
            px[x, y] = lerp_color(light, dark, min(1, max(0, t)))
    # Darker edge toward the bottom right: inner shadow from a shifted mask.
    shift = Image.new("L", (w, h), 0)
    shift.paste(mask, (-int(w * 0.04), -int(h * 0.04)))
    rim = Image.eval(Image.composite(Image.new("L", (w, h), 0), mask, shift), lambda v: v)
    rim = rim.filter(ImageFilter.GaussianBlur(max(2, w // 30)))
    shadow = Image.new("RGBA", (w, h), dark[:3] + (0,))
    shadow.putalpha(Image.eval(rim, lambda v: int(v * 0.55)))
    grad.alpha_composite(shadow)
    out = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    out.paste(grad, (0, 0), mask)
    return out


def outlined(mask):
    w = LINE * SS
    grown = mask.filter(ImageFilter.MaxFilter(w * 2 + 1 if w * 2 + 1 <= 31 else 31))
    line = Image.new("RGBA", mask.size, OUTLINE)
    out = Image.new("RGBA", mask.size, (0, 0, 0, 0))
    out.paste(line, (0, 0), grown)
    return out


def finish(layers, size, name):
    img = Image.new("RGBA", layers[0].size, (0, 0, 0, 0))
    for layer in layers:
        img.alpha_composite(layer)
    img = img.resize(size, Image.LANCZOS)
    img.save(os.path.join(OUT, name + ".png"))


def frame(parts, pid):
    p = next(p for p in parts if p["id"] == pid)
    w, h = p["canvas_px"]
    return p, (w, h), (w * SS, h * SS)


def paint_sleeve(parts):
    p, size, (W, H) = frame(parts, "sleeve")
    j = {k: (v[0] * SS, v[1] * SS) for k, v in p["joints_px"].items()}
    sx, sy = j["shoulder_near"]
    ex, ey = j["elbow_near"]
    hx, hy = j["hand_near"]
    half = 0.075 / 2 * 1024 * SS
    mask = Image.new("L", (W, H), 0)
    d = ImageDraw.Draw(mask)
    cap = half * 1.25  # Round shoulder cap painted whole (goes under the torso).
    d.ellipse([sx - cap, sy - cap, sx + cap, sy + cap], fill=255)
    d.polygon([(sx - half * 1.1, sy), (sx + half * 1.1, sy), (ex + half, ey), (hx + half * .85, hy + half * .3),
               (hx - half * .85, hy + half * .3), (ex - half, ey)], fill=255)
    d.ellipse([ex - half, ey - half, ex + half, ey + half], fill=255)
    body = shaded(mask, (150, 190, 95, 255), (58, 92, 44, 255))
    detail = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    dd = ImageDraw.Draw(detail)
    # Cuff band and two soft folds around the elbow.
    dd.rectangle([hx - half * .9, hy - half * .55, hx + half * .9, hy + half * .3], fill=(70, 100, 50, 255))
    dd.rectangle([hx - half * .9, hy - half * .62, hx + half * .9, hy - half * .5], fill=(40, 60, 32, 255))
    for k in (-1, 1):
        dd.arc([ex - half * .8, ey + k * half * .5 - half * .6, ex + half * .8, ey + k * half * .5 + half * .6],
               200, 340, fill=(55, 85, 40, 200), width=3 * SS)
    # Leather shoulder patch.
    dd.ellipse([sx - half * .7, sy - half * .2, sx + half * .7, sy + half * 1.0], fill=(120, 80, 45, 230))
    detail.putalpha(Image.composite(detail.getchannel("A"), Image.new("L", (W, H), 0), mask))
    finish([outlined(mask), body, detail], size, "sleeve")


def paint_glove(parts):
    p, size, (W, H) = frame(parts, "glove")
    hx, hy = (v * SS for v in p["joints_px"]["hand_near"])
    r = 0.045 * 1024 * SS
    cx, cy = W / 2, hy + r * .8
    mask = Image.new("L", (W, H), 0)
    d = ImageDraw.Draw(mask)
    d.rectangle([cx - r * .55, hy - r * .55, cx + r * .55, cy], fill=255)  # Wrist under the cuff.
    d.ellipse([cx - r, cy - r, cx + r, cy + r], fill=255)
    d.ellipse([cx + r * .35, cy - r * .9, cx + r * 1.05, cy - r * .1], fill=255)  # Thumb.
    body = shaded(mask, (120, 95, 80, 255), (45, 34, 28, 255))
    detail = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    dd = ImageDraw.Draw(detail)
    for k in range(3):
        y = cy + r * (.15 + k * .22)
        dd.arc([cx - r * .9, y - r * .3, cx + r * .2, y + r * .3], 20, 160, fill=(35, 26, 22, 220), width=2 * SS)
    dd.rectangle([cx - r * .6, hy - r * .1, cx + r * .6, hy + r * .25], fill=(150, 95, 50, 255))
    detail.putalpha(Image.composite(detail.getchannel("A"), Image.new("L", (W, H), 0), mask))
    finish([outlined(mask), body, detail], size, "glove")


def paint_torso(parts):
    p, size, (W, H) = frame(parts, "torso")
    pad = (0.04 + 0.02) * 1024 * SS
    mask = Image.new("L", (W, H), 0)
    d = ImageDraw.Draw(mask)
    d.rounded_rectangle([pad * .7, pad * .55, W - pad * .7, H - pad * .25], radius=W * .2, fill=255)
    # Neck painted whole above the collar: goes under the head.
    d.rounded_rectangle([W * .38, 0, W * .66, pad * 1.2], radius=W * .05, fill=255)
    body = shaded(mask, (150, 190, 95, 255), (52, 84, 40, 255))
    detail = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    dd = ImageDraw.Draw(detail)
    dd.rounded_rectangle([W * .38, 0, W * .66, pad * 1.2], radius=W * .05, fill=(205, 150, 45, 255))  # Neck.
    dd.rounded_rectangle([W * .25, pad * .7, W * .78, pad * 1.6], radius=W * .1, fill=(110, 150, 70, 255))  # Collar.
    dd.line([W * .62, pad * 1.4, W * .6, H - pad * .4], fill=(60, 50, 40, 255), width=3 * SS)  # Zipper.
    dd.rectangle([pad * .7, H - pad * 1.1, W - pad * .7, H - pad * .7], fill=(110, 70, 40, 255))  # Belt strap.
    dd.rectangle([W * .52, H - pad * 1.15, W * .62, H - pad * .65], outline=(200, 200, 190, 255), width=2 * SS)
    dd.line([W * .2, pad * 1.4, W * .45, H - pad * 1.2], fill=(120, 75, 40, 255), width=6 * SS)  # Pack strap.
    detail.putalpha(Image.composite(detail.getchannel("A"), Image.new("L", (W, H), 0), mask))
    finish([outlined(mask), body, detail], size, "torso")


def paint_head(parts):
    p, size, (W, H) = frame(parts, "head")
    pad = (0.035 + 0.02) * 1024 * SS
    mask = Image.new("L", (W, H), 0)
    d = ImageDraw.Draw(mask)
    d.rounded_rectangle([pad, pad, W - pad, H - pad], radius=W * .12, fill=255)
    body = shaded(mask, (255, 205, 80, 255), (205, 120, 20, 255))
    detail = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    dd = ImageDraw.Draw(detail)
    # Top face of the cube catches the light; a side strap shows the turn.
    dd.rounded_rectangle([pad * 1.4, pad * 1.1, W - pad * 1.4, pad * 2.6], radius=W * .06, fill=(255, 225, 120, 150))
    dd.rounded_rectangle([pad * 1.3, H * .45, pad * 2.6, H * .72], radius=W * .02, fill=(110, 70, 40, 255))
    detail.putalpha(Image.composite(detail.getchannel("A"), Image.new("L", (W, H), 0), mask))
    finish([outlined(mask), body, detail], size, "head")


def paint_eyes():
    W, H = 160 * SS, 240 * SS
    img = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    for x in (W * .22, W * .7):
        d.rounded_rectangle([x - W * .14, H * .05, x + W * .14, H * .95], radius=W * .12, fill=(28, 22, 22, 255))
        d.ellipse([x - W * .06, H * .2, x + W * .06, H * .36], fill=(250, 250, 245, 255))
    img.resize((160, 240), Image.LANCZOS).save(os.path.join(OUT, "eyes.png"))


def paint_shadow():
    size = 256
    img = Image.new("L", (size, size), 0)
    ImageDraw.Draw(img).ellipse([40, 40, size - 40, size - 40], fill=255)
    img = img.filter(ImageFilter.GaussianBlur(30))
    shadow = Image.new("RGBA", (size, size), (25, 18, 10, 0))
    shadow.putalpha(Image.eval(img, lambda v: int(v * .55)))
    shadow.save(os.path.join(OUT, "joint_shadow.png"))


def paint_pant_leg(parts):
    p, size, (W, H) = frame(parts, "pant_leg")
    j = {k: (v[0] * SS, v[1] * SS) for k, v in p["joints_px"].items()}
    hx, hy = j["hip_near"]
    kx, ky = j["knee_near"]
    fx, fy = j["foot_near"]
    half = p["width"] / 2 * 1024 * SS
    mask = Image.new("L", (W, H), 0)
    d = ImageDraw.Draw(mask)
    d.ellipse([hx - half * 1.2, hy - half * 1.2, hx + half * 1.2, hy + half * 1.2], fill=255)
    d.polygon([(hx - half * 1.1, hy), (hx + half * 1.1, hy), (kx + half, ky), (fx + half * .85, fy + half * .4),
               (fx - half * .85, fy + half * .4), (kx - half, ky)], fill=255)
    body = shaded(mask, (100, 98, 92, 255), (45, 44, 42, 255))
    detail = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    dd = ImageDraw.Draw(detail)
    dd.rounded_rectangle([kx, ky - half * .9, kx + half, ky + half * .9], radius=half * .4, fill=(170, 125, 75, 255))  # Knee patch.
    dd.rectangle([hx - half * 1.1, hy + (ky - hy) * .35, hx + half * 1.1, hy + (ky - hy) * .45], fill=(120, 75, 40, 255))
    detail.putalpha(Image.composite(detail.getchannel("A"), Image.new("L", (W, H), 0), mask))
    finish([outlined(mask), body, detail], size, "pant_leg")


def paint_box(parts, pid, light, dark, radius=.25, inset=(.6, .6, .6, .6)):
    p, size, (W, H) = frame(parts, pid)
    pad = (p["overlap"] + 0.02) * 1024 * SS
    mask = Image.new("L", (W, H), 0)
    ImageDraw.Draw(mask).rounded_rectangle([pad * inset[0], pad * inset[1], W - pad * inset[2], H - pad * inset[3]],
                                           radius=min(W, H) * radius, fill=255)
    return mask, shaded(mask, light, dark), size, (W, H), pad


def paint_pelvis(parts):
    mask, body, size, (W, H), pad = paint_box(parts, "pelvis", (100, 98, 92, 255), (45, 44, 42, 255), .3)
    belt = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    ImageDraw.Draw(belt).rectangle([0, pad * .6, W, pad * 1.4], fill=(110, 70, 40, 255))
    belt.putalpha(Image.composite(belt.getchannel("A"), Image.new("L", (W, H), 0), mask))
    finish([outlined(mask), body, belt], size, "pelvis")


def paint_boot(parts):
    mask, body, size, (W, H), pad = paint_box(parts, "boot", (190, 120, 60, 255), (95, 55, 25, 255), .2, (.6, .6, .4, .6))
    sole = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    ImageDraw.Draw(sole).rectangle([0, H - pad * 1.6, W, H], fill=(40, 32, 26, 255))
    sole.putalpha(Image.composite(sole.getchannel("A"), Image.new("L", (W, H), 0), mask))
    finish([outlined(mask), body, sole], size, "boot")


def paint_backpack(parts):
    mask, body, size, (W, H), pad = paint_box(parts, "backpack", (175, 120, 70, 255), (90, 55, 30, 255), .22)
    roll = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    ImageDraw.Draw(roll).rounded_rectangle([pad * .5, pad * .5, W - pad * .5, H * .25], radius=H * .1, fill=(95, 120, 70, 255))
    finish([outlined(mask), body, roll], size, "backpack")


if __name__ == "__main__":
    os.makedirs(OUT, exist_ok=True)
    with open(os.path.join(HERO, "skeleton.json"), encoding="utf-8") as f:
        parts = json.load(f)["parts"]
    paint_sleeve(parts)
    paint_glove(parts)
    paint_torso(parts)
    paint_head(parts)
    paint_eyes()
    paint_pant_leg(parts)
    paint_pelvis(parts)
    paint_boot(parts)
    paint_backpack(parts)
    paint_shadow()
    print("wrote placeholders to", OUT)
