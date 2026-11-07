"""Turn the detailed hero (build_hero.py) into a game model (docs/CHARACTER_3D_PLAN.md, stages 3-4).

Input: docs/character/3d/hero.blend, the detailed model (~650k triangles,
procedural materials). Output: game/assets/hero/model/hero.glb.

1. Low mesh: the large forms (head, jacket, sleeves, gloves, pants, boots,
   backpack, ...) are copied and decimated to a mobile budget, split by the
   triangle share of each part's surface area. Small details (stitches,
   buckles, laces, eyelets, thin straps) stay only in the detailed model.
2. Bake: one UV atlas; colour, normal and roughness are baked from the
   detailed model onto the low mesh, so the stitches, buckles and wear stay
   visible as texture.
3. Skeleton: bones at the joints of build_hero.py. Each low part may only
   follow its own bones (a glove follows its hand, pants the pelvis and legs);
   weights blend between the nearest allowed bones by distance, so elbows and
   knees bend smoothly without one leg pulling the other.
4. Export glTF binary with the textures inside.

Run: blender --background docs/character/3d/hero.blend --python tools/blender/export_hero.py -- [--tris=15000] [--size=2048]
"""
import math
import os
import sys

import bmesh
import bpy
from mathutils import Vector

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
OUT_DIR = os.path.join(ROOT, "game", "assets", "hero", "model")
TEX_DIR = os.path.join(ROOT, "docs", "character", "3d", "bake")

args = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
opts = dict(a[2:].split("=", 1) for a in args if a.startswith("--") and "=" in a)
TRIS = int(opts.get("tris", 15000))
SIZE = int(opts.get("size", 2048))

# Names of detail objects that only live in the detailed model (baked in).
DETAIL_WORDS = ("Строчка", "Шов", "Рант", "Зубцы", "Носок", "Край", "Пряжка", "Люверс", "Шнурок", "Бант",
                "Блик", "Кнопка", "Протектор", "Рифление", "Бегунок", "Торец", "Держатель", "Стяжка",
                "Ремешок", "Пластина", "Язычок", "Манжета", "Ремень", "Лямка", "Пояс", "Подол",
                "Планка", "Нагрудный", "Наколенник", "Отворот", "Каблук", "Клапан", "Карман брюк")
# Kept as low parts even though they are small or match a word above.
KEEP = ("Глаз", "Подошва", "Карман рюкзака", "Клапан рюкзака")

# ---------------------------------------------------------------- skeleton

S, E, W = (-0.005, 0.655), (0.0, 0.555), (0.01, 0.46)
ARM_Y, LEG_Y = 0.145, 0.058


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
    if name.startswith(("Голова", "Ручка", "Глаз")):
        return ["head"]
    if name.startswith("Шея"):
        return ["neck", "head"]
    if name.startswith(("Куртка", "Капюшон", "Карман")) and "рюкзака" not in name:
        return ["spine", "chest", "neck", "upper_arm_near", "upper_arm_far", "pelvis"]
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


def segment_distance(p, a, b):
    ab = b - a
    t = max(0.0, min(1.0, (p - a).dot(ab) / max(ab.length_squared, 1e-9)))
    return (p - (a + ab * t)).length


def weight_part(obj):
    """Smooth weights over the part's own bones: inverse distance to each bone
    segment, sharpened, the two strongest kept and normalised."""
    names = allowed_bones(obj.name)
    groups = {n: obj.vertex_groups.get(n) or obj.vertex_groups.new(name=n) for n in names}
    for v in obj.data.vertices:
        co = obj.matrix_world @ v.co
        scores = []
        for n in names:
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
    total_area = sum(area(o) for o in sources)
    lows = []
    for src in sources:
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


def unwrap(low):
    bpy.context.view_layer.objects.active = low
    bpy.ops.object.select_all(action="DESELECT")
    low.select_set(True)
    bpy.ops.object.mode_set(mode="EDIT")
    bpy.ops.mesh.select_all(action="SELECT")
    bpy.ops.uv.smart_project(angle_limit=math.radians(60), island_margin=0.004, area_weight=0.6)
    bpy.ops.uv.pack_islands(margin=0.004)
    bpy.ops.object.mode_set(mode="OBJECT")


# ---------------------------------------------------------------- bake

def bake(low, highs, kind, image_name, colorspace):
    img = bpy.data.images.new(image_name, SIZE, SIZE, alpha=False, float_buffer=False)
    img.colorspace_settings.name = colorspace
    mat = low.data.materials[0]
    node = mat.node_tree.nodes.new("ShaderNodeTexImage")
    node.image = img
    for n in mat.node_tree.nodes:
        n.select = False
    node.select = True
    mat.node_tree.nodes.active = node
    bpy.ops.object.select_all(action="DESELECT")
    for h in highs:
        h.select_set(True)
    low.select_set(True)
    bpy.context.view_layer.objects.active = low
    scene = bpy.context.scene
    bs = scene.render.bake
    bs.use_selected_to_active = True
    # Rays long enough to reach details standing off the low surface (thermos
    # holders, straps); shorter ones left black patches in the bake.
    bs.cage_extrusion = 0.02
    bs.max_ray_distance = 0.06
    bs.margin = 12
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
    bpy.ops.object.bake(type=kind)
    for n, value in metals:
        n.inputs["Metallic"].default_value = value
    path = os.path.join(TEX_DIR, image_name + ".png")
    img.filepath_raw = path
    img.file_format = "PNG"
    img.save()
    mat.node_tree.nodes.remove(node)
    return path


def game_material(low, paths):
    """One material for the whole hero: baked colour, normal and roughness."""
    mat = bpy.data.materials.new("Герой")
    mat.use_nodes = True
    nt = mat.node_tree
    bsdf = next(n for n in nt.nodes if n.type == "BSDF_PRINCIPLED")

    def tex(path, colorspace):
        n = nt.nodes.new("ShaderNodeTexImage")
        n.image = bpy.data.images.load(path)
        n.image.colorspace_settings.name = colorspace
        return n

    nt.links.new(tex(paths["color"], "sRGB").outputs["Color"], bsdf.inputs["Base Color"])
    rough = tex(paths["roughness"], "Non-Color")
    nt.links.new(rough.outputs["Color"], bsdf.inputs["Roughness"])
    nmap = nt.nodes.new("ShaderNodeNormalMap")
    nt.links.new(tex(paths["normal"], "Non-Color").outputs["Color"], nmap.inputs["Color"])
    nt.links.new(nmap.outputs["Normal"], bsdf.inputs["Normal"])
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


def main():
    os.makedirs(OUT_DIR, exist_ok=True)
    os.makedirs(TEX_DIR, exist_ok=True)
    define_bones()
    scene = bpy.context.scene
    scene.render.engine = "CYCLES"
    prefs = bpy.context.preferences.addons["cycles"].preferences
    prefs.compute_device_type = "OPTIX"
    prefs.get_devices()
    for d in prefs.devices:
        d.use = d.type == "OPTIX"
    scene.cycles.device = "GPU"
    scene.cycles.samples = 24
    highs = [o for o in scene.objects if o.type == "MESH" and o.name != "Земля"]
    sources = [o for o in highs if is_low_source(o)]
    print("LOW_SOURCES", len(sources), "of", len(highs))
    low = make_low(sources)
    print("LOW_TRIS", tris(low))
    unwrap(low)
    bake_mat = bpy.data.materials.new("Запекание")
    bake_mat.use_nodes = True
    low.data.materials.clear()
    low.data.materials.append(bake_mat)
    paths = {
        "color": bake(low, highs, "DIFFUSE", "hero_color", "sRGB"),
        "normal": bake(low, highs, "NORMAL", "hero_normal", "Non-Color"),
        "roughness": bake(low, highs, "ROUGHNESS", "hero_roughness", "Non-Color"),
    }
    game_material(low, paths)
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
    out = os.path.join(OUT_DIR, "hero.glb")
    bpy.ops.export_scene.gltf(filepath=out, export_format="GLB", use_selection=True, export_apply=False,
                              export_skins=True, export_animations=False, export_yup=True)
    bpy.ops.wm.save_as_mainfile(filepath=os.path.join(TEX_DIR, "hero_game.blend"))
    print("HERO_EXPORTED", out, "tris", tris(low), "bones", len(BONES))


main()
