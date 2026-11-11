"""Tiling surface detail for the hero (version 2.0): one 512x512 RGBA height
map, a channel per family, that the game's hero shader (hero_model.gd) lays
on the detail UV (hero units) and turns into relief, a little shading and
roughness. Vertex colours carry the large-scale colour (wear, grime); this
carries what vertices cannot: the weave, the grain.

  R  woven nylon/canvas (jacket, the mat): a plain weave, slubs in the yarn
  G  twill (pants): diagonal ribs
  B  leather grain (straps, boots, pack): pebbled cells and fine creases
  A  suede (gloves, knee patches): soft nap

One tile covers DETAIL_TILE hero units (hero_model.gd). Every channel tiles
seamlessly (noise from filtered periodic white noise, periodic cells).

Run: blender --background --python tools/blender/make_detail_maps.py
Output: game/assets/hero/model/hero_detail.png
"""
import os

import bpy
import numpy as np

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
OUT = os.path.join(ROOT, "game", "assets", "hero", "model", "hero_detail.png")
N = 512
rng = np.random.default_rng(7)


def periodic_noise(scale, octaves=1, falloff=0.5):
    """Tileable smooth noise: white noise low-passed in the frequency domain
    (periodic by construction). `scale` = feature size in pixels."""
    out = np.zeros((N, N))
    amp = 1.0
    for o in range(octaves):
        s = scale / (2 ** o)
        f = np.fft.fftfreq(N)
        fx, fy = np.meshgrid(f, f)
        k = np.sqrt(fx ** 2 + fy ** 2) * s
        spec = np.fft.fft2(rng.standard_normal((N, N))) * np.exp(-(k ** 2) * 2.0)
        layer = np.real(np.fft.ifft2(spec))
        out += layer / (layer.std() + 1e-9) * amp
        amp *= falloff
    return out / (out.std() + 1e-9)


def norm(a):
    a = a - a.min()
    return a / (a.max() + 1e-9)


y, x = np.mgrid[0:N, 0:N].astype(np.float64)


def weave(periods=16):
    """Plain weave: warp and weft threads passing over and under each other."""
    p = N / periods
    u, v = x / p, y / p
    # Thread profiles across their width (rounded), along their length they
    # rise over a crossing and dip under the next.
    across_u = np.cos((v % 1.0 - 0.5) * np.pi) ** 0.6  # weft (runs along u)
    across_v = np.cos((u % 1.0 - 0.5) * np.pi) ** 0.6  # warp (runs along v)
    cu, cv = np.floor(u), np.floor(v)
    over = ((cu + cv) % 2) == 0
    rise_u = 0.6 + 0.4 * np.cos((u % 1.0 - 0.5) * np.pi)
    rise_v = 0.6 + 0.4 * np.cos((v % 1.0 - 0.5) * np.pi)
    weft = across_u * np.where(over, rise_u, 0.55)
    warp = across_v * np.where(over, 0.55, rise_v)
    h = np.maximum(weft, warp)
    slub = periodic_noise(40, 2) * 0.12  # Uneven yarn.
    mottle = periodic_noise(90, 3) * 0.1
    return norm(h + slub + mottle)


def twill(periods=20):
    """2/1 twill: diagonal ribs, a little uneven."""
    p = N / periods
    d = (x + y) / p  # Diagonal coordinate (tiles: periods along x and y).
    rib = 0.5 + 0.5 * np.cos(d * np.pi * 2)
    rib = rib ** 0.8
    cross = 0.5 + 0.5 * np.cos(((x - y) / p) * np.pi * 2 * 1.0)
    h = rib * 0.85 + cross * rib * 0.15
    return norm(h + periodic_noise(36, 2) * 0.1 + periodic_noise(110, 2) * 0.08)


def leather(cells=26):
    """Pebbled grain: rounded cells (periodic Voronoi), fine creases."""
    # Jittered grid: pebbles of even size, as on tanned hide.
    g = (np.stack(np.meshgrid(np.arange(cells), np.arange(cells)), -1).reshape(-1, 2) + 0.5
         + (rng.random((cells * cells, 2)) - 0.5) * 0.75)
    pts = g * (N / cells)
    best = np.full((N, N), 1e9)
    second = np.full((N, N), 1e9)
    for px, py in pts:
        dx = np.abs(x - px)
        dy = np.abs(y - py)
        dx = np.minimum(dx, N - dx)
        dy = np.minimum(dy, N - dy)
        d = np.sqrt(dx * dx + dy * dy)
        second = np.where(d < best, best, np.minimum(second, d))
        best = np.minimum(best, d)
    edge = second - best  # 0 on the cell borders.
    pebble = np.clip(edge / (N / cells * 0.35), 0, 1) ** 0.5
    creases = np.abs(periodic_noise(22, 2))
    creases = 1.0 - np.clip(creases * 2.5, 0, 1) ** 0.3 * 0.0 - np.exp(-(periodic_noise(30, 2) ** 2) * 18) * 0.35
    return norm(pebble * 0.8 + creases * 0.35 + periodic_noise(80, 2) * 0.08)


def suede():
    """Soft brushed nap: fine noise, a faint direction, rubbed patches."""
    nap = periodic_noise(4, 2) * 0.5 + periodic_noise(10, 2) * 0.35
    rubbed = periodic_noise(70, 2) * 0.35
    return norm(nap + rubbed)


def main():
    channels = [weave(), twill(), leather(), suede()]
    rgba = np.stack(channels, axis=-1).astype(np.float32)
    img = bpy.data.images.new("hero_detail", N, N, alpha=True, float_buffer=False)
    img.colorspace_settings.name = "Non-Color"
    img.alpha_mode = "STRAIGHT"
    img.pixels.foreach_set(rgba[::-1].ravel())  # Blender stores rows bottom-up.
    img.filepath_raw = OUT
    img.file_format = "PNG"
    img.save()
    print("DETAIL_MAPS", OUT, [round(float(c.mean()), 3) for c in channels])


main()
