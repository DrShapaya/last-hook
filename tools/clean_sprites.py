# Cleans the painted sprites cut from reference sheets (assets/sprites):
#   1. Stray fragments of neighbouring objects: every separate piece that is
#      not the main object and touches the picture's border is removed (plus
#      a short list of known fragments that stop just short of the border).
#   2. Straight cuts: where the slicer cut an object along a straight line
#      (grass and bushes cut flat at the bottom, a branch cut at the side),
#      the edge is faded out along an irregular, softly noisy contour, so it
#      reads as tapering growth instead of a ruler line.
# Flag cloths are textures, not cut-outs, and are left alone.
# Run: python tools/clean_sprites.py [--dry]
import glob, os, sys
from collections import deque
import numpy as np
from PIL import Image

ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "game", "assets", "sprites")
SKIP = ("flags",)
SOFTEN = ("vegetation", "trees")
# Fragments that do not touch the border but belong to a neighbour.
KNOWN = {"trees/tree_dead_2.png", "vegetation/vine_root_5.png"}
DRY = "--dry" in sys.argv

def label(mask):
    h, w = mask.shape
    lab = np.zeros((h, w), np.int32)
    n = 0
    ys, xs = np.nonzero(mask)
    for y0, x0 in zip(ys, xs):
        if lab[y0, x0]: continue
        n += 1
        lab[y0, x0] = n
        q = deque([(y0, x0)])
        while q:
            y, x = q.popleft()
            for dy in (-1, 0, 1):
                for dx in (-1, 0, 1):
                    ny, nx = y + dy, x + dx
                    if 0 <= ny < h and 0 <= nx < w and mask[ny, nx] and not lab[ny, nx]:
                        lab[ny, nx] = n
                        q.append((ny, nx))
    return lab, n

def strip_fragments(rgba, name):
    alpha = rgba[:, :, 3]
    lab, n = label(alpha > 20)
    if n <= 1: return rgba, 0
    sizes = np.bincount(lab.ravel())
    sizes[0] = 0
    main = int(sizes.argmax())
    removed = 0
    # "At the border": within the slicer's margin of the picture's edge.
    m = 8
    border = set(np.unique(np.concatenate([lab[:m].ravel(), lab[-m:].ravel(), lab[:, :m].ravel(), lab[:, -m:].ravel()]))) - {0}
    for k in range(1, n + 1):
        if k == main: continue
        if k in border or name in KNOWN:
            # Also clear the faint halo around the piece.
            piece = lab == k
            grown = piece.copy()
            for _ in range(2):
                grown = grown | np.roll(grown, 1, 0) | np.roll(grown, -1, 0) | np.roll(grown, 1, 1) | np.roll(grown, -1, 1)
            grown &= ~(lab == main)
            rgba[grown, 3] = 0
            removed += 1
    return rgba, removed

def noise1d(length, seed, scale):
    rng = np.random.default_rng(seed)
    knots = rng.uniform(0, 1, length // max(4, scale) + 3)
    x = np.linspace(0, len(knots) - 3, length)
    i = np.floor(x).astype(int)
    t = x - i
    t = t * t * (3 - 2 * t)
    return knots[i] * (1 - t) + knots[i + 1] * t

def straight_sides(alpha):
    # A side is a straight cut when much of the object's outline on it sits
    # on one line (the outermost opaque row/column).
    solid = alpha > 160
    ys, xs = np.nonzero(solid)
    if len(ys) == 0: return []
    top, bottom, left, right = ys.min(), ys.max(), xs.min(), xs.max()
    sides = []
    for side, line, span in (("bottom", solid[bottom, left:right + 1], right - left + 1), ("top", solid[top, left:right + 1], right - left + 1),
                             ("left", solid[top:bottom + 1, left], bottom - top + 1), ("right", solid[top:bottom + 1, right], bottom - top + 1)):
        if span > 20 and line.sum() > max(14, span * .22): sides.append(side)
    return sides

def feather(rgba, side, seed):
    alpha = rgba[:, :, 3].astype(np.float32)
    solid = alpha > 160
    ys, xs = np.nonzero(solid)
    h, w = alpha.shape
    if side in ("bottom", "top"):
        extent = ys.max() - ys.min() + 1
        band = max(6.0, extent * .07)
        edge = ys.max() if side == "bottom" else ys.min()
        n = noise1d(w, seed, 18) * .7 + noise1d(w, seed + 7, 5) * .3
        depth = band * (.35 + .65 * n)  # how far the fade reaches in, per column
        rows = np.arange(h)[:, None].astype(np.float32)
        dist = (edge - rows) if side == "bottom" else (rows - edge)  # 0 at the cut, grows inward
        ramp = np.clip(dist / depth[None, :], 0, 1)
    else:
        extent = xs.max() - xs.min() + 1
        band = max(6.0, extent * .07)
        edge = xs.max() if side == "right" else xs.min()
        n = noise1d(h, seed, 18) * .7 + noise1d(h, seed + 7, 5) * .3
        depth = band * (.35 + .65 * n)
        cols = np.arange(w)[None, :].astype(np.float32)
        dist = (edge - cols) if side == "right" else (cols - edge)
        ramp = np.clip(dist / depth[:, None], 0, 1)
    ramp = ramp * ramp * (3 - 2 * ramp)
    rgba[:, :, 3] = (alpha * ramp).astype(np.uint8)
    return rgba

def main():
    changed = 0
    for path in sorted(glob.glob(os.path.join(ROOT, "*", "*.png"))):
        name = os.path.relpath(path, ROOT).replace("\\", "/")
        if name.split("/")[0] in SKIP: continue
        rgba = np.array(Image.open(path).convert("RGBA"))
        rgba, removed = strip_fragments(rgba, name)
        # Straight cuts are softened on plants only: chests, stones and
        # skulls stand on flat bottoms of their own.
        sides = straight_sides(rgba[:, :, 3]) if name.split("/")[0] in SOFTEN else []
        for index, side in enumerate(sides):
            rgba = feather(rgba, side, sum(name.encode()) + index * 31)
        if removed or sides:
            changed += 1
            print(f"{name}: fragments {removed}, softened {sides}")
            if not DRY:
                picture = Image.fromarray(rgba)
                # Trim the room a removed fragment leaves, keeping the margin.
                box = picture.getchannel("A").point(lambda v: 255 if v > 8 else 0).getbbox()
                if box: picture = picture.crop((max(0, box[0] - 6), max(0, box[1] - 6), min(picture.width, box[2] + 6), min(picture.height, box[3] + 6)))
                picture.save(path)
    print("changed", changed)

if __name__ == "__main__":
    main()
