# Builds the "peeking over the ledge" icon set for Last Hook: the cube-headed
# explorer peeks over a limestone ledge, gloves on its lip, the rope running up
# out of the frame. Faces are shaded with gradients, with rim light, contact
# shadows, a sunlit sky with faceted snowy peaks and stitched leather details.
# Writes icon.svg plus Android adaptive background / foreground / monochrome
# into game/assets (or the folder given as the first argument).
import math, os, sys
OUT = sys.argv[1] if len(sys.argv) > 1 else os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "game", "assets")

def P(pts, fill, extra=""):
    return f'<polygon points="{" ".join(f"{x:.1f},{y:.1f}" for x,y in pts)}" fill="{fill}" {extra}/>'

def svg(body, size=1024, defs=""):
    return (f'<svg xmlns="http://www.w3.org/2000/svg" width="{size}" height="{size}" viewBox="0 0 1024 1024">'
            f'<defs>{defs}</defs>{body}</svg>\n')

def linear(name, x1, y1, x2, y2, stops):
    s = "".join(f'<stop offset="{o}" stop-color="{c}"{f" stop-opacity={chr(34)}{a}{chr(34)}" if a is not None else ""}/>' for o, c, a in stops)
    return f'<linearGradient id="{name}" x1="{x1}" y1="{y1}" x2="{x2}" y2="{y2}" gradientUnits="userSpaceOnUse">{s}</linearGradient>'

def radial(name, cx, cy, r, stops):
    s = "".join(f'<stop offset="{o}" stop-color="{c}" stop-opacity="{a}"/>' for o, c, a in stops)
    return f'<radialGradient id="{name}" cx="{cx}" cy="{cy}" r="{r}" gradientUnits="userSpaceOnUse">{s}</radialGradient>'

DEFS = "".join([
    linear("sky", 0, 0, 0, 1024, [(0, "#2b74d6", None), (.55, "#6db2ee", None), (.8, "#a9d6f6", None), (1, "#d8eefc", None)]),
    radial("sun", 210, 190, 420, [(0, "#fffbea", 1), (.18, "#fff3c8", .9), (.55, "#ffe9a8", .25), (1, "#ffe9a8", 0)]),
    linear("top", 300, 210, 700, 320, [(0, "#ffe590", None), (1, "#ffcf4f", None)]),
    linear("front", 0, 330, 0, 770, [(0, "#ffb63a", None), (.65, "#f5a028", None), (1, "#e38c1c", None)]),
    linear("side", 650, 0, 780, 0, [(0, "#df8a1e", None), (1, "#bb6a12", None)]),
    linear("ledgeTop", 0, 650, 0, 760, [(0, "#fbf8f1", None), (1, "#e7e0cf", None)]),
    linear("ledgeFace", 0, 740, 0, 1024, [(0, "#cfc6b0", None), (.45, "#ab9f86", None), (1, "#8b8069", None)]),
    linear("rope", 0, 0, 40, 0, [(0, "#9a5a22", None), (.45, "#d48a3c", None), (1, "#8a4f1c", None)]),
    linear("glove", 0, -20, 0, 100, [(0, "#6a5446", None), (1, "#3a2c23", None)]),
    linear("eye", 0, 450, 0, 620, [(0, "#24323e", None), (1, "#0f171e", None)]),
    radial("vignette", 512, 512, 760, [(.62, "#0e2246", 0), (1, "#0e2246", .35)]),
    '<filter id="soft" x="-20%" y="-20%" width="140%" height="140%"><feGaussianBlur stdDeviation="14"/></filter>',
    '<filter id="blur6" x="-20%" y="-20%" width="140%" height="140%"><feGaussianBlur stdDeviation="6"/></filter>',
])

def peaks(base, items, lit, shade, snow, snow_shade):
    # Faceted snowy peaks: the face toward the sun is lit, a jagged snow cap.
    out = ""
    for left, top_x, top_h, right in items:
        top = (top_x, base - top_h)
        ridge = (top_x + 18, 1024)
        out += P([(left, 1024), top, ridge], lit) + P([top, (right, 1024), ridge], shade)
        k = .34
        cl = (top[0] + (left - top[0]) * k, top[1] + (1024 - top[1]) * k * .55)
        cr = (top[0] + (right - top[0]) * k, top[1] + (1024 - top[1]) * k * .55)
        cm = (top[0] + 10, top[1] + (1024 - top[1]) * k * .62)
        out += P([top, cl, ((cl[0] + cm[0]) / 2, (cl[1] + cm[1]) / 2 - 22), cm], snow)
        out += P([top, cm, ((cm[0] + cr[0]) / 2, (cm[1] + cr[1]) / 2 - 26), cr], snow_shade)
    return out

def background():
    out = '<rect width="1024" height="1024" fill="url(#sky)"/><rect width="1024" height="1024" fill="url(#sun)"/>'
    for cx, cy, rx in ((640, 250, 120), (740, 232, 90), (820, 262, 80), (120, 420, 90), (210, 404, 70)):
        out += f'<ellipse cx="{cx}" cy="{cy}" rx="{rx}" ry="{rx*.36:.0f}" fill="#ffffff" opacity=".62" filter="url(#blur6)"/>'
    out += peaks(600, [(-120, 90, 210, 330), (180, 420, 260, 640), (520, 760, 230, 1000), (840, 1040, 190, 1240)], "#bcdaf3", "#93bde6", "#f7fbfe", "#d8e8f6")
    out += peaks(700, [(-60, 210, 170, 460), (340, 600, 200, 860), (720, 960, 150, 1200)], "#9cc7ec", "#76a6da", "#eef6fd", "#c9ddf1")
    return out

def rope():
    d = "M690 360 C 730 250 800 140 870 -40"
    return (f'<path d="{d}" fill="none" stroke="#1b2a3d" stroke-opacity=".18" stroke-width="54" stroke-linecap="round" transform="translate(14 10)" filter="url(#blur6)"/>'
            f'<path d="{d}" fill="none" stroke="#5a3311" stroke-width="48" stroke-linecap="round"/>'
            f'<path d="{d}" fill="none" stroke="#c27b31" stroke-width="36" stroke-linecap="round"/>'
            f'<path d="{d}" fill="none" stroke="#7b4517" stroke-width="36" stroke-dasharray="7 15" stroke-linecap="butt" opacity=".75"/>'
            f'<path d="{d}" fill="none" stroke="#f1bd76" stroke-width="8" stroke-dasharray="16 22" stroke-linecap="round" transform="translate(-9 -3)"/>')

def head():
    # Cube head in a slight 3/4 view: lit top, warm front, shaded right side,
    # bevelled edges catching the light.
    F = [(250, 330), (650, 312), (664, 760), (240, 770)]
    T = [(250, 330), (372, 214), (762, 202), (650, 312)]
    S = [(650, 312), (762, 202), (776, 640), (664, 760)]
    out = P(T, "url(#top)") + P(S, "url(#side)") + P(F, "url(#front)")
    # Bevels: light along the top rim, a warm rim on the left edge.
    out += P([(250, 330), (650, 312), (648, 340), (252, 358)], "#ffe7a6", 'opacity=".75"')
    out += P([(372, 214), (762, 202), (742, 222), (392, 233)], "#fff4c8", 'opacity=".7"')
    out += P([(650, 312), (762, 202), (764, 228), (654, 340)], "#f3a83a", 'opacity=".7"')
    out += P([(250, 330), (276, 344), (266, 752), (240, 770)], "#ffd27a", 'opacity=".45"')
    # Worn texture: a few soft specks and scuffs.
    for x, y, r, o in ((330, 400, 9, .25), (560, 380, 6, .22), (600, 690, 11, .18), (300, 690, 7, .2), (470, 270, 8, .25), (700, 520, 7, .25)):
        out += f'<circle cx="{x}" cy="{y}" r="{r}" fill="#c9771a" opacity="{o}"/>'
    # Side strap and buckle, with stitches, as on the character model.
    out += P([(650, 470), (770, 380), (772, 450), (654, 545)], "#7a4a22")
    out += P([(652, 480), (770, 392), (770, 400), (652, 489)], "#a8693a", 'opacity=".8"')
    out += '<path d="M660 528 L768 444" stroke="#c99a6a" stroke-width="3" stroke-dasharray="9 8" fill="none"/>'
    out += P([(690, 452), (738, 416), (740, 486), (692, 522)], "#3b2a1e")
    out += P([(700, 462), (728, 440), (729, 476), (701, 498)], "#cfd5d8")
    out += P([(700, 462), (728, 440), (728, 448), (700, 470)], "#ffffff", 'opacity=".7"')
    # Eyes: tall pills with two catch lights, glancing up toward the next hold.
    for cx in (372, 520):
        out += f'<rect x="{cx-40}" y="450" width="80" height="170" rx="40" fill="url(#eye)"/>'
        out += f'<circle cx="{cx-6}" cy="490" r="19" fill="#ffffff"/>'
        out += f'<circle cx="{cx+16}" cy="530" r="7" fill="#ffffff" opacity=".7"/>'
    return out

def ledge():
    # Contact shadow of the head on the ledge top.
    out = '<ellipse cx="500" cy="712" rx="300" ry="26" fill="#3b3120" opacity=".35" filter="url(#soft)"/>'
    out += P([(0, 690), (1024, 650), (1024, 1024), (0, 1024)], "url(#ledgeFace)")
    out += P([(0, 690), (1024, 650), (1024, 706), (0, 748)], "url(#ledgeTop)")
    out += P([(0, 690), (1024, 650), (1024, 657), (0, 697)], "#ffffff", 'opacity=".9"')
    out += P([(0, 748), (1024, 706), (1024, 780), (0, 818)], "#d3cbb6")
    out += P([(0, 818), (420, 797), (300, 1024), (0, 1024)], "#b3a98f")
    out += P([(420, 797), (1024, 780), (1024, 1024), (300, 1024)], "#968c75")
    out += P([(0, 748), (1024, 706), (1024, 716), (0, 758)], "#6f6553", 'opacity=".35"')
    # The yellow hold mark of the game's grips.
    out += P([(380, 700), (640, 690), (640, 718), (380, 729)], "#f6c32f")
    out += P([(380, 700), (640, 690), (640, 696), (380, 706)], "#ffe590")
    out += P([(380, 724), (640, 713), (640, 718), (380, 729)], "#b88a12")
    # Cracks and pebbles.
    out += '<path d="M760 712 L742 760 L770 800 L752 850" fill="none" stroke="#6f6553" stroke-width="10" stroke-linecap="round" stroke-linejoin="round"/>'
    out += '<path d="M130 830 L160 880 L140 930" fill="none" stroke="#7d7462" stroke-width="8" stroke-linecap="round" stroke-linejoin="round" opacity=".7"/>'
    for x, y, r in ((560, 880, 16), (600, 905, 10), (880, 860, 13), (240, 960, 12)):
        out += f'<ellipse cx="{x}" cy="{y}" rx="{r}" ry="{r*.7:.0f}" fill="#7f7560"/><ellipse cx="{x-3}" cy="{y-3}" rx="{r*.6:.0f}" ry="{r*.35:.0f}" fill="#c9c0a9"/>'
    # Moss tufts on the lip.
    for x, y in ((70, 694), (930, 660)):
        out += "".join(f'<path d="M{x+dx} {y+4} q{dx*.3} -30 {dx*.6+6} -40" stroke="#5aa055" stroke-width="7" fill="none" stroke-linecap="round"/>' for dx in (-14, -4, 6, 16))
    return out

def glove(x, y, flip=1):
    g = f'<g transform="translate({x} {y}) scale({flip} 1)">'
    g += '<ellipse cx="0" cy="104" rx="92" ry="16" fill="#3b3120" opacity=".35" filter="url(#blur6)"/>'
    g += '<rect x="-84" y="-6" width="168" height="104" rx="46" fill="#33271f"/>'
    for i, fx in enumerate((-66, -26, 14)):
        top = -18 + (i % 2) * 6
        g += f'<rect x="{fx}" y="{top}" width="38" height="108" rx="19" fill="url(#glove)"/>'
        g += f'<rect x="{fx+8}" y="{top+8}" width="14" height="30" rx="7" fill="#9b8170" opacity=".55"/>'
    g += '<rect x="44" y="18" width="40" height="70" rx="20" fill="#4a3a30"/>'
    g += '<rect x="52" y="26" width="12" height="24" rx="6" fill="#8d7363" opacity=".5"/>'
    g += '<rect x="-74" y="74" width="148" height="34" rx="14" fill="#8e5527"/>'
    g += '<rect x="-74" y="74" width="148" height="9" rx="4" fill="#b8763f"/>'
    g += '<path d="M-64 100 H64" stroke="#d9a575" stroke-width="3" stroke-dasharray="8 7"/>'
    g += '<rect x="-20" y="80" width="40" height="22" rx="5" fill="#c3c9cc"/>'
    g += '<rect x="-20" y="80" width="40" height="7" rx="3" fill="#ffffff" opacity=".7"/>'
    return g + '</g>'

def head_shadow():
    # The head's soft shadow on the sky side behind it lifts it off the peaks.
    return P([(240, 330), (372, 214), (762, 202), (776, 640), (664, 760), (240, 770)], "#0e2246", 'opacity=".25" filter="url(#soft)" transform="translate(18 18)"')

def scene_front():
    return rope() + head_shadow() + head() + ledge() + glove(216, 632) + glove(700, 612, -1)

def monochrome():
    w = "#ffffff"
    out = P([(250, 330), (372, 214), (762, 202), (776, 640), (664, 760), (240, 770)], w)
    out += '<rect x="132" y="626" width="168" height="104" rx="46" fill="#fff"/><rect x="616" y="606" width="168" height="104" rx="46" fill="#fff"/>'
    out += '<path d="M690 360 C 730 250 800 140 870 -40" fill="none" stroke="#fff" stroke-width="40" stroke-linecap="round"/>'
    holes = "".join(f'<rect x="{cx-40}" y="450" width="80" height="170" rx="40" fill="#000"/>' for cx in (372, 520))
    mask = f'<mask id="m"><rect width="1024" height="1024" fill="#fff"/>{holes}</mask>'
    band = P([(-40, 694), (1064, 650), (1064, 720), (-40, 760)], w)
    return f'<defs>{mask}</defs>' + adaptive_wide(band) + adaptive(f'<g mask="url(#m)">{out}</g>')

FIT = "translate(512 512) scale(.70) translate(-508 -520)"
WIDEN = "translate(512 0) scale(1.6 1) translate(-512 0)"

def adaptive(content):
    # Android masks to the central 66/108 of the canvas; keep the face inside it.
    return f'<g transform="{FIT}">{content}</g>'

def adaptive_wide(content):
    # The ledge must still reach both edges of the canvas after the fit.
    return f'<g transform="{WIDEN}"><g transform="{FIT}">{content}</g></g>'

def adaptive_front():
    return adaptive(rope() + head_shadow() + head()) + adaptive_wide(ledge()) + adaptive(glove(216, 632) + glove(700, 612, -1))

# The app icon itself is the painted artwork in assets/art/icon_source.png;
# only the monochrome (themed) silhouette is still drawn here.
from PIL import Image, ImageFilter

def raster_icons():
    art = Image.open(os.path.join(OUT, "art", "icon_source.png")).convert("RGBA")
    art.resize((1024, 1024), Image.LANCZOS).save(os.path.join(OUT, "icon.png"))
    # Android adaptive: the mask shows the central 72 of 108 dp. The art is
    # laid at 80 % of the canvas (the mask keeps 83 % of it, gloves included)
    # over a blurred, enlarged copy that fills the margins.
    size = 864
    canvas = art.resize((size, size), Image.LANCZOS).filter(ImageFilter.GaussianBlur(28))
    inner = int(size * .8)
    picture = art.resize((inner, inner), Image.LANCZOS)
    feather = Image.new("L", (inner, inner), 0)
    edge = int(inner * .04)
    feather.paste(255, (edge, edge, inner - edge, inner - edge))
    feather = feather.filter(ImageFilter.GaussianBlur(edge * .6))
    canvas.paste(picture, ((size - inner) // 2, (size - inner) // 2), feather)
    canvas.resize((432, 432), Image.LANCZOS).save(os.path.join(OUT, "icon_background.png"))
    Image.new("RGBA", (432, 432), (0, 0, 0, 0)).save(os.path.join(OUT, "icon_foreground.png"))

raster_icons()
open(f"{OUT}/icon_monochrome.svg", "w", encoding="utf-8").write(svg(monochrome(), 432))
print("written to", OUT)
