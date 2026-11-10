"""Turn the detailed hero (build_hero.py) into a game model (docs/CHARACTER_3D_PLAN.md, stages 3-4).

Input: docs/character/3d/hero.blend, the detailed model (~650k triangles,
procedural materials). Output: game/assets/hero/model/hero.glb.

1. Low mesh: the large forms (head, jacket, sleeves, gloves, pants, boots,
   backpack, ...) are copied and decimated to a mobile budget, split by the
   triangle share of each part's surface area. Small details (stitches,
   buckles, laces, eyelets, thin straps) stay only in the detailed model.
2. Bake: one UV atlas (larger islands; the face, hands and boots get more
   texels). Each part bakes only from its own detailed source and the details
   lying on it, so no part catches a neighbour's colour. Colour, normal and
   an ORM map (R ambient occlusion, G roughness) at 4096, each also at 2048
   for the climb, written as PNGs next to the model.
3. Skeleton: bones at the joints of build_hero.py. Each low part may only
   follow its own bones (a glove follows its hand, pants the pelvis and legs);
   weights blend between the nearest allowed bones by distance, so elbows and
   knees bend smoothly without one leg pulling the other.
4. Export glTF binary (mesh, slot colours, skeleton; no textures).

Run: blender --background docs/character/3d/hero.blend --python tools/blender/export_hero.py -- [--tris=24000] [--size=4096] [--reuse-bake] [--stage=prep]
  The bake resumes: --stage=prep saves docs/character/3d/bake/hero_bake_prep.blend;
  then run blender --background on that file with this script (no --stage)
  until it prints HERO_EXPORTED: each run bakes the parts still missing
  (bake/progress/) and exports at the end.
"""
import json
import math
import os
import sys
import time

import bmesh
import bpy
import numpy
from mathutils import Vector

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
OUT_DIR = os.path.join(ROOT, "game", "assets", "hero", "model")
TEX_DIR = os.path.join(ROOT, "docs", "character", "3d", "bake")

args = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
opts = dict(a[2:].split("=", 1) for a in args if a.startswith("--") and "=" in a)
TRIS = int(opts.get("tris", 24000))
SIZE = int(opts.get("size", 4096))
REUSE_BAKE = "--reuse-bake" in args

# Names of detail objects that only live in the detailed model (baked in).
DETAIL_WORDS = ("Строчка", "Шов", "Рант", "Зубцы", "Носок", "Край", "Пряжка", "Люверс", "Шнурок", "Бант",
                "Блик", "Кнопка", "Протектор", "Рифление", "Бегунок", "Торец", "Держатель", "Стяжка",
                "Ремешок", "Пластина", "Язычок", "Манжета", "Ремень", "Лямка", "Пояс", "Подол",
                "Планка", "Нагрудный", "Наколенник", "Отворот", "Каблук", "Клапан", "Карман брюк")
# Kept as low parts even though they are small or match a word above.
# The head strap and its buckle stand off the head: baked flat they read as
# a blurred sticker past the head's edge, so they stay geometry.
KEEP = ("Глаз", "Подошва", "Карман рюкзака", "Клапан рюкзака", "Ремень головы", "Пряжка головы")

# ---------------------------------------------------------------- skeleton

S, E, W = (-0.005, 0.655), (0.0, 0.555), (0.01, 0.46)
ARM_Y, LEG_Y = 0.145, 0.076  # Must match build_hero.py.


def arm(side):
    y = -ARM_Y if side == "near" else ARM_Y
    k = 1 if side == "near" else -1
    sh = Vector((S[0], y, S[1]))
    el = Vector((E[0] + 0.02, y - 0.01 * k, E[1]))
    wr = Vector((W[0] + 0.035, y - 0.012 * k, W[1]))
    return sh, el, wr


BONES = {}  # name -> (head, tail, parent)


def define_bones():
    BONES["root"] = (Vector((0, 0, 0)), Vector((0, 0, 0.1)), None)
    BONES["pelvis"] = (Vector((0, 0, 0.40)), Vector((0, 0, 0.46)), "root")
    BONES["spine"] = (Vector((0, 0, 0.46)), Vector((0, 0, 0.56)), "pelvis")
    BONES["chest"] = (Vector((0, 0, 0.56)), Vector((0.005, 0, 0.68)), "spine")
    BONES["neck"] = (Vector((0.005, 0, 0.68)), Vector((0.01, 0, 0.72)), "chest")
    BONES["head"] = (Vector((0.01, 0, 0.72)), Vector((0.03, 0, 1.0)), "neck")
    BONES["backpack"] = (Vector((-0.2, 0, 0.45)), Vector((-0.2, 0, 0.75)), "chest")
    for side in ("near", "far"):
        sh, el, wr = arm(side)
        down = (wr - el).normalized()
        BONES["upper_arm_" + side] = (sh, el, "chest")
        BONES["forearm_" + side] = (el, wr, "upper_arm_" + side)
        BONES["hand_" + side] = (wr, wr + down * 0.1, "forearm_" + side)
        y = -LEG_Y if side == "near" else LEG_Y
        BONES["thigh_" + side] = (Vector((-0.005, y, 0.44)), Vector((0.012, y, 0.255)), "pelvis")
        BONES["shin_" + side] = (Vector((0.012, y, 0.255)), Vector((0.0, y, 0.085)), "thigh_" + side)
        BONES["foot_" + side] = (Vector((0.0, y, 0.085)), Vector((0.12, y, 0.03)), "shin_" + side)


def allowed_bones(name):
    """Which bones a low part may follow."""
    side = "near" if "near" in name else ("far" if "far" in name else None)
    if name.startswith(("Голова", "Ручка", "Глаз", "Ремень головы", "Пряжка головы")):
        return ["head"]
    if name.startswith("Шея"):
        return ["neck", "head"]
    if name.startswith(("Куртка", "Капюшон", "Карман")) and "рюкзака" not in name:
        # Not the arms: a raised arm dragged half the jacket's side into a
        # curtain from the elbow to the waist. The sleeve follows the arm.
        return ["spine", "chest", "neck", "pelvis"]
    if name.startswith("Рукав"):
        return ["chest", "upper_arm_" + side, "forearm_" + side]
    if name.startswith("Перчатка"):
        return ["hand_" + side]
    if name.startswith("Штаны"):
        return ["pelvis", "thigh_near", "shin_near", "thigh_far", "shin_far"]
    if name.startswith("Подошва"):
        return ["foot_" + side]  # The sole is rigid: it must not bend with the shin.
    if name.startswith("Ботинок"):
        return ["foot_" + side, "shin_" + side]
    if name.startswith(("Рюкзак", "Крышка рюкзака", "Карман рюкзака", "Клапан рюкзака", "Коврик", "Термос", "Крышка термоса")):
        return ["backpack"]
    return ["chest"]


# Wardrobe slots (game/scripts/hero_outfit.gd): each low part carries its slot
# in the vertex colour, so the game recolours one slot's fabric in the same
# single pass. Pure 0/1 channels survive any colour space conversion.
SLOT_COLORS = {"head": (1, 0, 0), "jacket": (0, 1, 0), "pants": (0, 0, 1),
               "boots": (1, 1, 0), "gloves": (1, 0, 1), "backpack": (0, 1, 1)}


def slot_of(name):
    if name.startswith("Голова"):
        return "head"
    if name.startswith(("Рюкзак", "Крышка рюкзака", "Карман рюкзака", "Клапан рюкзака", "Коврик")):
        return "backpack"
    if name.startswith(("Куртка", "Капюшон", "Карман", "Рукав")):
        return "jacket"
    if name.startswith("Штаны"):
        return "pants"
    if name.startswith(("Ботинок", "Подошва")):
        return "boots"
    if name.startswith("Перчатка"):
        return "gloves"
    return None


def tag_slot(obj):
    color = SLOT_COLORS.get(slot_of(obj.name), (0, 0, 0))
    layer = obj.data.color_attributes.get("slot") or obj.data.color_attributes.new("slot", "BYTE_COLOR", "CORNER")
    for item in layer.data:
        item.color = (color[0], color[1], color[2], 1.0)
    obj.data.color_attributes.active_color = layer
    obj.data.color_attributes.render_color_index = obj.data.color_attributes.find("slot")


def segment_distance(p, a, b):
    ab = b - a
    t = max(0.0, min(1.0, (p - a).dot(ab) / max(ab.length_squared, 1e-9)))
    return (p - (a + ab * t)).length


def weight_part(obj, as_name=None):
    """Smooth weights over the part's own bones: inverse distance to each bone
    segment, sharpened, the two strongest kept and normalised. as_name: weigh
    a detail (a buckle, a lace) as the part it sits on."""
    as_name = as_name or obj.name
    names = allowed_bones(as_name)
    groups = {n: obj.vertex_groups.get(n) or obj.vertex_groups.new(name=n) for n in names}
    pants = as_name.startswith("Штаны")
    for v in obj.data.vertices:
        co = obj.matrix_world @ v.co
        scores = []
        bones = names
        if pants:
            # Each leg follows only its own thigh and shin; a wide stride
            # stretched the inner legs into a web between the thighs. Only a
            # narrow strip at the crotch blends, through the pelvis.
            # (The inner leg surfaces reach within a centimetre of the centre
            # line, so the strip is bounded by height as well.)
            if abs(co.y) < 0.012 and co.z > 0.37:
                bones = ["pelvis"]
            elif co.y < 0:
                bones = [n for n in names if not n.endswith("_far")]
            else:
                bones = [n for n in names if not n.endswith("_near")]
        for n in bones:
            h, t, _ = BONES[n]
            d = segment_distance(co, h, t)
            scores.append((1.0 / (d ** 4 + 1e-7), n))
        scores.sort(reverse=True)
        top = scores[:2]
        total = sum(sc for sc, _ in top)
        for sc, n in top:
            w = sc / total
            if w > 0.02:
                groups[n].add([v.index], w, "REPLACE")


# ---------------------------------------------------------------- low mesh

def tris(obj):
    return sum(len(p.vertices) - 2 for p in obj.data.polygons)


def area(obj):
    return sum(p.area for p in obj.data.polygons)


def is_low_source(obj):
    if obj.type != "MESH" or obj.name == "Земля":
        return False
    if obj.name.startswith(KEEP):
        return True
    return not any(w in obj.name for w in DETAIL_WORDS)


def make_low(sources):
    """Decimated copies of the large forms, joined into one mesh. Each face
    remembers its part (face attribute "part"), so every part can be baked
    from its own detailed sources only."""
    total_area = sum(area(o) for o in sources)
    lows = []
    for index, src in enumerate(sources):
        low = src.copy()
        low.data = src.data.copy()
        low.name = src.name + " low"
        bpy.context.scene.collection.objects.link(low)
        budget = max(60, int(TRIS * area(src) / total_area))
        ratio = min(1.0, budget / max(1, tris(src)))
        if ratio < 1.0:
            mod = low.modifiers.new("decimate", "DECIMATE")
            mod.ratio = ratio
            mod.use_collapse_triangulate = True
            bpy.context.view_layer.objects.active = low
            bpy.ops.object.select_all(action="DESELECT")
            low.select_set(True)
            bpy.ops.object.modifier_apply(modifier=mod.name)
        weight_part(low)
        tag_slot(low)
        part = low.data.attributes.new("part", "INT", "FACE")
        for item in part.data:
            item.value = index
        lows.append(low)
    bpy.ops.object.select_all(action="DESELECT")
    for o in lows:
        o.select_set(True)
    bpy.context.view_layer.objects.active = lows[0]
    bpy.ops.object.join()
    low = bpy.context.active_object
    low.name = "Герой"
    low.data.name = "Герой"
    return low


# Texel density per part, relative to its surface: the face is what the
# character screen looks at, hands and boots come next.
DENSITY = (("Голова", 1.8), ("Глаз", 2.0), ("Пряжка головы", 1.6), ("Ремень головы", 1.4),
           ("Перчатка", 1.3), ("Ботинок", 1.2), ("Подошва", 1.0))


def density_of(name):
    for prefix, value in DENSITY:
        if name.startswith(prefix):
            return value
    return 1.0


def unwrap(low, sources):
    """Larger islands than before (66 degrees), all at one texel density,
    then the face, hands and boots scaled up before packing."""
    bpy.context.view_layer.objects.active = low
    bpy.ops.object.select_all(action="DESELECT")
    low.select_set(True)
    bpy.ops.object.mode_set(mode="EDIT")
    bpy.ops.mesh.select_all(action="SELECT")
    bpy.ops.uv.smart_project(angle_limit=math.radians(66), island_margin=0.002, area_weight=0.8)
    bpy.ops.uv.average_islands_scale()
    bm = bmesh.from_edit_mesh(low.data)
    uv = bm.loops.layers.uv.active
    part = bm.faces.layers.int.get("part")
    by_part = {}
    for f in bm.faces:
        by_part.setdefault(f[part], []).append(f)
    for index, faces in by_part.items():
        scale = density_of(sources[index].name)
        if scale == 1.0:
            continue
        loops = [l for f in faces for l in f.loops]
        centre = sum((l[uv].uv for l in loops), Vector((0, 0))) / len(loops)
        for l in loops:
            l[uv].uv = centre + (l[uv].uv - centre) * scale
    bmesh.update_edit_mesh(low.data)
    # 16 px at 4096 between islands: the bake margin (6 px) never reaches a neighbour.
    bpy.ops.uv.pack_islands(margin=0.004, rotate=True)
    bpy.ops.object.mode_set(mode="OBJECT")


def owners(sources, highs):
    """Which detailed objects each part bakes from: its own source, and the
    details (stitches, straps, buckles) lying within 1.5 cm of it. Other large
    parts never: a ray from the jacket used to hit the sleeve or the head and
    painted their colour onto the jacket."""
    details = [h for h in highs if h not in sources]
    near = {i: [src] for i, src in enumerate(sources)}
    depsgraph = bpy.context.evaluated_depsgraph_get()
    for d in details:
        verts = d.data.vertices
        step = max(1, len(verts) // 24)
        points = [d.matrix_world @ verts[i].co for i in range(0, len(verts), step)]
        for i, src in enumerate(sources):
            inverse = src.matrix_world.inverted()
            for p in points:
                ok, hit, _, _ = src.closest_point_on_mesh(inverse @ p)
                if ok and ((src.matrix_world @ hit) - p).length < 0.015:
                    near[i].append(d)
                    break
    return near


# ---------------------------------------------------------------- bake

def part_object(low, indices):
    """A temporary copy of the low mesh with only these parts' faces (same UVs)."""
    obj = low.copy()
    obj.data = low.data.copy()
    obj.modifiers.clear()
    obj.parent = None
    obj.matrix_world = low.matrix_world
    bpy.context.scene.collection.objects.link(obj)
    bm = bmesh.new()
    bm.from_mesh(obj.data)
    part = bm.faces.layers.int.get("part")
    bmesh.ops.delete(bm, geom=[f for f in bm.faces if f[part] not in indices], context="FACES")
    bm.to_mesh(obj.data)
    bm.free()
    return obj


PROGRESS = os.path.join(TEX_DIR, "progress")


def progress_done(kind):
    path = os.path.join(PROGRESS, kind + ".json")
    return set(json.load(open(path))) if os.path.exists(path) else set()


CONFLICTS = {}


def conflicts(low, near):
    """Pairs of parts that one bake call must not hold together: a point of
    one part's low surface lies within ray reach (cage 2 cm + ray 6 cm) of
    the other's detailed sources."""
    if CONFLICTS:
        return CONFLICTS
    part = low.data.attributes["part"]
    points = {}
    for poly in low.data.polygons:
        points.setdefault(part.data[poly.index].value, []).append(low.matrix_world @ poly.center)
    reach = 0.085
    for a in near:
        sample = points.get(a, [])[::max(1, len(points.get(a, [])) // 160)]
        CONFLICTS[a] = set()
        for b in near:
            if b == a:
                continue
            for src in near[b]:
                inverse = src.matrix_world.inverted()
                if any(((src.matrix_world @ src.closest_point_on_mesh(inverse @ p)[1]) - p).length < reach for p in sample):
                    CONFLICTS[a].add(b)
                    break
    for a in near:  # Symmetric: either way round spoils a bake.
        for b in CONFLICTS[a]:
            CONFLICTS[b].add(a)
    return CONFLICTS


def bake_groups(low, near, todo):
    """Parts that cannot reach each other bake in one call. Each bake call
    reloads the whole detailed model (~40 s), so fewer calls is most of the
    time saved."""
    clash = conflicts(low, near)
    groups = []
    for i in sorted(todo, key=lambda i: -len(clash[i])):
        for g in groups:
            if not any(j in clash[i] for j in g):
                g.append(i)
                break
        else:
            groups.append([i])
    return groups


def bake_parts(low, near, kind, image_name, colorspace, highs, size=None):
    """Bakes every part not yet done into PROGRESS/<kind>.png, saving after
    each part: a run that stalls (the GPU hung once after ~80 bakes) resumes
    where it stopped."""
    size = size or SIZE
    os.makedirs(PROGRESS, exist_ok=True)
    done = progress_done(kind)
    path = os.path.join(PROGRESS, kind + ".png")
    if done and os.path.exists(path):
        img = bpy.data.images.load(path)
    else:
        img = bpy.data.images.new(image_name, size, size, alpha=False, float_buffer=kind == "NORMAL")
    img.colorspace_settings.name = colorspace
    scene = bpy.context.scene
    bs = scene.render.bake
    bs.use_selected_to_active = True
    bs.cage_extrusion = 0.02
    bs.max_ray_distance = 0.06
    bs.margin = 6
    bs.use_clear = False
    metals = []
    if kind == "DIFFUSE":
        bs.use_pass_direct = False
        bs.use_pass_indirect = False
        bs.use_pass_color = True
        # Metal has no diffuse colour, so buckles and caps baked black. For the
        # colour pass every metal is made non-metallic, then restored.
        for m in bpy.data.materials:
            if not m.use_nodes:
                continue
            for n in m.node_tree.nodes:
                if n.type == "BSDF_PRINCIPLED" and n.inputs["Metallic"].default_value > 0:
                    metals.append((n, n.inputs["Metallic"].default_value))
                    n.inputs["Metallic"].default_value = 0.0
    # The background a part leaves: neutral normal, white occlusion.
    fill = {"NORMAL": (0.5, 0.5, 1.0, 1.0), "AO": (1, 1, 1, 1)}.get(kind, (0, 0, 0, 1))
    if not done:
        img.pixels.foreach_set(numpy.tile(numpy.array(fill, numpy.float32), size * size))
    groups = bake_groups(low, near, [i for i in near if i not in done])
    print("BAKE_GROUPS", kind, [len(g) for g in groups], flush=True)
    for group in groups:
        sources = [h for i in group for h in near[i]]
        obj = part_object(low, set(group))
        obj.hide_render = False
        mat = bpy.data.materials.new("Запекание")
        mat.use_nodes = True
        node = mat.node_tree.nodes.new("ShaderNodeTexImage")
        node.image = img
        mat.node_tree.nodes.active = node
        obj.data.materials.clear()
        obj.data.materials.append(mat)
        bpy.ops.object.select_all(action="DESELECT")
        for h in (highs if kind == "AO" else sources):
            h.select_set(True)
        obj.select_set(True)
        bpy.context.view_layer.objects.active = obj
        # The low copy must not shade the detailed surface it bakes from.
        for flag in ("visible_camera", "visible_diffuse", "visible_glossy", "visible_shadow"):
            setattr(obj, flag, False)
        started = time.time()
        bpy.ops.object.bake(type=kind)
        bpy.data.objects.remove(obj)
        bpy.data.materials.remove(mat)
        img.filepath_raw = path
        img.file_format = "PNG"
        img.save()
        done.update(group)
        json.dump(sorted(done), open(os.path.join(PROGRESS, kind + ".json"), "w"))
        print("BAKED_PART", kind, group, round(time.time() - started, 1), flush=True)
    for n, value in metals:
        n.inputs["Metallic"].default_value = value
    return img


def save_png(img, name, size=None, game=True):
    """Writes the image (optionally scaled down) as PNG next to the model and
    to TEX_DIR. A fresh image from the pixels: copying an image loaded from a
    file gives one without data."""
    w, h = img.size
    pixels = numpy.empty(w * h * 4, numpy.float32)
    img.pixels.foreach_get(pixels)
    out = bpy.data.images.new(name, w, h, alpha=False)
    out.colorspace_settings.name = img.colorspace_settings.name
    out.pixels.foreach_set(pixels)
    if size and size != w:
        out.scale(size, size)
    out.file_format = "PNG"
    path = os.path.join(OUT_DIR, name + ".png")
    for target in ((path,) if game else ()) + (os.path.join(TEX_DIR, name + ".png"),):
        out.filepath_raw = target
        out.save()
    bpy.data.images.remove(out)
    return path


def bake_all(low, near, highs):
    """Colour, normal, and an ORM map (R occlusion, G roughness) at SIZE,
    each also at half size for the climb."""
    scene = bpy.context.scene
    if scene.world is None:
        scene.world = bpy.data.worlds.new("Мир")
    scene.world.light_settings.distance = 0.05  # Occlusion reach: folds, under the head, behind straps.
    low.hide_render = True  # Only the part being baked may stand next to the detailed model.
    color = bake_parts(low, near, "DIFFUSE", "hero_color", "sRGB", highs)
    normal = bake_parts(low, near, "NORMAL", "hero_normal", "Non-Color", highs)
    rough = bake_parts(low, near, "ROUGHNESS", "hero_rough", "Non-Color", highs)
    # Occlusion is soft: baked at half size (a quarter of the per-pixel work,
    # which dominates the bake) and scaled up.
    samples = scene.cycles.samples
    scene.cycles.samples = 64
    ao = bake_parts(low, near, "AO", "hero_ao", "Non-Color", highs, SIZE // 2)
    scene.cycles.samples = samples
    ao.scale(SIZE, SIZE)
    orm = bpy.data.images.new("hero_orm", SIZE, SIZE, alpha=False)
    orm.colorspace_settings.name = "Non-Color"
    a = numpy.empty(SIZE * SIZE * 4, numpy.float32)
    r = numpy.empty(SIZE * SIZE * 4, numpy.float32)
    ao.pixels.foreach_get(a)
    rough.pixels.foreach_get(r)
    pixels = numpy.zeros(SIZE * SIZE * 4, numpy.float32)
    pixels[0::4] = a[0::4]
    pixels[1::4] = r[0::4]
    pixels[3::4] = 1.0
    orm.pixels.foreach_set(pixels)
    for img, name in ((color, "hero_color"), (normal, "hero_normal"), (orm, "hero_orm")):
        # Full size stays with the bake: close-ups use export_showcase.py.
        save_png(img, name, game=False)
        save_png(img, name + "_2k", SIZE // 2, game=False)
    low.hide_render = False


def game_material(low):
    """A plain material: the game shades the hero itself (HeroModel) from the
    PNGs next to the model, so the glb carries no textures."""
    mat = bpy.data.materials.new("Герой")
    mat.use_nodes = True
    low.data.materials.clear()
    low.data.materials.append(mat)


# ---------------------------------------------------------------- armature

def build_armature(low):
    arm_data = bpy.data.armatures.new("Скелет")
    rig = bpy.data.objects.new("Скелет", arm_data)
    bpy.context.scene.collection.objects.link(rig)
    bpy.context.view_layer.objects.active = rig
    bpy.ops.object.select_all(action="DESELECT")
    rig.select_set(True)
    bpy.ops.object.mode_set(mode="EDIT")
    edit = {}
    for name, (h, t, parent) in BONES.items():
        b = arm_data.edit_bones.new(name)
        b.head, b.tail = h, t
        b.roll = 0.0
        edit[name] = b
    for name, (_, _, parent) in BONES.items():
        if parent:
            edit[name].parent = edit[parent]
            edit[name].use_connect = False
    bpy.ops.object.mode_set(mode="OBJECT")
    low.parent = rig
    mod = low.modifiers.new("Скелет", "ARMATURE")
    mod.object = rig
    return rig


def setup_cycles():
    scene = bpy.context.scene
    scene.render.engine = "CYCLES"
    prefs = bpy.context.preferences.addons["cycles"].preferences
    prefs.compute_device_type = "OPTIX"
    prefs.get_devices()
    for d in prefs.devices:
        d.use = d.type == "OPTIX"
    scene.cycles.device = "GPU"
    scene.cycles.samples = 24


PREP = os.path.join(TEX_DIR, "hero_bake_prep.blend")


def prepare():
    """Low mesh, UVs and each part's bake sources, saved to PREP."""
    define_bones()
    scene = bpy.context.scene
    highs = [o for o in scene.objects if o.type == "MESH" and o.name != "Земля"]
    sources = [o for o in highs if is_low_source(o)]
    print("LOW_SOURCES", len(sources), "of", len(highs))
    low = make_low(sources)
    print("LOW_TRIS", tris(low))
    unwrap(low, sources)
    near = owners(sources, highs)
    print("BAKE_SOURCES", sum(len(v) for v in near.values()))
    low["near"] = json.dumps({str(i): [o.name for o in v] for i, v in near.items()})
    if os.path.isdir(PROGRESS):
        for name in os.listdir(PROGRESS):
            os.remove(os.path.join(PROGRESS, name))
    bpy.ops.wm.save_as_mainfile(filepath=PREP)


def loaded_near(low):
    return {int(i): [bpy.data.objects[n] for n in names] for i, names in json.loads(low["near"]).items()}


def main():
    os.makedirs(OUT_DIR, exist_ok=True)
    os.makedirs(TEX_DIR, exist_ok=True)
    # A file that already holds the prepared low mesh only bakes and exports.
    stage = opts.get("stage", "bake" if "Герой" in bpy.data.objects else "all")
    setup_cycles()
    if stage in ("prep", "all"):
        prepare()
        if stage == "prep":
            return
    define_bones()
    scene = bpy.context.scene
    low = bpy.data.objects["Герой"]
    highs = [o for o in scene.objects if o.type == "MESH" and o.name not in ("Земля", "Герой")]
    near = loaded_near(low)
    if not (REUSE_BAKE and os.path.exists(os.path.join(OUT_DIR, "hero_color.png"))):
        bake_all(low, near, highs)
    game_material(low)
    rig = build_armature(low)
    # Only the game model goes into the file.
    for o in highs:
        bpy.data.objects.remove(o)
    for o in list(scene.objects):
        if o not in (low, rig):
            bpy.data.objects.remove(o)
    bpy.ops.object.select_all(action="DESELECT")
    low.select_set(True)
    rig.select_set(True)
    # The game uses the detailed hero (export_showcase.py); this simplified
    # model stays with the bake for reference.
    out = os.path.join(TEX_DIR, "hero_low.glb")
    bpy.ops.export_scene.gltf(filepath=out, export_format="GLB", use_selection=True, export_apply=False,
                              export_skins=True, export_animations=False, export_yup=True,
                              export_vertex_color="ACTIVE", export_image_format="NONE")
    bpy.ops.wm.save_as_mainfile(filepath=os.path.join(TEX_DIR, "hero_game.blend"))
    print("HERO_EXPORTED", out, "tris", tris(low), "bones", len(BONES))


if __name__ == "__main__":
    main()
