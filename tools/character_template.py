"""Skeleton template for the cut-out hero (CHARACTER_PLAN.md, stage 0).

Writes game/assets/hero/skeleton.json (bones, sockets, parts, layer order) and
docs/character/skeleton-template.png: the hero in the neutral reference pose
with joint pivots, bones, part borders, the overlap each part must paint under
its neighbour, and the drawing order.

Units: hero height = 1.0, origin on the ground between the feet, x toward the
face (the hero looks right), y up. Pixel sizes are given for the master scale
MASTER_PX (hero height in pixels when a part is painted).

Run: python tools/character_template.py
"""
import json
import math
import os

from PIL import Image, ImageDraw, ImageFont

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(ROOT, "docs", "character")
GAME_HERO = os.path.join(ROOT, "game", "assets", "hero")
REFERENCE = os.path.join(GAME_HERO, "pioneer", "reference-v2.png")
REFERENCE_FEET_X = 546  # Pixel column of x = 0 (between the boots) in the reference.
MASTER_PX = 1024  # Hero height when parts are painted (2x+ of phone size).

# name: (parent, x, y). Neutral pose measured on the chosen reference
# game/assets/hero/pioneer/reference-v2.png (strict side view facing right;
# x = 0 between the boots). Arms and legs are straight in the rest pose.
BONES = {
    "root": (None, 0.0, 0.0),
    "pelvis": ("root", -0.01, 0.45),
    "spine": ("pelvis", -0.01, 0.52),
    "chest": ("spine", 0.0, 0.62),
    "neck": ("chest", 0.0, 0.73),
    "head": ("neck", 0.0, 0.755),
    "shoulder_near": ("chest", -0.02, 0.67),
    "elbow_near": ("shoulder_near", -0.0225, 0.5625),
    "hand_near": ("elbow_near", -0.025, 0.455),
    "shoulder_far": ("chest", 0.06, 0.66),
    "elbow_far": ("shoulder_far", 0.0725, 0.5575),
    "hand_far": ("elbow_far", 0.085, 0.455),
    "hip_near": ("pelvis", -0.03, 0.44),
    "knee_near": ("hip_near", -0.035, 0.265),
    "foot_near": ("knee_near", -0.04, 0.09),
    "hip_far": ("pelvis", 0.03, 0.44),
    "knee_far": ("hip_far", 0.035, 0.265),
    "foot_far": ("knee_far", 0.04, 0.09),
}

# Points attached to bones; heads move eyes/headwear sockets with their shape.
SOCKETS = {
    "grip_near": ("hand_near", -0.025, 0.41, "Точка хвата каната (заменяет Grip)"),
    "grip_far": ("hand_far", 0.085, 0.41, "Вторая рука на канате"),
    "back": ("chest", -0.17, 0.57, "Рюкзак"),
    "head_top": ("head", -0.03, 1.0, "Головной убор (задаёт голова)"),
    "eyes": ("head", 0.072, 0.86, "Глаза и лицо (задаёт голова)"),
    "neck_front": ("chest", 0.06, 0.71, "Шарф, значок"),
    "belt": ("pelvis", 0.0, 0.47, "Пояс: верёвка, фляга"),
}

# Each part: slot, bones it follows (two for skinned bends), its outline as a
# polygon in hero units, and how far (units) it must be painted beyond its
# visible border under the neighbour named in `under`.
PARTS = [
    {"id": "head", "slot": "head", "bones": ["head"], "rigid": True,
     "shape": [(-0.18, 0.75), (0.11, 0.75), (0.11, 1.0), (-0.18, 1.0)],
     "under": "низ головы над воротником", "overlap": 0.02, "color": (240, 170, 40)},
    {"id": "torso", "slot": "torso", "bones": ["spine", "chest"], "rigid": False,
     "shape": [(-0.08, 0.46), (0.1, 0.46), (0.1, 0.74), (-0.08, 0.74)],
     "under": "подол заходит на таз, плечи круглые под рукавами, шея под головой", "overlap": 0.035, "color": (90, 140, 70)},
    {"id": "pelvis", "slot": "pants", "bones": ["pelvis"], "rigid": True,
     "shape": [(-0.08, 0.39), (0.08, 0.39), (0.08, 0.48), (-0.08, 0.48)],
     "under": "верх таза под подолом куртки", "overlap": 0.035, "color": (70, 70, 80)},
    {"id": "sleeve", "slot": "torso", "bones": ["shoulder", "elbow"], "rigid": False, "pair": True,
     "chain": ["shoulder_near", "elbow_near", "hand_near"], "width": 0.08,
     "under": "шапка плеча под торсом, манжета над перчаткой", "overlap": 0.03, "color": (110, 160, 80)},
    {"id": "glove", "slot": "gloves", "bones": ["hand"], "rigid": True, "pair": True,
     "chain": ["hand_near"], "radius": 0.042,
     "under": "запястье уходит в манжету", "overlap": 0.02, "color": (70, 55, 45)},
    {"id": "pant_leg", "slot": "pants", "bones": ["hip", "knee"], "rigid": False, "pair": True,
     "chain": ["hip_near", "knee_near", "foot_near"], "width": 0.095,  # v2 pants are wider than the sleeves.
     "under": "бедро уходит в таз, низ штанины в ботинок", "overlap": 0.03, "color": (80, 80, 92)},
    {"id": "boot", "slot": "boots", "bones": ["foot"], "rigid": True, "pair": True,
     "shape_rel": [(-0.07, -0.09), (0.08, -0.09), (0.08, -0.04), (0.02, 0.03), (-0.06, 0.03)],
     "under": "голенище с запасом под штаниной", "overlap": 0.025, "color": (180, 110, 50)},
    {"id": "backpack", "slot": "backpack", "bones": ["chest"], "rigid": True,
     "shape": [(-0.28, 0.41), (-0.07, 0.41), (-0.07, 0.73), (-0.27, 0.73)],
     "under": "лямки уходят за плечо", "overlap": 0.025, "color": (160, 100, 50)},
]

# Back to front for a hero looking right. Each glove sits under its sleeve:
# the wrist goes into the cuff. Turning swaps near and far; the
# animation may move an arm across the torso (throw) by changing this order.
LAYERS = [
    "glove_far", "sleeve_far", "boot_far", "pant_leg_far", "backpack", "pelvis",
    "pant_leg_near", "boot_near", "torso", "joint_shadows", "head", "eyes",
    "headwear", "glove_near", "sleeve_near", "hook",
]


def bone_pos(name):
    return BONES[name][1], BONES[name][2]


def part_entry(part):
    entry = {k: part[k] for k in ("id", "slot", "bones", "rigid", "under", "overlap")}
    entry["paired"] = part.get("pair", False)
    entry["overlap_px"] = round(part["overlap"] * MASTER_PX)
    for key in ("width", "radius"):
        if key in part:
            entry[key] = part[key]
    entry.update(paint_frame(part))
    if "chain" in part:
        entry["chain"] = part["chain"]
    return entry


def glove_center(side):
    ex, ey = bone_pos("elbow_" + side)
    hx, hy = bone_pos("hand_" + side)
    length = math.hypot(hx - ex, hy - ey)
    r = next(p for p in PARTS if p["id"] == "glove")["radius"]
    return hx + (hx - ex) / length * r * 0.8, hy + (hy - ey) / length * r * 0.8


def paint_frame(part):
    """Where the part is painted: canvas size and joint pixels.

    Limbs and gloves are painted straight and hanging down (first joint at the
    top); the rig turns them onto their bones. Other parts are painted upright
    exactly as they stand in the neutral pose.
    """
    pad = part["overlap"] + 0.02
    px = lambda v: round(v * MASTER_PX)
    if "chain" in part and "width" in part:
        points = chain_points(part["chain"], "near")
        lengths = [0.0]
        for a, b in zip(points, points[1:]):
            lengths.append(lengths[-1] + math.hypot(b[0] - a[0], b[1] - a[1]))
        w, h = part["width"] + 2 * pad, lengths[-1] + 2 * pad
        joints = {n: [px(w / 2), px(pad + l)] for n, l in zip(part["chain"], lengths)}
        return {"canvas_px": [px(w), px(h)], "joints_px": joints, "pivot": part["chain"][0],
                "axis": [part["chain"][0], part["chain"][-1]], "painted": "straight, hanging down"}
    if "radius" in part:
        r = part["radius"]
        size = 2 * r + 2 * pad
        return {"canvas_px": [px(size), px(size)], "joints_px": {"hand_near": [px(size / 2), px(size / 2 - 0.8 * r)]},
                "pivot": "hand_near", "axis": ["elbow_near", "hand_near"], "painted": "hanging down, wrist at the top"}
    pts = outline(part, "near")
    x0, x1 = min(p[0] for p in pts) - pad, max(p[0] for p in pts) + pad
    y0, y1 = min(p[1] for p in pts) - pad, max(p[1] for p in pts) + pad
    bones = [b if b in BONES else b for b in part["bones"]]
    if part["id"] == "boot":
        bones = ["foot_near"]
    joints = {b: [px(bone_pos(b)[0] - x0), px(y1 - bone_pos(b)[1])] for b in bones}
    return {"canvas_px": [px(x1 - x0), px(y1 - y0)], "joints_px": joints, "pivot": bones[0], "axis": None,
            "painted": "upright, as in the neutral pose"}


def chain_points(chain, side):
    return [bone_pos(n.replace("_near", "_" + side)) for n in chain]


def outline(part, side):
    if "shape" in part:
        return part["shape"]
    if "shape_rel" in part:
        fx, fy = bone_pos("foot_" + side)
        return [(fx + x, fy + y) for x, y in part["shape_rel"]]
    points = chain_points(part["chain"], side)
    if "radius" in part:
        cx, cy = glove_center(side)
        r = part["radius"]
        return [(cx + r * math.cos(a / 12 * math.tau), cy + r * math.sin(a / 12 * math.tau)) for a in range(12)]
    # A limb tube around shoulder->elbow->wrist (or hip->knee->ankle).
    w = part["width"] / 2
    left, right = [], []
    for i, (x, y) in enumerate(points):
        a = points[max(i - 1, 0)]
        b = points[min(i + 1, len(points) - 1)]
        dx, dy = b[0] - a[0], b[1] - a[1]
        length = math.hypot(dx, dy) or 1
        nx, ny = -dy / length * w, dx / length * w
        taper = 1 - 0.18 * i / max(1, len(points) - 1)
        left.append((x + nx * taper, y + ny * taper))
        right.append((x - nx * taper, y - ny * taper))
    return left + right[::-1]


def write_json():
    data = {
        "units": "hero height = 1.0; origin on the ground between the feet; x toward the face; y up",
        "master_px": MASTER_PX,
        "bones": [{"name": n, "parent": p, "position": [x, y]} for n, (p, x, y) in BONES.items()],
        "sockets": [{"name": n, "bone": b, "position": [x, y], "use": u} for n, (b, x, y, u) in SOCKETS.items()],
        "parts": [part_entry(p) for p in PARTS],
        "layers_back_to_front": LAYERS,
        "rules": [
            "Каждая деталь рисуется целиком, с продолжением под соседней деталью на overlap_px.",
            "Рукав, штанина и торс гнутся сеткой по двум костям; кисти, ботинки, голова и рюкзак жёсткие.",
            "Свет мягкий сверху-слева, без теней от соседних деталей: тени стыков — отдельный слой joint_shadows.",
            "Одна картинка на парную деталь; дальняя затемняется шейдером.",
            "Контур одной толщины: 6 px при master_px.",
        ],
    }
    os.makedirs(GAME_HERO, exist_ok=True)
    with open(os.path.join(GAME_HERO, "skeleton.json"), "w", encoding="utf-8", newline="\n") as f:
        json.dump(data, f, ensure_ascii=False, indent="\t")


def font(size, bold=False):
    name = "segoeuib.ttf" if bold else "segoeui.ttf"
    return ImageFont.truetype(os.path.join(os.environ.get("WINDIR", "C:/Windows"), "Fonts", name), size)


def draw_png():
    W, H = 2600, 1500
    img = Image.new("RGB", (W, H), (246, 243, 236))
    d = ImageDraw.Draw(img, "RGBA")
    scale = 1150
    ox, oy = 560, 1360

    def P(x, y):
        return (ox + x * scale, oy - y * scale)

    d.text((40, 24), "Шаблон скелета героя — нейтральная поза, вид сбоку, смотрит вправо", font=font(40, True), fill=(30, 30, 30))
    d.text((40, 78), f"Единица — рост героя. Детали рисуются при росте {MASTER_PX} px. Круги — оси суставов, штрих — запас под соседнюю деталь.", font=font(24), fill=(70, 70, 70))
    # The chosen reference underneath, so the fit of bones and parts shows.
    if os.path.exists(REFERENCE):
        ref = Image.open(REFERENCE).convert("RGBA")
        alpha = ref.getchannel("A").point(lambda v: 255 if v > 40 else 0)
        x0, y0, x1, y1 = alpha.getbbox()
        k = scale / (y1 - y0)
        ref = ref.resize((round(ref.width * k), round(ref.height * k)), Image.LANCZOS)
        ref.putalpha(ref.getchannel("A").point(lambda v: int(v * 0.45)))
        img.paste(ref, (round(ox - REFERENCE_FEET_X * k), round(oy - y1 * k)), ref)
    # Ground and height marks.
    d.line([P(-0.4, 0), P(0.4, 0)], fill=(120, 120, 120), width=3)
    for t in range(0, 11):
        y = t / 10
        d.line([P(-0.42, y), P(-0.4, y)], fill=(120, 120, 120), width=2)
        d.text((P(-0.47, y)[0], P(-0.47, y)[1] - 12), f"{y:.1f}", font=font(18), fill=(120, 120, 120))
    # Parts, far side first, in layer order.
    order = []
    for layer in LAYERS:
        for part in PARTS:
            if layer == part["id"] or layer in (part["id"] + "_far", part["id"] + "_near"):
                side = "far" if layer.endswith("_far") else "near"
                order.append((part, side))
    for part, side in order:
        pts = outline(part, side)
        r, g, b = part["color"]
        if side == "far":
            r, g, b = int(r * .65), int(g * .65), int(b * .65)
        # Overlap margin: grown outline, hatched look via dashed border.
        cx = sum(p[0] for p in pts) / len(pts)
        cy = sum(p[1] for p in pts) / len(pts)
        grown = []
        for x, y in pts:
            dx, dy = x - cx, y - cy
            dist = math.hypot(dx, dy) or 1
            grown.append((x + dx / dist * part["overlap"], y + dy / dist * part["overlap"]))
        gp = [P(*p) for p in grown]
        for i in range(len(gp)):
            a, b2 = gp[i], gp[(i + 1) % len(gp)]
            steps = max(1, int(math.hypot(b2[0] - a[0], b2[1] - a[1]) / 14))
            for s in range(0, steps, 2):
                t0, t1 = s / steps, min(1, (s + 1) / steps)
                d.line([(a[0] + (b2[0] - a[0]) * t0, a[1] + (b2[1] - a[1]) * t0),
                        (a[0] + (b2[0] - a[0]) * t1, a[1] + (b2[1] - a[1]) * t1)], fill=(r, g, b, 200), width=3)
        d.polygon([P(*p) for p in pts], fill=(r, g, b, 150), outline=(40, 30, 20, 255))
    # Eyes hint on the cube head.
    for ex in (0.06, 0.1):
        d.rounded_rectangle([P(ex - 0.012, 0.89), P(ex + 0.012, 0.83)], radius=8, fill=(30, 25, 25, 230))
    # Bones and pivots.
    for name, (parent, x, y) in BONES.items():
        if parent:
            px, py = bone_pos(parent)
            far = name.endswith("_far")
            d.line([P(px, py), P(x, y)], fill=(40, 80, 200, 150 if far else 255), width=5)
    for name, (parent, x, y) in BONES.items():
        cx, cy = P(x, y)
        far = name.endswith("_far")
        d.ellipse([cx - 11, cy - 11, cx + 11, cy + 11], fill=(255, 255, 255, 255), outline=(200, 40, 40, 140 if far else 255), width=4)
        d.line([cx - 16, cy, cx + 16, cy], fill=(200, 40, 40, 200), width=2)
        d.line([cx, cy - 16, cx, cy + 16], fill=(200, 40, 40, 200), width=2)
        if not far and name != "root":
            d.text((cx + 16, cy - 30), name, font=font(19), fill=(160, 30, 30))
    for name, (bone, x, y, use) in SOCKETS.items():
        cx, cy = P(x, y)
        d.rectangle([cx - 9, cy - 9, cx + 9, cy + 9], outline=(20, 140, 120), width=4)
        d.text((cx + 12, cy + 4), name, font=font(18), fill=(20, 120, 100))
    # Right column: legend, parts table, layer order.
    x0 = 1260
    d.text((x0, 140), "Детали (слот · кости · запас под стык · холст)", font=font(30, True), fill=(30, 30, 30))
    y = 190
    for part in PARTS:
        e = part_entry(part)
        r, g, b = part["color"]
        d.rectangle([x0, y + 6, x0 + 28, y + 34], fill=(r, g, b), outline=(40, 30, 20))
        kind = "жёсткая" if part["rigid"] else "гнётся по 2 костям"
        pair = " ×2 (ближняя/дальняя)" if part.get("pair") else ""
        d.text((x0 + 42, y), f"{part['id']}{pair} — {part['slot']}, {kind}", font=font(24, True), fill=(30, 30, 30))
        d.text((x0 + 42, y + 32), f"{part['under']}; запас {e['overlap_px']} px; холст {e['canvas_px'][0]}×{e['canvas_px'][1]} px", font=font(20), fill=(80, 80, 80))
        y += 74
    y += 16
    d.text((x0, y), "Порядок слоёв (сзади → вперёд)", font=font(30, True), fill=(30, 30, 30))
    y += 46
    col = 0
    for i, layer in enumerate(LAYERS):
        cx = x0 + (i // 8) * 420
        cy = y + (i % 8) * 34
        d.text((cx, cy), f"{i + 1:>2}. {layer}", font=font(22), fill=(50, 50, 50))
    y += 8 * 34 + 20
    notes = [
        "Поворот героя меняет ближние и дальние детали местами.",
        "Бросок: ближняя рука уходит за корпус и выходит вперёд — порядок задаёт анимация.",
        "Тени стыков (рукав на торсе, рюкзак на спине, голова на шее) — отдельный слой.",
        "Свет на деталях — мягкий сверху-слева, без теней от соседей.",
        "Красный крест — ось сустава; бирюзовый квадрат — гнездо.",
    ]
    for line in notes:
        d.text((x0, y), "• " + line, font=font(21), fill=(60, 60, 60))
        y += 32
    img.save(os.path.join(OUT, "skeleton-template.png"))


if __name__ == "__main__":
    os.makedirs(OUT, exist_ok=True)
    write_json()
    draw_png()
    print("wrote", os.path.join(GAME_HERO, "skeleton.json"), "and", os.path.join(OUT, "skeleton-template.png"))
