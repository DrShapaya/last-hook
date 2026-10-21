# Builds the final "peeking over the ledge" icon set for Last Hook.
# Writes icon.svg plus Android adaptive background / foreground / monochrome
# into game/assets (or the folder given as the first argument).
import math, os, sys
OUT = sys.argv[1] if len(sys.argv) > 1 else os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "game", "assets")

def P(pts, fill, extra=""):
    return f'<polygon points="{" ".join(f"{x:.1f},{y:.1f}" for x,y in pts)}" fill="{fill}" {extra}/>'

def svg(body, size=1024, defs=""):
    return (f'<svg xmlns="http://www.w3.org/2000/svg" width="{size}" height="{size}" viewBox="0 0 1024 1024">'
            f'<defs>{defs}</defs>{body}</svg>\n')

SKY_DEF = ('<linearGradient id="sky" x1="0" y1="0" x2="0" y2="1024" gradientUnits="userSpaceOnUse">'
           '<stop stop-color="#3a8ce0"/><stop offset=".7" stop-color="#8cc5f2"/><stop offset="1" stop-color="#b9def8"/></linearGradient>')

def ridge(base, amp, c1, c2, n, phase):
    tops = [(1024*i/n, base-amp*(.5+.5*math.sin(i*2.1+phase))) for i in range(n+1)]
    out = ""
    for i in range(n):
        a, b = tops[i], tops[i+1]
        mid = ((a[0]+b[0])/2+18*math.sin(i+phase), max(a[1], b[1])+amp*.7)
        out += P([a, b, mid], c1 if i % 2 == 0 else c2)
        out += P([a, mid, (mid[0], 1024), (a[0], 1024)], c2)
        out += P([b, (b[0], 1024), (mid[0], 1024), mid], c1)
    return out

def background():
    return '<rect width="1024" height="1024" fill="url(#sky)"/>' + ridge(600, 110, "#b4d8f6", "#9fcaf0", 5, .4) + ridge(700, 80, "#9ac6ee", "#87b9e8", 4, 1.7)

def rope():
    d = "M690 360 C 730 250 800 140 870 -40"
    return (f'<path d="{d}" fill="none" stroke="#5e3a12" stroke-width="46" stroke-linecap="round"/>'
            f'<path d="{d}" fill="none" stroke="#c27b31" stroke-width="32" stroke-linecap="round"/>'
            f'<path d="{d}" fill="none" stroke="#eab06a" stroke-width="10" stroke-dasharray="20 26" stroke-linecap="round"/>')

def head():
    # Cube head in a slight 3/4 view: lit top, warm front, shaded right side.
    F = [(250, 330), (650, 312), (664, 760), (240, 770)]
    T = [(250, 330), (372, 214), (762, 202), (650, 312)]
    S = [(650, 312), (762, 202), (776, 640), (664, 760)]
    out = P(T, "#ffd45f") + P(S, "#db841b") + P(F, "#f7a72b")
    out += P([(250, 330), (650, 312), (648, 338), (251, 356)], "#ffe39a", 'opacity=".6"')
    out += P([(372, 214), (762, 202), (740, 222), (392, 232)], "#fff0b8", 'opacity=".55"')
    # Side strap and buckle, as on the character model.
    out += P([(650, 470), (770, 380), (772, 450), (654, 545)], "#7a4a22")
    out += P([(690, 452), (738, 416), (740, 486), (692, 522)], "#3b2a1e")
    out += P([(700, 462), (728, 440), (729, 476), (701, 498)], "#b9c0c4")
    # Eyes: tall pills with a catch light, glancing up toward the next hold.
    for cx in (372, 520):
        out += f'<rect x="{cx-40}" y="450" width="80" height="170" rx="40" fill="#18222b"/>'
        out += f'<circle cx="{cx-6}" cy="488" r="18" fill="#ffffff"/>'
    return out

def ledge():
    out = P([(0, 690), (1024, 650), (1024, 1024), (0, 1024)], "#9e947d")
    out += P([(0, 690), (1024, 650), (1024, 706), (0, 748)], "#f1ede3")
    out += P([(0, 748), (1024, 706), (1024, 780), (0, 818)], "#d3cbb6")
    out += P([(0, 818), (420, 797), (300, 1024), (0, 1024)], "#b3a98f")
    out += P([(420, 797), (1024, 780), (1024, 1024), (300, 1024)], "#968c75")
    out += P([(380, 700), (640, 690), (640, 718), (380, 729)], "#f6c32f")
    out += '<path d="M760 712 L742 760 L770 800 L752 850" fill="none" stroke="#7d7462" stroke-width="10" stroke-linecap="round" stroke-linejoin="round"/>'
    return out

def glove(x, y, flip=1):
    g = f'<g transform="translate({x} {y}) scale({flip} 1)">'
    g += '<rect x="-84" y="-6" width="168" height="104" rx="46" fill="#3f3128"/>'
    for i, fx in enumerate((-66, -26, 14)):
        g += f'<rect x="{fx}" y="{-18+(i % 2)*6}" width="38" height="108" rx="19" fill="#57453a"/>'
    g += '<rect x="44" y="18" width="40" height="70" rx="20" fill="#4a3a30"/>'
    g += '<rect x="-74" y="74" width="148" height="34" rx="14" fill="#8e5527"/>'
    g += '<rect x="-20" y="80" width="40" height="22" rx="5" fill="#c3c9cc"/>'
    return g + '</g>'

def scene_front():
    return rope() + head() + ledge() + glove(216, 632) + glove(700, 612, -1)

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
    return adaptive(rope() + head()) + adaptive_wide(ledge()) + adaptive(glove(216, 632) + glove(700, 612, -1))

open(f"{OUT}/icon.svg", "w").write(svg(background() + scene_front(), 1024, SKY_DEF))
open(f"{OUT}/icon_background.svg", "w").write(svg(background(), 432, SKY_DEF))
open(f"{OUT}/icon_foreground.svg", "w").write(svg(adaptive_front(), 432))
open(f"{OUT}/icon_monochrome.svg", "w").write(svg(monochrome(), 432))
print("written to", OUT)
