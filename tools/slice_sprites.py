"""Cuts the painted sprite sheets (references/<folder>) into single sprites
for the game.

    python tools/slice_sprites.py

Each sheet holds a row (or two) of plants on a clear background. A plant is a
connected patch of opaque pixels, grown a little so its loose leaves stay
with it; patches are taken row by row, left to right, trimmed with a small
margin and saved as game/assets/sprites/<folder>/<kind>_<n>.png, at most
MAX_SIDE px on their longer side.
"""
import os
from collections import deque

from PIL import Image, ImageFilter

HERE = os.path.dirname(os.path.abspath(__file__))
REFERENCES = os.path.join(HERE, "..", "references")
SPRITES = os.path.join(HERE, "..", "game", "assets", "sprites")
MAX_SIDE = 384
MARGIN = 6
# Folder -> sheet (file name prefix) -> sprite kind.
SHEETS = {
    "vegetation": {
        "exec-0b4cab57": "icicle", "exec-15aee314": "grass_tuft", "exec-1df0ed59": "grass_blades",
        "exec-4c6dbe89": "snow_plant", "exec-6b097d0b": "vine_dry", "exec-7d23b3ba": "cactus",
        "exec-7f97644d": "vine_green", "exec-9873edb3": "vine_root", "exec-b7125cf3": "vine_frost",
        "exec-d45726e6": "dry_plant", "exec-f5896764": "bush",
    },
    "stones": {
        "exec-0b9b084b": "stone_snow", "exec-3e9a67d3": "stone_grey", "exec-94b64fed": "scree_grey",
        "exec-bcdbca9f": "stone_desert", "exec-bceab953": "scree_desert", "exec-e9de1478": "scree_snow",
    },
    "treasures": {
        "exec-365eac63": "treasure_a", "exec-6eb9f500": "treasure_b", "exec-c34fd378": "treasure_desert",
        "exec-d4a38e82": "treasure_winter",
    },
    "crystals": {"exec-34270cc5": "crystal_blue", "exec-7b748711": "crystal_ice", "exec-d5c5a241": "crystal_amber"},
    "trees": {"exec-8fab4ed1": "tree_dead", "exec-af3f39e0": "tree_snow", "exec-e3cfa69a": "tree_green"},
    "bones": {"exec-d3ab5b51": "skull"},
}


def components(mask, scale):
    """Bounding boxes (in full-size pixels) of the connected patches of a
    reduced mask."""
    width, height = mask.size
    pixels = mask.load()
    seen = [[False] * width for _ in range(height)]
    boxes = []
    for y in range(height):
        for x in range(width):
            if seen[y][x] or pixels[x, y] == 0:
                continue
            queue = deque([(x, y)])
            seen[y][x] = True
            x0, y0, x1, y1, count = x, y, x, y, 0
            while queue:
                cx, cy = queue.popleft()
                count += 1
                x0, y0, x1, y1 = min(x0, cx), min(y0, cy), max(x1, cx), max(y1, cy)
                for nx, ny in ((cx + 1, cy), (cx - 1, cy), (cx, cy + 1), (cx, cy - 1)):
                    if 0 <= nx < width and 0 <= ny < height and not seen[ny][nx] and pixels[nx, ny]:
                        seen[ny][nx] = True
                        queue.append((nx, ny))
            boxes.append(((x0 * scale, y0 * scale, (x1 + 1) * scale, (y1 + 1) * scale), count))
    return boxes


def isolate(crop):
    """The crop with only its largest patch (grown a little, so loose leaves
    and tips stay with it) left opaque."""
    scale = 3
    alpha = crop.getchannel("A")
    small = alpha.point(lambda v: 255 if v > 24 else 0).resize((max(1, crop.width // scale), max(1, crop.height // scale)), Image.BOX)
    small = small.point(lambda v: 255 if v > 0 else 0).filter(ImageFilter.MaxFilter(5))
    found = components(small, 1)
    if len(found) < 2:
        return crop
    (x0, y0, x1, y1), _ = max(found, key=lambda f: f[1])
    # The patch's own pixels: flood the reduced mask from inside its box.
    pixels = small.load()
    keep = Image.new("L", small.size, 0)
    kept = keep.load()
    start = next(((x, y) for y in range(y0, y1) for x in range(x0, x1) if pixels[x, y]), None)
    queue = deque([start])
    kept[start] = 255
    while queue:
        cx, cy = queue.popleft()
        for nx, ny in ((cx + 1, cy), (cx - 1, cy), (cx, cy + 1), (cx, cy - 1)):
            if 0 <= nx < small.width and 0 <= ny < small.height and pixels[nx, ny] and not kept[nx, ny]:
                kept[nx, ny] = 255
                queue.append((nx, ny))
    # Only the largest patch is kept when it is clearly the plant itself.
    if sum(1 for v in keep.getdata() if v) < sum(1 for v in small.getdata() if v) * 0.6:
        return crop
    mask = keep.resize(crop.size, Image.NEAREST)
    cleaned = crop.copy()
    cleaned.putalpha(Image.composite(alpha, Image.new("L", crop.size, 0), mask))
    return cleaned


def split_merged(boxes, alpha, expected):
    """Plants painted close together come out as one patch. While there are
    fewer patches than the sheet holds, the widest one (in units of the
    typical width) is cut at the emptiest columns between its parts."""
    columns = alpha.load()
    while len(boxes) < expected:
        widths = sorted(b[2] - b[0] for b in boxes)
        typical = widths[len(widths) // 2] if len(boxes) >= 3 else (alpha.width / expected)
        widest = max(boxes, key=lambda b: (b[2] - b[0]) / typical)
        parts = max(2, round((widest[2] - widest[0]) / typical))
        parts = min(parts, expected - len(boxes) + 1)
        x0, y0, x1, y1 = widest
        profile = []
        for x in range(x0, x1):
            profile.append(sum(1 for y in range(y0, y1, 2) if columns[x, y] > 24))
        cuts = [x0]
        for k in range(1, parts):
            centre = x0 + (x1 - x0) * k // parts
            span = (x1 - x0) // (parts * 3)
            window = range(max(x0, centre - span), min(x1, centre + span))
            cuts.append(min(window, key=lambda x: profile[x - x0]))
        cuts.append(x1)
        boxes.remove(widest)
        for a, b in zip(cuts, cuts[1:]):
            boxes.append((a, y0, b, y1))
    return boxes


def band_boxes(band, expected):
    scale = 4
    alpha = band.getchannel("A").point(lambda v: 255 if v > 24 else 0)
    small = alpha.resize((band.width // scale, band.height // scale), Image.BOX).point(lambda v: 255 if v > 0 else 0)
    small = small.filter(ImageFilter.MaxFilter(5))
    boxes = [box for box, count in components(small, scale) if count > small.width * small.height * 0.004]
    boxes = split_merged(boxes, alpha, expected)
    # Row by row: patches whose centres are within half a patch height share
    # a row.
    boxes.sort(key=lambda b: (b[1] + b[3]) / 2)
    rows = []
    for box in boxes:
        centre = (box[1] + box[3]) / 2
        if rows and abs(centre - rows[-1][0]) < (box[3] - box[1]) * 0.5:
            rows[-1][1].append(box)
        else:
            rows.append([centre, [box]])
    return [box for _, row in rows for box in sorted(row, key=lambda b: b[0])]


def slice_sheet(path, kind, target, expected, rows=1):
    """Treasure sheets hold two rows that may touch: the sheet is cut at its
    emptiest line between them first, and each band sliced on its own."""
    sheet = Image.open(path).convert("RGBA")
    bands = [(0, sheet.height)]
    if rows == 2:
        alpha = sheet.getchannel("A")
        pixels = alpha.load()
        def filled(y):
            return sum(1 for x in range(0, sheet.width, 3) if pixels[x, y] > 24)
        cut = min(range(int(sheet.height * .35), int(sheet.height * .65)), key=filled)
        bands = [(0, cut), (cut, sheet.height)]
    ordered = []
    for top, bottom in bands:
        band = sheet.crop((0, top, sheet.width, bottom))
        for box in band_boxes(band, expected // rows):
            ordered.append((box[0], box[1] + top, box[2], box[3] + top))
    saved = []
    for index, box in enumerate(ordered):
        x0, y0, x1, y1 = box
        crop = sheet.crop((max(0, x0 - MARGIN), max(0, y0 - MARGIN), min(sheet.width, x1 + MARGIN), min(sheet.height, y1 + MARGIN)))
        # Keep only this plant's pixels: drop bits of its neighbours that
        # reach into the crop, then trim to its own opaque bounds.
        crop = isolate(crop)
        crop = crop.crop(crop.getchannel("A").point(lambda v: 255 if v > 8 else 0).getbbox())
        padded = Image.new("RGBA", (crop.width + MARGIN * 2, crop.height + MARGIN * 2), (0, 0, 0, 0))
        padded.paste(crop, (MARGIN, MARGIN))
        side = max(padded.size)
        if side > MAX_SIDE:
            padded = padded.resize((round(padded.width * MAX_SIDE / side), round(padded.height * MAX_SIDE / side)), Image.LANCZOS)
        name = f"{kind}_{index + 1}.png"
        padded.save(os.path.join(target, name))
        saved.append((name, padded.size))
    return saved


def main():
    for folder, sheets in SHEETS.items():
        target = os.path.join(SPRITES, folder)
        os.makedirs(target, exist_ok=True)
        for file in sorted(os.listdir(os.path.join(REFERENCES, folder))):
            prefix = file[:13]
            if prefix not in sheets:
                continue
            expected = 10 if folder == "treasures" else 5
            rows = 2 if folder == "treasures" else 1
            for name, size in slice_sheet(os.path.join(REFERENCES, folder, file), sheets[prefix], target, expected, rows):
                print(folder, name, size)


if __name__ == "__main__":
    main()
