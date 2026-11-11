"""Build the 3D hero (docs/CHARACTER_3D_PLAN.md) in Blender from code.

The look follows game/assets/hero/pioneer/reference-v2.png: a rounded mustard
cube head with a side strap, green jacket with a hood collar, pocket and a
crossing strap, dark cargo pants with knee patches, hiking boots and a leather
backpack with a rolled mat and a thermos.

Version 2.0: the large forms (jacket, sleeves, gloves, pants, boots, the
pack) are lofts, rings of points along a spine joined into a clean quad cage
and subdivided, so each silhouette is drawn on purpose and the edge loops run
round the limbs. Straps are ribbons laid on the part's surface, pockets and
flaps are thin sheets pressed onto it, so details sit flush. Materials are
procedural (fabric weave, leather grain, worn paint, brushed metal);
export_showcase.py bakes them into the vertices.

Units: hero height 1.0, origin between the feet, the hero looks along +X,
the camera side (near side) is -Y, Z is up.

Run: blender --background --python tools/blender/build_hero.py -- [--render] [--out=<dir>]
"""
import math
import os
import sys

import bmesh
import bpy
from mathutils import Matrix, Vector

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
OUT = os.path.join(ROOT, "docs", "character", "3d")
VOXEL = 0.0045  # Remesh detail; smaller is smoother and heavier.

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import hero_joints as HJ  # noqa: E402  The joints, shared with the skeleton (export_hero.py).


# ---------------------------------------------------------------- scene

def reset():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    scene = bpy.context.scene
    scene.unit_settings.system = "METRIC"
    return scene


def link(obj, collection=None):
    (collection or bpy.context.scene.collection).objects.link(obj)
    return obj


def active(obj):
    bpy.ops.object.select_all(action="DESELECT")
    obj.select_set(True)
    bpy.context.view_layer.objects.active = obj


def apply_all(obj):
    active(obj)
    for mod in list(obj.modifiers):
        bpy.ops.object.modifier_apply(modifier=mod.name)
    bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)


# ---------------------------------------------------------------- materials

def node_tree(mat):
    mat.use_nodes = True
    nt = mat.node_tree
    for n in list(nt.nodes):
        nt.nodes.remove(n)
    out = nt.nodes.new("ShaderNodeOutputMaterial")
    bsdf = nt.nodes.new("ShaderNodeBsdfPrincipled")
    nt.links.new(bsdf.outputs["BSDF"], out.inputs["Surface"])
    return nt, bsdf


def noise(nt, scale, detail=6.0, rough=0.6, coords=None):
    n = nt.nodes.new("ShaderNodeTexNoise")
    n.inputs["Scale"].default_value = scale
    n.inputs["Detail"].default_value = detail
    n.inputs["Roughness"].default_value = rough
    if coords is not None:
        nt.links.new(coords, n.inputs["Vector"])
    return n


def ramp(nt, src, a, b, lo=0.35, hi=0.65):
    r = nt.nodes.new("ShaderNodeValToRGB")
    r.color_ramp.elements[0].position = lo
    r.color_ramp.elements[0].color = (*a, 1)
    r.color_ramp.elements[1].position = hi
    r.color_ramp.elements[1].color = (*b, 1)
    nt.links.new(src, r.inputs["Fac"])
    return r


def bump(nt, height, strength, distance=0.002, normal=None):
    b = nt.nodes.new("ShaderNodeBump")
    b.inputs["Strength"].default_value = strength
    b.inputs["Distance"].default_value = distance
    nt.links.new(height, b.inputs["Height"])
    if normal is not None:
        nt.links.new(normal, b.inputs["Normal"])
    return b


def srgb(hex_color):
    h = hex_color.lstrip("#")
    c = [int(h[i:i + 2], 16) / 255 for i in (0, 2, 4)]
    return tuple(x / 12.92 if x <= 0.04045 else ((x + 0.055) / 1.055) ** 2.4 for x in c)


def mix_rgb(nt, blend, a, b, factor):
    """Mix two colour sockets; `factor` is a socket or a number."""
    m = nt.nodes.new("ShaderNodeMix")
    m.data_type = "RGBA"
    m.blend_type = blend
    if isinstance(factor, (int, float)):
        m.inputs[0].default_value = factor
    else:
        nt.links.new(factor, m.inputs[0])
    nt.links.new(a, m.inputs[6])
    if isinstance(b, tuple):
        m.inputs[7].default_value = (*b, 1)
    else:
        nt.links.new(b, m.inputs[7])
    return m.outputs[2]


def weather(nt, bsdf, color, edge=None, edge_amount=0.0, grime=0.55, edge_lo=0.57, edge_hi=0.65):
    """Grime in the creases (ambient occlusion) and lighter worn edges
    (mesh pointiness): what makes a toy look used and real. Pointiness of a
    rounded surface sits just above 0.5 everywhere, so the wear ramp starts
    well above it; otherwise wear covers the whole part and greys it."""
    ao = nt.nodes.new("ShaderNodeAmbientOcclusion")
    ao.inputs["Distance"].default_value = 0.025
    ao.samples = 8
    cavity = ramp(nt, ao.outputs["AO"], (1 - grime,) * 3, (1, 1, 1), 0.15, 0.85)
    color = mix_rgb(nt, "MULTIPLY", color, cavity.outputs["Color"], 1.0)
    if edge is not None and edge_amount > 0:
        geo = nt.nodes.new("ShaderNodeNewGeometry")
        wear_noise = noise(nt, 60.0, 4, 0.7)
        e = ramp(nt, geo.outputs["Pointiness"], (0, 0, 0), (1, 1, 1), edge_lo, edge_hi)
        mask = nt.nodes.new("ShaderNodeMath")
        mask.operation = "MULTIPLY"
        nt.links.new(e.outputs["Color"], mask.inputs[0])
        nt.links.new(wear_noise.outputs["Fac"], mask.inputs[1])
        k = nt.nodes.new("ShaderNodeMath")
        k.operation = "MULTIPLY"
        k.inputs[1].default_value = edge_amount * 2.2
        nt.links.new(mask.outputs["Value"], k.inputs[0])
        color = mix_rgb(nt, "MIX", color, srgb(edge), k.outputs["Value"])
    nt.links.new(color, bsdf.inputs["Base Color"])


def fabric(name, light, dark, weave=900.0, sheen=0.35):
    """Woven cloth: colour mottling, a fine weave bump and soft sheen."""
    mat = bpy.data.materials.new(name)
    nt, bsdf = node_tree(mat)
    coords = nt.nodes.new("ShaderNodeTexCoord").outputs["Object"]
    mottle = noise(nt, 9.0, 8, 0.55, coords)
    col = ramp(nt, mottle.outputs["Fac"], srgb(dark), srgb(light), 0.3, 0.7)
    # Worn, sun-faded patches like v2's canvas: a lighter, yellower tone.
    faded = noise(nt, 3.5, 5, 0.6, coords)
    fk = ramp(nt, faded.outputs["Fac"], (0, 0, 0), (0.3, 0.3, 0.3), 0.58, 0.74)
    c = mix_rgb(nt, "MIX", col.outputs["Color"], srgb(light), fk.outputs["Color"])
    c = mix_rgb(nt, "SCREEN", c, (0.06, 0.05, 0.0), fk.outputs["Color"])
    weather(nt, bsdf, c, light, 0.25, grime=0.6)
    wave_a = nt.nodes.new("ShaderNodeTexWave")
    wave_a.inputs["Scale"].default_value = weave
    wave_a.bands_direction = "X"
    wave_b = nt.nodes.new("ShaderNodeTexWave")
    wave_b.inputs["Scale"].default_value = weave
    wave_b.bands_direction = "Z"
    for w in (wave_a, wave_b):
        nt.links.new(coords, w.inputs["Vector"])
    mix = nt.nodes.new("ShaderNodeMath")
    mix.operation = "MULTIPLY"
    nt.links.new(wave_a.outputs["Fac"], mix.inputs[0])
    nt.links.new(wave_b.outputs["Fac"], mix.inputs[1])
    wrinkle = noise(nt, 38.0, 4, 0.5, coords)
    canvas = noise(nt, 260.0, 3, 0.55, coords)  # Coarse canvas grain, visible at game size.
    b1 = bump(nt, mix.outputs["Value"], 0.3, 0.0008)
    b1b = bump(nt, canvas.outputs["Fac"], 0.35, 0.0012, b1.outputs["Normal"])
    b2 = bump(nt, wrinkle.outputs["Fac"], 0.25, 0.004, b1b.outputs["Normal"])
    nt.links.new(b2.outputs["Normal"], bsdf.inputs["Normal"])
    bsdf.inputs["Roughness"].default_value = 0.88
    bsdf.inputs["Sheen Weight"].default_value = sheen
    return mat


def leather(name, light, dark, grain=420.0, rough=0.55):
    mat = bpy.data.materials.new(name)
    nt, bsdf = node_tree(mat)
    coords = nt.nodes.new("ShaderNodeTexCoord").outputs["Object"]
    wear = noise(nt, 7.0, 10, 0.65, coords)
    col = ramp(nt, wear.outputs["Fac"], srgb(dark), srgb(light), 0.32, 0.68)
    # Suede-like mottling: dark smudges and light rubbed spots, as on v2's boots.
    smudge = noise(nt, 26.0, 8, 0.7, coords)
    dk = ramp(nt, smudge.outputs["Fac"], (0, 0, 0), (0.55, 0.55, 0.55), 0.56, 0.7)
    c = mix_rgb(nt, "MIX", col.outputs["Color"], srgb(dark), dk.outputs["Color"])
    lk = ramp(nt, smudge.outputs["Fac"], (0.35, 0.35, 0.35), (0, 0, 0), 0.26, 0.38)
    c = mix_rgb(nt, "SCREEN", c, (0.18, 0.12, 0.07), lk.outputs["Color"])
    weather(nt, bsdf, c, light, 0.6, grime=0.65)
    vor = nt.nodes.new("ShaderNodeTexVoronoi")
    vor.inputs["Scale"].default_value = grain
    nt.links.new(coords, vor.inputs["Vector"])
    b = bump(nt, vor.outputs["Distance"], 0.35, 0.0008)
    nt.links.new(b.outputs["Normal"], bsdf.inputs["Normal"])
    r = ramp(nt, wear.outputs["Fac"], (rough + .15,) * 3, (rough - .15,) * 3)
    nt.links.new(r.outputs["Color"], bsdf.inputs["Roughness"])
    return mat


def painted(name, color, worn, deep):
    """The cube head: thick worn paint like v2.

    Uneven tone (deeper orange in broad patches), an orange-peel surface,
    small dark pits, light scratches and chipped lighter edges. Little clear
    coat: a strong coat turns the orange pale.
    """
    mat = bpy.data.materials.new(name)
    nt, bsdf = node_tree(mat)
    coords = nt.nodes.new("ShaderNodeTexCoord").outputs["Object"]
    tone = noise(nt, 5.0, 4, 0.55, coords)
    col = ramp(nt, tone.outputs["Fac"], srgb(deep), srgb(color), 0.35, 0.62)
    scuff = noise(nt, 22.0, 12, 0.75, coords)
    sc = ramp(nt, scuff.outputs["Fac"], (0, 0, 0), (0.7, 0.7, 0.7), 0.72, 0.8)
    c = mix_rgb(nt, "MIX", col.outputs["Color"], srgb(worn), sc.outputs["Color"])
    speck = noise(nt, 45.0, 8, 0.65, coords)
    darker = ramp(nt, speck.outputs["Fac"], (0, 0, 0), (0.55, 0.55, 0.55), 0.56, 0.7)
    c = mix_rgb(nt, "MIX", c, srgb("#D27A08"), darker.outputs["Color"])
    lighter = ramp(nt, speck.outputs["Fac"], (0.45, 0.45, 0.45), (0, 0, 0), 0.3, 0.42)
    c = mix_rgb(nt, "MIX", c, srgb("#FFC84A"), lighter.outputs["Color"])
    # Pits: tiny dark dots in the paint.
    pits = nt.nodes.new("ShaderNodeTexVoronoi")
    pits.inputs["Scale"].default_value = 95.0
    nt.links.new(coords, pits.inputs["Vector"])
    pit = ramp(nt, pits.outputs["Distance"], (1, 1, 1), (0, 0, 0), 0.05, 0.13)
    pk = nt.nodes.new("ShaderNodeMath")
    pk.operation = "MULTIPLY"
    pk.inputs[1].default_value = 0.55
    nt.links.new(pit.outputs["Color"], pk.inputs[0])
    c = mix_rgb(nt, "MIX", c, srgb("#8C4A10"), pk.outputs["Value"])
    # Fine scratches: stretched noise, lighter paint showing through.
    scratch_map = nt.nodes.new("ShaderNodeMapping")
    scratch_map.inputs["Scale"].default_value = (1, 18, 1)
    nt.links.new(coords, scratch_map.inputs["Vector"])
    scratch = noise(nt, 40.0, 2, 0.5, scratch_map.outputs["Vector"])
    sr = ramp(nt, scratch.outputs["Fac"], (0, 0, 0), (1, 1, 1), 0.69, 0.735)
    k = nt.nodes.new("ShaderNodeMath")
    k.operation = "MULTIPLY"
    k.inputs[1].default_value = 0.6
    nt.links.new(sr.outputs["Color"], k.inputs[0])
    c = mix_rgb(nt, "MIX", c, srgb("#BDB3A3"), k.outputs["Value"])
    weather(nt, bsdf, c, "#CDBFA6", 0.6, grime=0.3, edge_lo=0.58, edge_hi=0.66)
    # Orange peel plus the pits in the relief.
    peel = noise(nt, 55.0, 6, 0.62, coords)
    b1 = bump(nt, peel.outputs["Fac"], 0.55, 0.002)
    b2 = bump(nt, pits.outputs["Distance"], 0.25, 0.0006, b1.outputs["Normal"])
    nt.links.new(b2.outputs["Normal"], bsdf.inputs["Normal"])
    rough = ramp(nt, scuff.outputs["Fac"], (0.42,) * 3, (0.62,) * 3, 0.5, 0.75)
    nt.links.new(rough.outputs["Color"], bsdf.inputs["Roughness"])
    bsdf.inputs["Coat Weight"].default_value = 0.08
    bsdf.inputs["Coat Roughness"].default_value = 0.4
    return mat


def plain(name, color, rough, metal=0.0, coat=0.0, grime=0.5):
    mat = bpy.data.materials.new(name)
    nt, bsdf = node_tree(mat)
    rgb = nt.nodes.new("ShaderNodeRGB")
    rgb.outputs[0].default_value = (*srgb(color), 1)
    weather(nt, bsdf, rgb.outputs[0], grime=grime)
    bsdf.inputs["Roughness"].default_value = rough
    bsdf.inputs["Metallic"].default_value = metal
    bsdf.inputs["Coat Weight"].default_value = coat
    return mat


def emissive(name, color, strength):
    mat = plain(name, color, 0.2)
    bsdf = next(n for n in mat.node_tree.nodes if n.type == "BSDF_PRINCIPLED")
    bsdf.inputs["Emission Color"].default_value = (*srgb(color), 1)
    bsdf.inputs["Emission Strength"].default_value = strength
    return mat


def materials():
    return {
        "head": painted("Голова", "#F7A616", "#C8B89C", "#EC960E"),
        "eye": plain("Глаз", "#120D0B", 0.38, coat=0.25),  # Soft gloss: a mirror coat reflected the scene like glass.
        "glint": emissive("Блик", "#FFFFFF", 6.0),
        "jacket": fabric("Куртка", "#646A30", "#363916", weave=700),
        "jacket_dark": fabric("Куртка тень", "#4E5324", "#2B2D12", weave=700),
        "pants": fabric("Штаны", "#46342A", "#20160F", weave=800, sheen=0.25),
        "patch": leather("Наколенник", "#B98A55", "#7A5530", grain=300),
        "leather": leather("Кожа", "#A8622C", "#5E3416"),
        "strap": leather("Ремень", "#9A5526", "#5A2F12", grain=500),
        "glove": leather("Перчатка", "#5E4237", "#2C1E19", grain=380, rough=0.7),
        "boot": leather("Ботинок", "#C8703A", "#6E3418", grain=300),
        "thread": plain("Нитка", "#D9B47A", 0.8),
        "thread_dark": plain("Нитка тёмная", "#3C4520", 0.85),
        "thread_pants": plain("Нитка брюк", "#6E5646", 0.85),
        "sole": plain("Подошва", "#2B241F", 0.85),
        "welt": leather("Рант", "#5C3A22", "#2E1C10", grain=500),
        "lace": plain("Шнурок", "#8A4E22", 0.7),
        "metal": plain("Металл", "#C9C4BA", 0.3, metal=1.0),
        "mat": fabric("Коврик", "#7C8E55", "#4F5E33", weave=500),
        "thermos": painted("Термос", "#4F7E5A", "#B8B6AA", "#3C6447"),
        "skin": painted("Шея", "#E8900F", "#F2B848", "#C86A08"),
    }


# ---------------------------------------------------------------- shapes

def cube(size, loc, rot=(0, 0, 0)):
    bpy.ops.mesh.primitive_cube_add(size=1, location=loc, rotation=rot)
    obj = bpy.context.active_object
    obj.scale = size
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    return obj


def ball(radius, loc, scale=(1, 1, 1), segments=32):
    bpy.ops.mesh.primitive_uv_sphere_add(segments=segments, ring_count=segments // 2, radius=radius, location=loc)
    obj = bpy.context.active_object
    obj.scale = scale
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    return obj


def rod(p1, p2, r1, r2=None, vertices=32):
    """A tapered cylinder from p1 to p2 with rounded ends."""
    p1, p2 = Vector(p1), Vector(p2)
    r2 = r1 if r2 is None else r2
    d = p2 - p1
    bpy.ops.mesh.primitive_cone_add(vertices=vertices, radius1=r1, radius2=r2, depth=d.length, location=(p1 + p2) / 2,
                                    rotation=Vector((0, 0, 1)).rotation_difference(d.normalized()).to_euler())
    seg = max(12, min(32, vertices))  # End caps as fine as the tube (a lace needs no 32-segment balls).
    parts = [bpy.context.active_object, ball(r1, p1, segments=seg), ball(r2, p2, segments=seg)]
    return join(parts)


def torus(major, minor, loc, rot=(0, 0, 0), scale=(1, 1, 1), segments=48, rings=16):
    bpy.ops.mesh.primitive_torus_add(major_radius=major, minor_radius=minor, location=loc, rotation=rot,
                                     major_segments=segments, minor_segments=rings)
    obj = bpy.context.active_object
    obj.scale = scale
    bpy.ops.object.transform_apply(location=False, rotation=True, scale=True)
    return obj


def rounded(size, loc, radius, rot=(0, 0, 0), segments=5):
    """A box with rounded edges (bevel applied)."""
    obj = cube(size, loc, rot)
    mod = obj.modifiers.new("bevel", "BEVEL")
    mod.width = radius
    mod.segments = segments
    mod.limit_method = "NONE"
    apply_all(obj)
    return obj


def join(objs):
    objs = [o for o in objs if o is not None]
    bpy.ops.object.select_all(action="DESELECT")
    for o in objs:
        o.select_set(True)
    bpy.context.view_layer.objects.active = objs[0]
    bpy.ops.object.join()
    return bpy.context.active_object


def fuse(objs, name, mat, voxel=VOXEL, smooth=6, crease=None):
    """Join solids and remesh them into one seamless surface."""
    obj = join(objs)
    obj.name = name
    mod = obj.modifiers.new("remesh", "REMESH")
    mod.mode = "VOXEL"
    mod.voxel_size = voxel
    mod.use_smooth_shade = True
    sm = obj.modifiers.new("smooth", "CORRECTIVE_SMOOTH")
    sm.iterations = smooth
    sm.smooth_type = "LENGTH_WEIGHTED"
    sm.use_only_smooth = True
    apply_all(obj)
    finish(obj, mat)
    return obj


def finish(obj, mat, name=None):
    """Material, smooth shading and transforms baked into the mesh, so local
    coordinates are world coordinates (closest_point_on_mesh works in local)."""
    if name:
        obj.name = name
    active(obj)
    bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
    obj.data.materials.clear()
    obj.data.materials.append(mat)
    for poly in obj.data.polygons:
        poly.use_smooth = True
    return obj


def cloth_relief(obj, strength=0.0025, size=0.035):
    """Soft fabric lumps so cloth never looks like plastic."""
    tex = bpy.data.textures.new(obj.name + " складки", "CLOUDS")
    tex.noise_scale = size
    tex.noise_depth = 2
    mod = obj.modifiers.new("relief", "DISPLACE")
    mod.texture = tex
    mod.strength = strength
    mod.mid_level = 0.5
    mod.texture_coords = "GLOBAL"
    apply_all(obj)


def folds(obj, centre, axis, count, spacing, depth, radius):
    """Ring folds (sleeve at the elbow, trousers behind the knee): pinch the
    surface inward along thin bands across `axis` around `centre`."""
    centre, axis = Vector(centre), Vector(axis).normalized()
    for v in obj.data.vertices:
        rel = v.co - centre
        along = rel.dot(axis)
        if abs(along) > radius:
            continue
        side = rel - axis * along
        if side.length < 1e-6:
            continue
        band = 0.5 + 0.5 * math.cos(along / spacing * math.pi * 2)
        fade = 0.5 + 0.5 * math.cos(along / radius * math.pi)
        # Folds bunch on the inner side of the bend (+X for the elbow).
        v.co -= side.normalized() * depth * band * fade
    obj.data.update()


def drape(obj, axis, wavelength, depth, centre, radius, seed=0.0):
    """Soft cloth folds: waves across `axis`, pushed along vertex normals,
    fading out at `radius` from `centre`; the phase wanders so folds are
    uneven like real cloth."""
    axis, centre = Vector(axis).normalized(), Vector(centre)
    mesh = obj.data
    for v in mesh.vertices:
        rel = v.co - centre
        dist = rel.length
        if dist > radius:
            continue
        fade = 0.5 + 0.5 * math.cos(dist / radius * math.pi)
        wander = math.sin(v.co.x * 41.0 + seed) * 1.3 + math.sin(v.co.y * 37.0 + seed * 2) * 1.1
        wave = math.sin(rel.dot(axis) / wavelength * math.tau + wander)
        v.co += v.normal * depth * wave * fade
    mesh.update()


def oval_patch(target, centre, rx, rz, thick, mat, name, lift=0.0015, rings=6, segments=32):
    """A padded oval piece (knee patch) wrapped onto the target's surface.
    Returns the patch and a rim path just inside its edge for stitching."""
    ok, c, n, _ = target.closest_point_on_mesh(Vector(centre))
    up = Vector((0, 0, 1))
    side = n.cross(up).normalized()
    up = side.cross(n).normalized()
    bm = bmesh.new()
    centre_v = bm.verts.new(c + n * 0.01)
    prev = None
    rings_v = []
    for r in range(1, rings + 1):
        k = r / rings
        ring = [bm.verts.new(c + n * 0.01 + side * math.cos(a) * rx * k + up * math.sin(a) * rz * k)
                for a in [i / segments * math.tau for i in range(segments)]]
        rings_v.append(ring)
    for i in range(segments):
        bm.faces.new((centre_v, rings_v[0][i], rings_v[0][(i + 1) % segments]))
    for a_ring, b_ring in zip(rings_v, rings_v[1:]):
        for i in range(segments):
            j = (i + 1) % segments
            bm.faces.new((a_ring[i], b_ring[i], b_ring[j], a_ring[j]))
    mesh = bpy.data.meshes.new(name)
    bm.to_mesh(mesh)
    bm.free()
    obj = link(bpy.data.objects.new(name, mesh))

    def drop(p):
        """Straight down the patch's normal onto the surface: the oval keeps
        its shape (nearest-point wrapping folded it over the knee's folds)."""
        hit, loc, nn, _ = target.ray_cast(p + n * 0.05, -n, distance=0.2)
        return (loc + nn * lift) if hit else p
    for v in obj.data.vertices:
        v.co = drop(v.co)
    obj.data.update()
    solid = obj.modifiers.new("solid", "SOLIDIFY")
    solid.thickness = thick
    solid.offset = 1
    bev = obj.modifiers.new("bevel", "BEVEL")
    bev.width = thick * 0.45
    bev.segments = 2
    sub = obj.modifiers.new("sub", "SUBSURF")
    sub.levels = 2
    apply_all(obj)
    finish(obj, mat)
    rim = [drop(c + side * math.cos(a) * rx * 0.8 + up * math.sin(a) * rz * 0.8) + n * thick
           for a in [i / 64 * math.tau for i in range(65)]]
    return obj, rim


def band(target, path, width, thick, mat, name, lift=0.002):
    """A strap: a flat ribbon laid along `path` on the target's surface."""
    pts = []
    for p in path:
        ok, loc, normal, _ = target.closest_point_on_mesh(Vector(p))
        pts.append((loc + normal * lift, normal))
    # Resample so the ribbon is smooth.
    bm = bmesh.new()
    rows = []
    across = 5
    for i, (p, n) in enumerate(pts):
        t = (pts[min(i + 1, len(pts) - 1)][0] - pts[max(i - 1, 0)][0]).normalized()
        side = n.cross(t).normalized() * width / 2
        rows.append([bm.verts.new(p + side * (2 * k / (across - 1) - 1)) for k in range(across)])
    for a, b in zip(rows, rows[1:]):
        for k in range(across - 1):
            bm.faces.new((a[k], a[k + 1], b[k + 1], b[k]))
    mesh = bpy.data.meshes.new(name)
    bm.to_mesh(mesh)
    obj = link(bpy.data.objects.new(name, mesh))
    wrap = obj.modifiers.new("wrap", "SHRINKWRAP")
    wrap.target = target
    wrap.wrap_method = "NEAREST_SURFACEPOINT"
    wrap.offset = lift
    solid = obj.modifiers.new("solid", "SOLIDIFY")
    solid.thickness = thick
    solid.offset = 1
    bev = obj.modifiers.new("bevel", "BEVEL")
    bev.width = thick * 0.45
    bev.segments = 2
    sub = obj.modifiers.new("sub", "SUBSURF")
    sub.levels = 1
    apply_all(obj)
    finish(obj, mat)
    return obj


def stitches(target, path, mat, name, spacing=0.0085, length=0.0055, radius=0.0012, lift=0.0012, offset=0.0):
    """Dashed seam along `path` on the target's surface: one mesh of small
    capsules, `offset` to the side of the line (to follow a strap edge)."""
    pts = []
    for p in path:
        ok, loc, n, _ = target.closest_point_on_mesh(Vector(p))
        pts.append((loc, n.normalized()))
    bm = bmesh.new()
    walked, next_at = 0.0, spacing / 2
    for (a, na), (b, nb) in zip(pts, pts[1:]):
        seg = b - a
        seg_len = seg.length
        if seg_len < 1e-7:
            continue
        t = seg / seg_len
        while next_at <= walked + seg_len:
            k = (next_at - walked) / seg_len
            loc = a.lerp(b, k)
            n = na.lerp(nb, k).normalized()
            x = (t - n * t.dot(n)).normalized()
            y = n.cross(x)
            basis = Matrix((x, y, n)).transposed()
            pos = loc + n * (lift + radius * 0.5) + y * offset
            m = Matrix.Translation(pos) @ basis.to_4x4() @ Matrix.Diagonal((length / 2, radius, radius, 1))
            bmesh.ops.create_uvsphere(bm, u_segments=8, v_segments=5, radius=1.0, matrix=m)
            next_at += spacing
        walked += seg_len
    mesh = bpy.data.meshes.new(name)
    bm.to_mesh(mesh)
    bm.free()
    obj = link(bpy.data.objects.new(name, mesh))
    return finish(obj, mat)


def band_edges(target, strap, path, width, mat, name, inset=0.004, **kw):
    """Stitches along both edges of a strap laid with band() on target."""
    outside = []
    for p in path:
        ok, loc, n, _ = target.closest_point_on_mesh(Vector(p))
        outside.append(loc + n * 0.012)
    return [stitches(strap, outside, mat, name, lift=0.0003, offset=side * (width / 2 - inset), **kw) for side in (-1, 1)]


def surface_path(target, start, end, steps=24, bulge=None):
    """Points between start and end, pushed onto the target's surface."""
    pts = []
    for i in range(steps + 1):
        t = i / steps
        p = Vector(start).lerp(Vector(end), t)
        if bulge:
            p += Vector(bulge) * math.sin(t * math.pi)
        pts.append(p)
    return pts


def ring_path(centre, radius_y, radius_x, z_axis=(0, 0, 1), steps=48):
    c = Vector(centre)
    return [c + Vector((math.cos(a) * radius_x, math.sin(a) * radius_y, 0))
            for a in [i / steps * math.tau for i in range(steps + 1)]]


def buckle(loc, normal, size, mat_metal, mat_strap, name, along=None):
    """A square metal buckle frame facing `normal`, square to its strap:
    `along` is the strap's direction (default: level round the part)."""
    n = Vector(normal).normalized()
    a = Vector(along) if along is not None else n.cross(Vector((0, 0, 1)))
    if a.length < 1e-6:
        a = Vector((1, 0, 0))
    x = (a - n * a.dot(n)).normalized()
    rot = Matrix((x, n.cross(x), n)).transposed().to_euler()
    frame = rounded((size, size * 1.15, size * 0.18), loc, size * 0.12, rot)
    hole = cube((size * 0.62, size * 0.78, size), loc, rot)
    mod = frame.modifiers.new("hole", "BOOLEAN")
    mod.object = hole
    mod.operation = "DIFFERENCE"
    apply_all(frame)
    bpy.data.objects.remove(hole)
    finish(frame, mat_metal, name)
    return frame


# ---------------------------------------------------------------- lofts
# Version 2.0 builds the large forms as lofts: rings of points along a spine,
# joined into a clean quad cage and smoothed by subdivision. Unlike the fused
# primitives of the first model, the silhouette is drawn on purpose (shoulder
# slope, waist, chest, a knee, a heel), edge loops run around the limbs, so
# elbows and knees bend cleanly, and the loft carries real UVs (metres along
# and around the surface) for the game's tiling fabric and leather detail.


def lerp(a, b, t):
    return a + (b - a) * t


def smooth01(t):
    t = min(1.0, max(0.0, t))
    return t * t * (3 - 2 * t)


def catmull(p0, p1, p2, p3, t):
    t2, t3 = t * t, t * t * t
    return 0.5 * ((2 * p1) + (-p0 + p2) * t + (2 * p0 - 5 * p1 + 4 * p2 - p3) * t2 + (-p0 + 3 * p1 - 3 * p2 + p3) * t3)


def profile(rows, steps):
    """Smooth rows of numbers (each row a tuple) through Catmull-Rom: the
    silhouette passes exactly through every row without kinks."""
    out = []
    n = len(rows)
    for i in range(n - 1):
        r0, r1, r2, r3 = rows[max(i - 1, 0)], rows[i], rows[i + 1], rows[min(i + 2, n - 1)]
        for s in range(steps):
            t = s / steps
            out.append(tuple(catmull(a, b, c, d, t) for a, b, c, d in zip(r0, r1, r2, r3)))
    out.append(tuple(rows[-1]))
    return out


def sring(c, u, v, n, a_pos, a_neg, b_pos, b_neg, p=2.0, phase=0.0):
    """A ring of n points: a superellipse (p=2 an ellipse, higher squarer)
    with its own radius on each of the four sides (front, back, two sides)."""
    pts = []
    for i in range(n):
        t = phase + i / n * math.tau
        cs, sn = math.cos(t), math.sin(t)
        x = math.copysign(abs(cs) ** (2 / p), cs)
        y = math.copysign(abs(sn) ** (2 / p), sn)
        pts.append(Vector(c) + Vector(u) * x * (a_pos if x >= 0 else a_neg) + Vector(v) * y * (b_pos if y >= 0 else b_neg))
    return pts


def transport_frames(path, up):
    """Frames along a path (parallel transport): tangent, and two axes across
    that turn no more than the path does (no twisting)."""
    path = [Vector(p) for p in path]
    n = len(path)
    tangents = [(path[min(i + 1, n - 1)] - path[max(i - 1, 0)]).normalized() for i in range(n)]
    u = (Vector(up) - tangents[0] * Vector(up).dot(tangents[0])).normalized()
    frames = []
    for i, t in enumerate(tangents):
        if i > 0:
            u = tangents[i - 1].rotation_difference(t) @ u
            u = (u - t * u.dot(t)).normalized()
        frames.append((t, u, t.cross(u)))
    return frames


def loft(name, rings, mat, cap_start=False, cap_end=False, closed=False, levels=2, crease_caps=False):
    """A quad cage from rings of equal length, subdivided. UV: metres around
    (u) and along (v), so tiling detail keeps one size everywhere."""
    n = len(rings[0])
    bm = bmesh.new()
    uv_layer = bm.loops.layers.uv.new("detail")
    grid = [[bm.verts.new(p) for p in ring] for ring in rings]
    # Along: distance between ring centres; around: arc length per ring.
    centres = [sum(r, Vector()) / n for r in rings]
    along = [0.0]
    for a, b in zip(centres, centres[1:]):
        along.append(along[-1] + (b - a).length)
    around = []
    for ring in rings:
        acc = [0.0]
        for i in range(n):
            acc.append(acc[-1] + (ring[(i + 1) % n] - ring[i]).length)
        around.append(acc)
    count = len(rings)
    pairs = list(zip(range(count - 1), range(1, count)))
    if closed:
        pairs.append((count - 1, 0))
    for ia, ib in pairs:
        va = along[ia]
        vb = along[ib] if ib != 0 else along[-1] + (centres[0] - centres[-1]).length
        for i in range(n):
            j = (i + 1) % n
            f = bm.faces.new((grid[ia][i], grid[ia][j], grid[ib][j], grid[ib][i]))
            uvs = ((around[ia][i], va), (around[ia][i + 1], va), (around[ib][i + 1], vb), (around[ib][i], vb))
            for loop, uv in zip(f.loops, uvs):
                loop[uv_layer].uv = uv
    caps = []
    for flag, index, sign in ((cap_start, 0, -1), (cap_end, count - 1, 1)):
        if not flag:
            continue
        ring = grid[index]
        inner = rings[index]
        centre = sum(inner, Vector()) / n
        mid = bm.verts.new(centre)
        for i in range(n):
            j = (i + 1) % n
            verts = (ring[j], ring[i], mid) if sign < 0 else (ring[i], ring[j], mid)
            f = bm.faces.new(verts)
            for loop in f.loops:
                p = loop.vert.co - centre
                loop[uv_layer].uv = (p.x + p.y * 0.7, p.z + p.y * 0.7)
            caps.append(f)
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    mesh = bpy.data.meshes.new(name)
    bm.to_mesh(mesh)
    bm.free()
    obj = link(bpy.data.objects.new(name, mesh))
    if levels:
        sub = obj.modifiers.new("sub", "SUBSURF")
        sub.levels = levels
        sub.render_levels = levels
        sub.uv_smooth = "PRESERVE_BOUNDARIES"
        apply_all(obj)
    return finish(obj, mat)


def cap_rings(c, axis, u, v, r_a, r_b, n, steps=4, p=2.0, end=1.0):
    """Rings closing a tube end into a dome (a hemisphere scaled by `end`
    along the axis), from the full ring at c outward along axis."""
    out = []
    for k in range(1, steps + 1):
        phi = k / (steps + 0.6) * math.pi / 2
        s = math.cos(phi)
        out.append(sring(Vector(c) + Vector(axis) * math.sin(phi) * end * max(r_a, r_b), u, v, n,
                         r_a * s, r_a * s, r_b * s, r_b * s, p))
    return out


def displace_along_normals(obj, fn):
    """Moves each vertex along its normal by fn(co, normal)."""
    mesh = obj.data
    mesh.update()
    moves = [(v.index, v.normal.copy() * fn(v.co, v.normal)) for v in mesh.vertices]
    for i, d in moves:
        mesh.vertices[i].co += d
    mesh.update()


def union_copy(objs, name="Цель"):
    """One temporary mesh of copies of objs: a strap laid from outside lands
    on whichever surface is outermost (a lid over the bag, a flap)."""
    copies = []
    for o in objs:
        c = o.copy()
        c.data = o.data.copy()
        link(c)
        copies.append(c)
    u = join(copies)
    u.name = name
    return u


def solid_sheet(name, grid_pts, thick, mat, levels=2, target=None, lift=0.0):
    """A cloth/leather sheet from a grid of points (rows x cols), thickened
    and subdivided: a lid, a flap, a pocket. Optionally pressed onto a
    target surface so it lies flush."""
    bm = bmesh.new()
    uv_layer = bm.loops.layers.uv.new("detail")
    rows = [[bm.verts.new(p) for p in row] for row in grid_pts]
    for r in range(len(rows) - 1):
        for c in range(len(rows[0]) - 1):
            f = bm.faces.new((rows[r][c], rows[r][c + 1], rows[r + 1][c + 1], rows[r + 1][c]))
            for loop, (rr, cc) in zip(f.loops, ((r, c), (r, c + 1), (r + 1, c + 1), (r + 1, c))):
                p = grid_pts[rr][cc]
                loop[uv_layer].uv = (cc * (grid_pts[0][1] - grid_pts[0][0]).length, rr * (grid_pts[1][0] - grid_pts[0][0]).length)
    mesh = bpy.data.meshes.new(name)
    bm.to_mesh(mesh)
    bm.free()
    obj = link(bpy.data.objects.new(name, mesh))
    if target is not None:
        wrap = obj.modifiers.new("wrap", "SHRINKWRAP")
        wrap.target = target
        wrap.wrap_method = "NEAREST_SURFACEPOINT"
        wrap.wrap_mode = "OUTSIDE_SURFACE"
        wrap.offset = lift
    solid = obj.modifiers.new("solid", "SOLIDIFY")
    solid.thickness = thick
    solid.offset = 1
    solid.use_even_offset = True
    bev = obj.modifiers.new("bevel", "BEVEL")
    bev.width = thick * 0.4
    bev.segments = 2
    bev.limit_method = "ANGLE"
    sub = obj.modifiers.new("sub", "SUBSURF")
    sub.levels = levels
    apply_all(obj)
    return finish(obj, mat)


# ---------------------------------------------------------------- parts

def build_head(M):
    top, h, d, w = HJ.HEAD_TOP, HJ.HEAD_TOP - HJ.HEAD_BOTTOM, 0.33, 0.278  # Height, depth along X, width along Y.
    cz = top - h / 2
    cx = 0.028
    # A rounded cube: bevelled cage, then subdivided; the faces stay a touch
    # domed (cloth_relief) like v2's thick paint.
    core = rounded((d, w, h), (cx, 0, cz), 0.07, segments=8)
    sub = core.modifiers.new("sub", "SUBSURF")
    sub.levels = 2
    apply_all(core)
    for v in core.data.vertices:  # Faces bulge a little: a soft toy block, not a box.
        p = v.co - Vector((cx, 0, cz))
        k = 1.0 + 0.035 * (1 - abs(p.x) / (d / 2)) * (1 - abs(p.y) / (w / 2)) * (1 - abs(p.z) / (h / 2)) * 4
        v.co = Vector((cx, 0, cz)) + Vector((p.x * (1 + (k - 1) * 0.3), p.y * (1 + (k - 1) * 0.3), p.z * (1 + (k - 1) * 0.25)))
    finish(core, M["head"], "Голова")
    cloth_relief(core, 0.0012, 0.06)
    ridge = rod((cx - 0.1, 0, top - 0.002), (cx + 0.065, 0, top - 0.002), 0.015, vertices=24)
    ridge.scale = (1, 1, 0.55)
    apply_all(ridge)
    finish(ridge, M["head"], "Ручка")
    eyes = []
    face_x = cx + d / 2
    for y in (-0.043, 0.043):
        ec = Vector((face_x - 0.004, y * 1.08, cz + 0.032))
        e = rod(ec - Vector((0, 0, 0.024)), ec + Vector((0, 0, 0.024)), 0.0215, vertices=32)
        e.scale = (0.3, 1, 1)
        apply_all(e)
        finish(e, M["eye"], "Глаз")
        g = ball(0.009, (face_x + 0.0048, y * 1.08 - 0.004, cz + 0.057), (0.4, 0.95, 1.35), 16)
        finish(g, M["glint"], "Блик")
        eyes += [e, g]
    strap_z = cz - 0.006
    path = [p for p in ring_path((cx, 0, strap_z), w / 2 + 0.02, d / 2 + 0.02, steps=96) if p.x < cx + d / 2 - 0.055]
    path.sort(key=lambda p: math.atan2(p.y, p.x - cx) % math.tau)
    strap = band(core, path, 0.042, 0.009, M["strap"], "Ремень головы", lift=0.0025)
    seams = band_edges(core, strap, path, 0.042, M["thread"], "Строчка ремня головы")
    hardware = []
    for s in (-1, 1):
        plate = rounded((0.1, 0.02, 0.088), (cx - 0.04, s * (w / 2 + 0.011), strap_z), 0.013)
        finish(plate, M["sole"], "Пластина")
        bk = buckle((cx - 0.035, s * (w / 2 + 0.024), strap_z), (0, s, 0), 0.056, M["metal"], M["strap"], "Пряжка головы")
        tab = rounded((0.046, 0.015, 0.064), (cx - 0.072, s * (w / 2 + 0.028), strap_z), 0.009)
        finish(tab, M["strap"], "Язычок")
        hardware += [plate, bk, tab]
    return [core, ridge, strap] + hardware + eyes + seams


# Jacket body, bottom to top: z, half width (Y), front depth, back depth,
# squareness, x offset. A real jacket: flared hem, waist, a chest that fills
# it out, sloping shoulders under the sleeve caps, a neck opening.
JACKET_ROWS = [
    (0.392, 0.134, 0.111, 0.104, 2.6, 0.006),
    (0.41, 0.133, 0.109, 0.102, 2.6, 0.005),
    (0.45, 0.127, 0.103, 0.097, 2.6, 0.003),
    (0.50, 0.115, 0.104, 0.095, 2.6, 0.003),
    (0.555, 0.11, 0.108, 0.097, 2.7, 0.004),
    (0.605, 0.116, 0.107, 0.099, 2.8, 0.002),
    (0.64, 0.12, 0.1, 0.097, 2.9, 0.0),
    (0.664, 0.116, 0.09, 0.09, 3.0, -0.002),
    (0.684, 0.1, 0.074, 0.078, 2.7, -0.004),
    (0.698, 0.062, 0.057, 0.062, 2.2, -0.006),
]


def jacket_ring(row, n=36):
    z, b, af, ab, p, xo = row
    return sring((xo, 0, z), (1, 0, 0), (0, 1, 0), n, af, ab, b, b, p, phase=math.pi)


def build_torso(M):
    rows = profile(JACKET_ROWS, 3)
    rings = [jacket_ring(r) for r in rows]
    # The hem has a thickness: the cloth turns inward and up a little.
    first = JACKET_ROWS[0]
    inner = (first[0] + 0.012, first[1] - 0.011, first[2] - 0.011, first[3] - 0.011, first[4], first[5])
    deep = (first[0] + 0.06, first[1] - 0.016, first[2] - 0.016, first[3] - 0.016, first[4], first[5])
    rings = [jacket_ring(deep), jacket_ring(inner)] + rings
    jacket = loft("Куртка", rings, M["jacket"], cap_start=True, cap_end=True)
    z0, z1 = JACKET_ROWS[0][0], JACKET_ROWS[-1][0]
    # Cloth: soft folds at the waist where the jacket gathers, and under the
    # arms; a padded quilting band across the chest.
    drape(jacket, (0, 0, 1), 0.03, 0.0035, (0.0, 0, z0 + 0.06), 0.13)
    drape(jacket, (0.5, 0, 1), 0.026, 0.003, (0.0, -0.1, 0.6), 0.07, seed=1.7)
    drape(jacket, (0.5, 0, 1), 0.026, 0.003, (0.0, 0.1, 0.6), 0.07, seed=3.1)
    cloth_relief(jacket, 0.0009, 0.06)
    # Hood folded into a soft collar: a tube round the neck, thick at the
    # back and thin at the front, where it opens over the zip.
    path = []
    tube = []
    for i in range(40):
        a = i / 40 * math.tau
        back = 0.5 - 0.5 * math.cos(a)  # 0 at the front (+X), 1 at the back.
        path.append(Vector((-0.012 + math.cos(a) * (0.064 + 0.012 * back), math.sin(a) * 0.072, z1 + 0.008 + 0.012 * back
                            - 0.006 * (1 - back))))
        tube.append((0.016 + 0.03 * back ** 0.8, 0.02 + 0.028 * back ** 0.8))
    frames = transport_frames(path + path[:2], (0, 0, 1))
    hood_rings = []
    for (c, (rw, rh)), (t, u, v) in zip(zip(path, tube), frames):
        out = Vector((c.x + 0.012, c.y, 0)).normalized()
        up = Vector((0, 0, 1))
        hood_rings.append(sring(c + up * rh * 0.25, out, up, 16, rw, rw * 0.7, rh, rh * 0.9, 2.2))
    hood = loft("Капюшон", hood_rings, M["jacket_dark"], closed=True)
    drape(hood, (0, 0, 1), 0.018, 0.0025, (-0.03, 0, z1), 0.1, seed=0.6)
    cloth_relief(hood, 0.001, 0.04)
    neck = rod((0.008, 0, z1 - 0.04), (0.012, 0, HJ.HEAD_BOTTOM + 0.03), 0.034, vertices=24)
    finish(neck, M["skin"], "Шея")
    # Chest pocket on the near side: a stitched patch pressed onto the
    # jacket with a flap and a press stud, flush with the cloth.
    pocket, flap, stud, pocket_seams = patch_pocket(jacket, Vector((0.11, -0.045, 0.452)), 0.056, 0.062, M, "куртки",
                                                    M["jacket"], M["jacket_dark"], M["thread_dark"])
    zip_path = surface_path(jacket, (0.15, -0.0, z1 - 0.02), (0.15, -0.0, z0 + 0.012), 24)
    zipper = band(jacket, zip_path, 0.011, 0.003, M["jacket_dark"], "Планка молнии")
    teeth = stitches(jacket, zip_path, M["metal"], "Зубцы молнии", spacing=0.0042, length=0.0055, radius=0.0014, lift=0.0032)
    hem_path = ring_path((0.004, 0, z0 + 0.024), 0.145, 0.118, steps=96)
    hem = band(jacket, hem_path, 0.03, 0.005, M["jacket_dark"], "Подол")
    hem_seams = band_edges(jacket, hem, hem_path, 0.03, M["thread_dark"], "Строчка подола")
    straps = []
    for s in (-1, 1):
        # Backpack straps: from the pack's top over the shoulder, down the
        # chest beside the zip and back under the arm to the pack's bottom.
        top = Vector((-0.07, s * 0.07, z1 - 0.004))
        over = Vector((0.02, s * 0.085, z1 - 0.002))
        chest = Vector((0.1, s * 0.075, 0.6))
        low = Vector((0.1, s * 0.085, 0.5))
        path = [top.lerp(over, k / 6) for k in range(6)] + [over.lerp(chest, k / 8) for k in range(8)] \
            + [chest.lerp(low, k / 8) for k in range(9)]
        name = "Лямка" + (" far" if s > 0 else "")
        strap = band(jacket, path, 0.032, 0.008, M["strap"], name, lift=0.0025)
        straps += [strap] + band_edges(jacket, strap, path, 0.032, M["thread"], "Строчка лямки")
        ok, bl, bn, _ = jacket.closest_point_on_mesh(path[16])
        straps.append(buckle(bl + bn * 0.011, bn, 0.03, M["metal"], M["strap"], "Пряжка лямки", along=path[17] - path[15]))
    # Chest strap between the two shoulder straps, with a buckle on the zip.
    chest_path = surface_path(jacket, (0.09, -0.08, 0.585), (0.09, 0.08, 0.585), 24, bulge=(0.06, 0, 0))
    chest = band(jacket, chest_path, 0.02, 0.006, M["strap"], "Нагрудный ремень", lift=0.008)
    chest_seams = band_edges(jacket, chest, chest_path, 0.02, M["thread"], "Строчка нагрудного ремня", inset=0.003)
    ok, cl, cn, _ = jacket.closest_point_on_mesh(Vector((0.16, 0.0, 0.585)))
    chest_bk = buckle(cl + cn * 0.015, cn, 0.026, M["metal"], M["strap"], "Пряжка нагрудного ремня")
    ok, zl, zn, _ = jacket.closest_point_on_mesh(Vector((0.16, 0.0, z1 - 0.03)))
    pull = rounded((0.005, 0.011, 0.026), zl + zn * 0.006 - Vector((0, 0, 0.016)), 0.0025)
    finish(pull, M["strap"], "Бегунок")
    return ([jacket, hood, neck, pocket, flap, stud, zipper, teeth, hem, chest, chest_bk, pull]
            + pocket_seams + hem_seams + straps + chest_seams)


def patch_pocket(target, centre, width, height, M, word, mat, flap_mat, thread):
    """A flat patch pocket pressed onto a surface, a flap over its top and a
    press stud: sheets wrapped onto the surface so they never float."""
    ok, c, n, _ = target.closest_point_on_mesh(centre)
    up = Vector((0, 0, 1))
    side = n.cross(up).normalized()
    up = side.cross(n).normalized()
    cols, rws = 7, 8

    def grid(w, h, base):
        return [[base + side * (w * (cc / (cols - 1) - 0.5)) + up * (h * (rr / (rws - 1) - 0.5)) + n * 0.01
                 for cc in range(cols)] for rr in range(rws)]

    pocket = solid_sheet("Карман " + word, grid(width, height, c), 0.006, mat, target=target, lift=0.0008)
    flap_c = c + up * (height * 0.5 - 0.012)
    flap = solid_sheet("Клапан " + word, grid(width + 0.006, 0.03, flap_c), 0.006, flap_mat, target=pocket, lift=0.0005)
    ok, sl, sn, _ = flap.closest_point_on_mesh(flap_c - up * 0.006 + n * 0.02)
    stud = ball(0.0055, sl + sn * 0.0015, (1, 1, 0.55), 12)
    stud.rotation_euler = Vector((0, 0, 1)).rotation_difference(sn).to_euler()
    apply_all(stud)
    finish(stud, M["metal"], "Кнопка " + word)
    rim = []
    corners = [(-0.5, 0.25), (-0.5, -0.5), (0.5, -0.5), (0.5, 0.25)]
    inset = 0.007
    for (x0, y0), (x1, y1) in zip(corners, corners[1:]):
        for k in range(10):
            x = lerp(x0, x1, k / 10) * (width - 2 * inset)
            y = lerp(y0, y1, k / 10) * (height - 2 * inset)
            rim.append(c + side * x + up * y + n * 0.03)
    seam = stitches(pocket, rim, thread, "Строчка кармана " + word)
    flap_rim = [flap_c + side * (width * (k / 12 - 0.5) * 0.9) - up * 0.008 + n * 0.03 for k in range(13)]
    flap_seam = stitches(flap, flap_rim, thread, "Строчка клапана " + word)
    return pocket, flap, stud, [seam, flap_seam]


def raglan_points(side):
    """The sleeve's spine: from under the collar over the shoulder (a raglan
    sleeve, as on outdoor jackets: one smooth slope from the neck to the
    arm), then down the arm to the cuff. Returns points, radii and how far
    along each point is (negative over the shoulder, 0 at the joint)."""
    sh, el, wr = HJ.arm_points(side)
    k = 1 if side == "near" else -1
    # A real shoulder line: nearly level from the collar out past the head's
    # edge, a rounded shoulder point (the deltoid), then the arm hangs down.
    # A set-in sleeve: it leaves the jacket from an armhole on the side of
    # the chest, rounds over into the shoulder cap and hangs down against
    # the body. The armhole lies inside the jacket, so the sleeve grows out of
    # it along the shoulder seam instead of standing next to it.
    a = Vector((sh.x - 0.002, -k * (HJ.ARM_Y - 0.05), sh.z - 0.02))
    b = Vector((sh.x - 0.001, -k * (HJ.ARM_Y - 0.018), sh.z - 0.016))
    c = Vector((sh.x, -k * (HJ.ARM_Y - 0.002), sh.z - 0.05))
    cuff_end = wr + (el - wr).normalized() * 0.016  # The gauntlet shows below it.
    keys = [a, b, c, sh.lerp(el, 0.6) + Vector((0, -k * 0.002, 0)), el, el.lerp(cuff_end, 0.5), cuff_end]
    key_r = [0.05, 0.05, 0.048, 0.045, 0.041, 0.041, 0.038]
    key_t = [-0.35, -0.15, 0.1, 0.6, 1.0, 1.5, 2.0]
    pts, radii, ts = [], [], []
    for i in range(len(keys) - 1):
        steps = 3 if i < 2 else 5
        for st in range(steps):
            u = st / steps
            p0, p1, p2, p3 = keys[max(i - 1, 0)], keys[i], keys[i + 1], keys[min(i + 2, len(keys) - 1)]
            pts.append(catmull(p0, p1, p2, p3, u))
            r0, r1, r2, r3 = key_r[max(i - 1, 0)], key_r[i], key_r[i + 1], key_r[min(i + 2, len(keys) - 1)]
            radii.append(catmull(r0, r1, r2, r3, u))
            ts.append(lerp(key_t[i], key_t[i + 1], u))
    pts.append(keys[-1])
    radii.append(key_r[-1])
    ts.append(key_t[-1])
    return pts, radii, ts


def build_arm(M, side):
    sh, el, wr = HJ.arm_points(side)
    k = 1 if side == "near" else -1
    out = Vector((0, -k, 0))
    path, radii, ts = raglan_points(side)
    frames = transport_frames(path, (1, 0, 0))
    n = 24
    rings = []
    t0, u0, v0 = frames[0]
    rings += list(reversed(cap_rings(path[0], -t0, u0, v0, radii[0], radii[0], n, steps=3, end=0.4)))
    for (c, r, t), (tt, u, v) in zip(zip(path, radii, ts), frames):
        # Over the shoulder the sleeve lies on the jacket: flatter top to bottom.
        # The shoulder cap is slimmer front to back than top to bottom: a round
        # cap read as a ball on the back of the shoulder.
        slim = 1.0 - 0.16 * (1.0 - smooth01((t + 0.05) / 0.4))
        rings.append(sring(c, u, v, n, r * 1.02 * slim, r * slim, r, r, 2.15, phase=math.pi * 0.5 * k))
    # The cuff end: the cloth turns inward (no closed cap: the glove sits in it).
    t1, u1, v1 = frames[-1]
    r1 = radii[-1]
    rings.append(sring(path[-1] + t1 * 0.004, u1, v1, n, r1 * 0.86, r1 * 0.86, r1 * 0.86, r1 * 0.86, 2.0, phase=math.pi * 0.5 * k))
    rings.append(sring(path[-1] - t1 * 0.012, u1, v1, n, r1 * 0.78, r1 * 0.78, r1 * 0.78, r1 * 0.78, 2.0, phase=math.pi * 0.5 * k))
    sleeve = loft("Рукав " + side, rings, M["jacket"], cap_start=True)
    folds(sleeve, el, (wr - sh), 3, 0.018, 0.0026, 0.03)
    drape(sleeve, (wr - sh), 0.024, 0.003, (sh + el) / 2, 0.055, seed=0.4 if side == "near" else 2.2)
    drape(sleeve, (wr - sh), 0.02, 0.0026, (el + wr) / 2, 0.045, seed=1.3 if side == "near" else 2.9)
    cloth_relief(sleeve, 0.0008, 0.05)
    # The shoulder seam round the sleeve where it leaves the jacket.
    i_seam = min(range(len(path)), key=lambda i: abs(abs(path[i].y) - (HJ.ARM_Y - 0.026)))
    c_s, r_s = path[i_seam], radii[i_seam]
    _, u_s, v_s = frames[i_seam]
    seam_ring = [c_s + u_s * math.cos(a_) * r_s * 1.1 + v_s * math.sin(a_) * r_s * 1.1 for a_ in [i / 64 * math.tau for i in range(65)]]
    raglan = [stitches(sleeve, seam_ring, M["thread_dark"], "Шов плеча")]
    # Cuff: a leather strap with a buckle just above the wrist.
    down = (wr - el).normalized()
    cuff_c = wr - down * 0.052  # Clear of the sleeve's turned-in end: its edge wrapped inside and stuck out.
    cf = transport_frames([cuff_c - down * 0.01, cuff_c, cuff_c + down * 0.01], (1, 0, 0))[1]
    path_c = [cuff_c + cf[1] * math.cos(a) * 0.055 + cf[2] * math.sin(a) * 0.055 for a in [i / 48 * math.tau for i in range(49)]]
    cuff = band(sleeve, path_c, 0.03, 0.007, M["strap"], "Манжета " + side)
    cuff_seams = band_edges(sleeve, cuff, path_c, 0.03, M["thread"], "Строчка манжеты")
    ok, bl, bn, _ = sleeve.closest_point_on_mesh(cuff_c + out * 0.055)
    bk = buckle(bl + bn * 0.009, bn, 0.026, M["metal"], M["strap"], "Пряжка манжеты " + side)
    glove = build_glove(M, wr, down, side)
    return [sleeve, cuff, bk] + raglan + cuff_seams + glove


def finger(name, base, direction, curl_axis, lengths, curls, r0, r_tip, n=12):
    """One finger: three phalanges, each bent `curls` (radians) about
    curl_axis, a knuckle swelling at each joint, a rounded tip."""
    pts = [Vector(base)]
    d = Vector(direction).normalized()
    joints = [0]
    for length, angle in zip(lengths, curls):
        d = Matrix.Rotation(angle, 3, curl_axis) @ d
        pts.append(pts[-1] + d * length)
        joints.append(len(pts) - 1)
    # Resample with a few rings per phalanx.
    path, radii = [], []
    total = sum(lengths)
    acc = 0.0
    for i in range(len(lengths)):
        a, b = pts[i], pts[i + 1]
        steps = 4
        for s in range(steps):
            t = s / steps
            path.append(a.lerp(b, t))
            g = (acc + lengths[i] * t) / total
            r = lerp(r0, r_tip, g)
            # Knuckle swelling at joints, the pad of each phalanx a little fuller.
            r *= 1.0 + 0.08 * math.exp(-(t / 0.18) ** 2) + 0.03 * math.sin(t * math.pi)
            radii.append(r)
        acc += lengths[i]
    path.append(pts[-1])
    radii.append(r_tip)
    frames = transport_frames(path, curl_axis)
    rings = []
    for (c, r), (t, u, v) in zip(zip(path, radii), frames):
        # Flatter on the palm side, round on the back.
        rings.append(sring(c, u, v, n, r, r, r * 1.04, r * 0.86, 2.1))
    t, u, v = frames[-1]
    rings += cap_rings(path[-1], t, u, v, r_tip, r_tip, n, steps=3, end=0.9)
    return rings


def build_glove(M, wrist, down, side):
    """A gloved hand hanging relaxed beside the thigh, built like a hand.

    The palm faces the body and is soft and rounded, a little cupped. The
    four fingers start on an arched knuckle line, touch each other, lean in
    toward the middle finger and curl gently toward the palm, each a bit
    more than the one before it: the middle longest, the little finger short.
    The thumb comes off the front of the palm and lies along the index
    finger, seen from the side. A short gauntlet shows between the sleeve's
    cuff and the hand, with a stitched edge.
    """
    k = 1 if side == "near" else -1
    inward = Vector((0, k, 0))  # Toward the body: the palm faces it.
    fwd = (Vector((1, 0, 0)) - down * Vector((1, 0, 0)).dot(down)).normalized()
    inward = (inward - down * inward.dot(down) - fwd * inward.dot(fwd)).normalized()
    objs = []
    n = 20
    # Palm and back of the hand: from inside the gauntlet to the knuckles;
    # the back domed, the palm side fuller at the heel of the hand.
    palm_rows = [  # along, half width (fwd), back (outward), palm (inward), squareness, fwd shift
        (-0.012, 0.027, 0.022, 0.022, 2.0, 0.0),
        (0.004, 0.029, 0.021, 0.022, 2.1, 0.001),
        (0.02, 0.034, 0.02, 0.023, 2.3, 0.002),
        (0.036, 0.038, 0.019, 0.021, 2.4, 0.002),
        (0.05, 0.039, 0.017, 0.018, 2.4, 0.001),
        (0.058, 0.036, 0.015, 0.015, 2.3, 0.0),
    ]
    rows = profile(palm_rows, 2)
    rings = [sring(wrist + down * a + fwd * sh, fwd, -inward, n, hw, hw, back, palm, p) for a, hw, back, palm, p, sh in rows]
    last = rows[-1]
    rings += cap_rings(wrist + down * last[0] + fwd * last[5], down, fwd, -inward, last[1], (last[2] + last[3]) / 2, n,
                       steps=3, end=0.3)
    objs.append(loft("Перчатка " + side, rings, M["glove"], cap_start=True, levels=1))
    curl_axis = down.cross(inward).normalized()  # Turning `down` about it bends a finger toward the palm.
    # Index (front) to little (back): offset along fwd, how far down the
    # knuckle sits (an arch), length, radius, curl.
    specs = [
        (0.0255, 0.049, 0.95, 0.0102, (0.3, 0.55, 0.4)),
        (0.0085, 0.053, 1.07, 0.0107, (0.34, 0.62, 0.42)),
        (-0.0085, 0.052, 1.0, 0.0102, (0.4, 0.68, 0.45)),
        (-0.0245, 0.047, 0.78, 0.009, (0.5, 0.75, 0.5)),
    ]
    for row, drop, scale, r, curls in specs:
        base = wrist + down * drop + fwd * row - inward * 0.001
        # Lean toward the middle finger: the hand narrows to the fingertips.
        lean = -row * 0.9
        direction = (down + fwd * lean - inward * 0.05).normalized()
        rings = finger("Палец", base, direction, curl_axis, [0.023 * scale, 0.016 * scale, 0.013 * scale],
                       list(curls), r, r * 0.84)
        objs.append(loft("Палец", rings, M["glove"], cap_start=True, cap_end=True, levels=1))
    # Thumb: a fleshy mound on the front of the palm, then two phalanges
    # pointing down along the index finger, the tip curling in a little.
    mound = ball(0.017, wrist + down * 0.022 + fwd * 0.026 + inward * 0.006, (1.0, 1.0, 1.0), 20)
    finish(mound, M["glove"], "Подушка")
    objs.append(mound)
    t_base = wrist + down * 0.02 + fwd * 0.03 + inward * 0.007
    t_dir = (down * 0.9 + fwd * 0.22 + inward * 0.3).normalized()
    thumb_axis = t_dir.cross(inward).normalized()
    rings = finger("Большой", t_base, t_dir, thumb_axis, [0.022, 0.018], [0.0, 0.3], 0.0125, 0.0108)
    objs.append(loft("Большой", rings, M["glove"], cap_start=True, cap_end=True, levels=1))
    # Gauntlet: from inside the sleeve, flaring out just below the cuff, then
    # gathering into the wrist.
    g_rows = [(-0.05, 0.026), (-0.034, 0.0285), (-0.022, 0.0305), (-0.01, 0.0295), (0.0, 0.027), (0.01, 0.025)]
    g_rings = [sring(wrist + down * a, fwd, -inward, n, r * 1.12, r * 1.12, r * 0.9, r * 0.9, 2.0) for a, r in g_rows]
    objs.append(loft("Раструб", g_rings, M["glove"], levels=1))
    glove = join(objs)
    glove.name = "Перчатка " + side
    cloth_relief(glove, 0.0003, 0.02)
    ring = [wrist - down * 0.014 + fwd * 0.037 * math.cos(t) - inward * 0.031 * math.sin(t) for t in [i / 48 * math.tau for i in range(49)]]
    seams = [stitches(glove, ring, M["thread"], "Край перчатки " + side, spacing=0.007, length=0.0045, radius=0.001)]
    return [glove] + seams


# Pant leg, top to bottom: z, x centre, front, back, outer side, inner side.
LEG_ROWS = [
    # Under the jacket the pants are a slim pelvis that fits inside it with
    # room to spare (fuller, the seat stuck out of the jacket's back).
    (0.482, -0.004, 0.07, 0.066, 0.042, 0.07),
    (0.452, -0.004, 0.072, 0.07, 0.046, 0.07),
    (0.415, -0.002, 0.074, 0.074, 0.053, 0.066),
    (0.38, 0.0, 0.07, 0.072, 0.059, 0.06),
    (0.335, 0.004, 0.065, 0.064, 0.061, 0.057),
    (0.29, 0.01, 0.062, 0.059, 0.058, 0.055),
    (0.262, 0.012, 0.063, 0.056, 0.057, 0.055),
    (0.23, 0.01, 0.058, 0.057, 0.056, 0.055),
    (0.2, 0.006, 0.058, 0.058, 0.057, 0.056),
    (0.172, 0.004, 0.062, 0.064, 0.062, 0.06),
    (0.152, 0.006, 0.068, 0.067, 0.066, 0.063),
]
PANT_HEM = 0.152


def build_pants(M):
    legs = []
    for side, y in (("near", -HJ.LEG_Y), ("far", HJ.LEG_Y)):
        s = -1 if y < 0 else 1  # +1: outer side is +Y
        rings = []
        for z, x, af, ab, b_out, b_in in profile(LEG_ROWS, 3):
            bp, bn = (b_out, b_in) if s > 0 else (b_in, b_out)
            rings.append(sring((x, y, z), (1, 0, 0), (0, 1, 0), 28, af, ab, bp, bn, 2.2, phase=math.pi * 0.5 * -s))
        last = LEG_ROWS[-1]
        z, x = last[0], last[1]
        rings.append(sring((x, y, z + 0.004), (1, 0, 0), (0, 1, 0), 28, last[2] - 0.008, last[3] - 0.008, last[4] - 0.008,
                           last[5] - 0.008, 2.2, phase=math.pi * 0.5 * -s))
        rings.append(sring((x, y, z + 0.03), (1, 0, 0), (0, 1, 0), 28, last[2] - 0.012, last[3] - 0.012, last[4] - 0.012,
                           last[5] - 0.012, 2.2, phase=math.pi * 0.5 * -s))
        # The hem is not a ruler-cut cylinder: it rides up over the laces at
        # the front, drops a little at the back and waves.
        for ring in rings:
            for p in ring:
                fade = 1.0 - smooth01((p.z - PANT_HEM) / 0.03)
                if fade <= 0:
                    continue
                a = math.atan2(p.y - y, p.x - x)
                p.z += fade * (0.009 * max(0.0, math.cos(a)) ** 1.5 - 0.004 * max(0.0, -math.cos(a))
                               + 0.0018 * math.sin(3 * a + y * 40))
        legs.append(loft("Штаны " + side, rings, M["pants"], cap_start=True))
    pants = join(legs)
    pants.name = "Штаны"
    for side, y in (("near", -HJ.LEG_Y), ("far", HJ.LEG_Y)):
        folds(pants, (0.0, y, HJ.KNEE + 0.005), (0, 0, 1), 3, 0.018, 0.0028, 0.03)
        folds(pants, (0.0, y, PANT_HEM + 0.03), (0, 0, 1), 3, 0.014, 0.003, 0.03)
        drape(pants, (0.3, 0, 1), 0.03, 0.0035, (0.0, y, (HJ.KNEE + PANT_HEM) / 2), 0.075, seed=0.7 if side == "near" else 2.4)
        drape(pants, (-0.3, 0, 1), 0.034, 0.003, (0.0, y, (HJ.HIP + HJ.KNEE) / 2), 0.085, seed=1.9 if side == "near" else 3.6)
    cloth_relief(pants, 0.0012, 0.05)
    extra = []
    for side, y in (("near", -HJ.LEG_Y), ("far", HJ.LEG_Y)):
        s = -1 if y < 0 else 1
        patch, rim = oval_patch(pants, (0.12, y + s * 0.012, HJ.KNEE + 0.008), 0.028, 0.042,
                                0.006, M["patch"], "Наколенник " + side, lift=0.0012)
        extra.append(stitches(patch, rim, M["thread"], "Строчка наколенника " + side))
        tz = HJ.HIP - 0.13  # Mid-thigh, below the hanging hand's fingertips.
        # Tight round the leg: a wider ring reached the other thigh, got glued
        # to it and stretched into a line between the knees in a stride.
        path = ring_path((0.004, y, tz), 0.064, 0.066, steps=64)
        strap = band(pants, path, 0.024, 0.006, M["strap"], "Ремень бедра " + side)
        ok, bl, bn, _ = pants.closest_point_on_mesh(Vector((0.1, y, tz)))
        bk = buckle(bl + bn * 0.008, bn, 0.022, M["metal"], M["strap"], "Пряжка бедра " + side)
        extra += [patch, strap, bk]
        extra.append(stitches(pants, surface_path(pants, (0.0, y + s * 0.08, HJ.HIP - 0.02), (0.004, y + s * 0.08, PANT_HEM + 0.012), 40),
                              M["thread_pants"], "Боковой шов"))
        hem_line = []
        for i in range(97):
            a = i / 96 * math.tau
            z = PANT_HEM + 0.014 + 0.009 * max(0.0, math.cos(a)) ** 1.5 - 0.004 * max(0.0, -math.cos(a))                 + 0.0018 * math.sin(3 * a + y * 40)
            # Close round its own leg: a wider ring reached the other leg.
            hem_line.append(Vector((0.006 + math.cos(a) * 0.068, y + math.sin(a) * 0.066, z)))
        extra.append(stitches(pants, hem_line, M["thread_pants"], "Строчка низа"))
    # Cargo pocket on the outer side of the near thigh, pressed flat.
    pocket, flap, stud, seams = patch_pocket(pants, Vector((0.0, -HJ.LEG_Y - 0.09, HJ.HIP - 0.13)), 0.062, 0.078, M, "брюк",
                                             M["pants"], M["pants"], M["thread_pants"])
    extra += [pocket, flap, stud] + seams
    # No belt: it sat under the jacket where it never shows, and poked out
    # through the jacket's sides.
    return [pants] + extra


SOLE_BACK, SOLE_FRONT = -0.064, 0.15
TOE_SPRING = 0.016  # The toe of a hiking boot curves up off the ground.


def toe_lift(x):
    return TOE_SPRING * smooth01((x - 0.07) / (SOLE_FRONT - 0.07)) ** 1.6


def sole_half_width(x):
    """Half the sole's width at x: a round toe, the ball wide, a waist under
    the arch, a narrower round heel."""
    t = (x - SOLE_BACK) / (SOLE_FRONT - SOLE_BACK)
    t = min(1.0, max(0.0, t))
    toe = math.sqrt(max(0.0, 1.0 - ((t - 0.7) / 0.3) ** 2)) if t > 0.7 else 1.0
    heel = math.sqrt(max(0.0, 1.0 - ((0.2 - t) / 0.2) ** 2)) if t < 0.2 else 1.0
    waist = 1.0 - 0.13 * math.exp(-((t - 0.42) / 0.12) ** 2)
    ball_ = 1.0 + 0.05 * math.exp(-((t - 0.66) / 0.1) ** 2)
    return 0.057 * min(toe, heel) * waist * ball_ * (1.0 if t > 0.5 else 0.94)


def sole_slab(y, z, thick, grow, x_from=None, x_to=None, name="Подошва", bevel=0.006):
    """An extruded foot-shaped outline (between x_from and x_to), edges softly
    rounded, its toe lifted with the toe spring."""
    back = SOLE_BACK - grow if x_from is None else x_from
    front = SOLE_FRONT + grow if x_to is None else x_to
    steps = 48
    xs = [back + (front - back) * i / steps for i in range(steps + 1)]

    def hw(x):
        if x < SOLE_BACK or x > SOLE_FRONT:
            return max(0.0, grow)
        return sole_half_width(x) + grow
    ring = [(x, -hw(x)) for x in xs] + [(x, hw(x)) for x in reversed(xs)]
    ring = [(x, dy) for x, dy in ring if True]
    bm = bmesh.new()
    bottom = [bm.verts.new((x, y + dy, z - thick / 2)) for x, dy in ring]
    face = bm.faces.new(bottom)
    ext = bmesh.ops.extrude_face_region(bm, geom=[face])
    for v in [e for e in ext["geom"] if isinstance(e, bmesh.types.BMVert)]:
        v.co.z += thick
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    mesh = bpy.data.meshes.new(name)
    bm.to_mesh(mesh)
    bm.free()
    obj = link(bpy.data.objects.new(name, mesh))
    mod = obj.modifiers.new("bevel", "BEVEL")
    mod.width = min(bevel, thick * 0.4)
    mod.segments = 3
    mod.limit_method = "ANGLE"
    apply_all(obj)
    for v in obj.data.vertices:
        v.co.z += toe_lift(v.co.x)
    obj.data.update()
    return obj


# Boot upper, bottom to top: z, heel x, toe x, width (share of the sole's
# outline), roundness (0 the foot-shaped outline, 1 an ellipse: the shaft),
# shaft half width. Each slice of the upper is the sole's own outline drawn
# smaller, so the upper fills its sole with an even margin; the toe box rounds
# over at the front, the heel counter stays upright, the shaft rises from the
# instep to a padded collar.
BOOT_SLICES = [
    (0.0425, -0.058, 0.143, 0.93, 0.0, 0.05),
    (0.05, -0.0605, 0.1475, 0.975, 0.0, 0.05),
    (0.064, -0.0612, 0.148, 0.985, 0.0, 0.05),
    (0.08, -0.0605, 0.141, 0.975, 0.04, 0.052),
    (0.094, -0.059, 0.126, 0.95, 0.18, 0.053),
    (0.105, -0.0575, 0.104, 0.92, 0.42, 0.053),
    (0.117, -0.0555, 0.08, 0.92, 0.72, 0.053),
    (0.13, -0.0535, 0.066, 0.92, 0.95, 0.052),
    (0.146, -0.053, 0.063, 0.92, 1.0, 0.052),
    (0.16, -0.0535, 0.0645, 0.92, 1.0, 0.0535),
    (0.169, -0.0525, 0.0635, 0.92, 1.0, 0.052),
    (0.1735, -0.045, 0.055, 0.92, 1.0, 0.045),
]
BOOT_RING = 48


def boot_slice(y, row, n=BOOT_RING):
    z, xb, xf, w, e, ry = row
    pts = []
    for i in range(n):
        th = i / n * math.tau
        t = 0.5 - 0.5 * math.cos(th)  # 0 at the heel, 1 at the toe.
        side = 1.0 if math.sin(th) >= 0 else -1.0
        x = xb + (xf - xb) * t
        foot = sole_half_width(SOLE_BACK + t * (SOLE_FRONT - SOLE_BACK)) * w
        ell = ry * abs(math.sin(th))
        hw = lerp(foot, ell, e)
        lift = toe_lift(x) * (1.0 - smooth01((z - 0.0425) / 0.07))
        pts.append(Vector((x, y + side * hw, z + lift)))
    return pts


def boot_front_x(z):
    """Where the front of the upper is at height z (from BOOT_SLICES)."""
    rows = BOOT_SLICES
    for a, b in zip(rows, rows[1:]):
        if a[0] <= z <= b[0]:
            return lerp(a[2], b[2], (z - a[0]) / (b[0] - a[0]))
    return rows[-1][2]


def outward(p, y):
    """Pushed 1 cm out from the boot's axis: a point to project onto it."""
    return p + (p - Vector((0.04, y, p.z))).normalized() * 0.01


def build_boot(M, side):
    y = -HJ.LEG_Y if side == "near" else HJ.LEG_Y
    rows = profile(BOOT_SLICES, 2)
    rings = [boot_slice(y, r) for r in rows]
    top = BOOT_SLICES[-1]
    # The top turns inward (the cut edge of the padded collar), no cap.
    rings.append(boot_slice(y, (top[0] - 0.008, top[1] + 0.006, top[2] - 0.006, top[3], 1.0, top[5] - 0.006)))
    upper = loft("Ботинок " + side, rings, M["boot"], cap_start=True)
    cloth_relief(upper, 0.0006, 0.03)
    # Sole: a stitched leather welt, a rubber midsole, then the lugged
    # outsole: a heel block and a forefoot pad with a gap under the arch.
    welt_band = sole_slab(y, 0.037, 0.011, 0.0035, name="Рант подошвы " + side, bevel=0.003)
    finish(welt_band, M["welt"])
    mid = sole_slab(y, 0.024, 0.017, 0.004, name="Подошва " + side, bevel=0.005)
    finish(mid, M["sole"])
    heel = sole_slab(y, 0.009, 0.014, 0.0035, x_from=SOLE_BACK - 0.0035, x_to=0.006, name="Каблук " + side, bevel=0.004)
    finish(heel, M["sole"])
    fore = sole_slab(y, 0.009, 0.014, 0.0035, x_from=0.04, x_to=SOLE_FRONT + 0.0035, name="Протектор " + side, bevel=0.004)
    finish(fore, M["sole"])
    lugs = [heel, fore]
    # Tread: chevron lugs across the forefoot, bars across the heel, and
    # short teeth round the edge that show from the side.
    for i in range(6):
        x = 0.05 + i * 0.017
        hw = sole_half_width(x) * 0.62
        for s in (-1, 1):
            lug = rounded((0.011, hw, 0.009), (x + 0.004, y + s * hw * 0.5, 0.0005 + toe_lift(x)), 0.0035,
                          rot=(0, 0, s * math.radians(28)), segments=2)
            finish(lug, M["sole"], "Протектор")
            lugs.append(lug)
    for x in (-0.05, -0.032, -0.014):
        hw = sole_half_width(x) * 0.8
        lug = rounded((0.011, hw * 2, 0.009), (x, y, 0.0005), 0.0035, segments=2)
        finish(lug, M["sole"], "Протектор")
        lugs.append(lug)
    for x in [SOLE_BACK + 0.01 + i * 0.0175 for i in range(12)]:
        if 0.008 < x < 0.035:
            continue
        hw = sole_half_width(x) + 0.0015
        for s in (-1, 1):
            tooth = rounded((0.011, 0.012, 0.016), (x, y + s * (hw - 0.004), 0.008 + toe_lift(x)), 0.004, segments=2)
            finish(tooth, M["sole"], "Протектор")
            lugs.append(tooth)
    # Welt stitching round the sole's top edge.
    welt_pts = []
    for i in range(129):
        th = i / 128 * math.tau
        t = 0.5 - 0.5 * math.cos(th)
        x = SOLE_BACK + 0.002 + (SOLE_FRONT - SOLE_BACK - 0.004) * t
        sd = 1 if math.sin(th) >= 0 else -1
        welt_pts.append(Vector((x, y + sd * (sole_half_width(x) + 0.0015), 0.044 + toe_lift(x))))
    welt = stitches(welt_band, welt_pts, M["thread"], "Рант " + side)
    # The rand seam: one unbroken stitch line all round the upper just above
    # the welt, as on a hiking boot (half seams stopped mid-surface).
    rand = boot_slice(y, (0.072, -0.061, 0.148, 0.985, 0.0, 0.05), 128)
    toe_cap = stitches(upper, [outward(p, y) for p in rand + rand[:1]], M["thread"], "Носок " + side)
    # Lacing: a tongue down the front from the collar to the instep, two
    # leather flaps with eyelets either side, laces crossing over the tongue
    # and pressed onto it, a small bow at the top.
    zs = [0.154, 0.136, 0.117, 0.1, 0.087]  # Eyelets on the middle three, below the pant hem.
    centre_line = []
    for z in zs:
        ok, loc, nn, _ = upper.closest_point_on_mesh(Vector((boot_front_x(z) + 0.03, y, z + 0.006)))
        centre_line.append((loc, nn))
    tongue_path = [Vector((boot_front_x(0.17) - 0.004, y, 0.172))] + [c for c, _ in centre_line] + \
                  [centre_line[-1][0] + Vector((0.008, 0, -0.005))]
    tongue = band(upper, tongue_path, 0.028, 0.006, M["glove"], "Язык " + side, lift=0.0008)
    laces = [tongue]
    for sd in (-1, 1):
        edge = []
        for c, nn in centre_line:
            across = nn.cross(Vector((0, 0, 1))).normalized()
            edge.append(c + across * sd * 0.022 + nn * 0.02)
        flap = band(upper, edge, 0.013, 0.004, M["boot"], "Клапан ботинка", lift=0.0025)
        laces += [flap, stitches(flap, edge, M["thread"], "Строчка клапана ботинка", spacing=0.007)]
    holes = []
    for (c, nn) in centre_line[1:-1]:
        row = []
        across = nn.cross(Vector((0, 0, 1))).normalized()
        for sd in (-1, 1):
            ok, loc, en, _ = upper.closest_point_on_mesh(c + across * sd * 0.022 + nn * 0.02)
            loc = loc + en * 0.0062
            eyelet = torus(0.0066, 0.0021, loc, rot=Vector((0, 0, 1)).rotation_difference(en).to_euler(), segments=16, rings=8)
            finish(eyelet, M["metal"], "Люверс")
            laces.append(eyelet)
            row.append((loc, en))
        holes.append(row)
    for upper_row, lower_row in zip(holes, holes[1:]):
        for (pa, na), (pb, nb) in ((upper_row[0], lower_row[1]), (upper_row[1], lower_row[0])):
            mid_pt = (pa + pb) / 2
            ok, ml, mn, _ = tongue.closest_point_on_mesh(mid_pt + (na + nb) * 0.02)
            mid_pt = ml + mn * 0.0035
            for p0, p1 in ((pa, mid_pt), (mid_pt, pb)):
                lace = rod(p0, p1, 0.003, vertices=10)
                finish(lace, M["lace"], "Шнурок")
                laces.append(lace)
    top_row = holes[0]
    tn = top_row[0][1]
    centre = (top_row[0][0] + top_row[1][0]) / 2 + tn * 0.002
    for dy in (-1, 1):
        # Bow loops lying on the tongue, drooping to the sides, short tails.
        loop = torus(0.0075, 0.0024, centre + tn * 0.003 + Vector((0, dy * 0.009, 0.002)),
                     rot=(Vector((0, 0, 1)).rotation_difference(tn) @ Matrix.Rotation(dy * 0.4, 3, "X").to_quaternion()).to_euler(),
                     scale=(1.0, 0.7, 1.0), segments=20, rings=8)
        finish(loop, M["lace"], "Бант")
        tail = rod(centre + tn * 0.003, centre + tn * 0.004 + Vector((0.002, dy * 0.006, -0.018)), 0.0024, vertices=10)
        finish(tail, M["lace"], "Шнурок")
        laces += [loop, tail]
    return [upper, welt_band, mid, welt, toe_cap] + lugs + laces


def spiral_end(centre, y_dir, r_out, turns, mat, name, thick=0.0042):
    """The end of a rolled mat: a flat spiral groove pressed into the face."""
    pts = []
    steps = int(turns * 48)
    for i in range(steps + 1):
        t = i / steps
        a = t * turns * math.tau
        r = r_out * (0.12 + 0.86 * t)
        pts.append(Vector((math.cos(a) * r, 0, math.sin(a) * r)) + Vector(centre))
    curve = bpy.data.curves.new(name, "CURVE")
    curve.dimensions = "3D"
    curve.bevel_depth = thick
    curve.bevel_resolution = 2
    spline = curve.splines.new("POLY")
    spline.points.add(len(pts) - 1)
    for p_, pt in zip(spline.points, pts):
        p_.co = (*pt, 1)
    obj = link(bpy.data.objects.new(name, curve))
    active(obj)
    bpy.ops.object.convert(target="MESH")
    return finish(obj, mat)


PACK_X = -0.183  # The pack's centre line (its back panel rests on the jacket).

# Pack body, bottom to top: z, outward bulge, back panel, half width, squareness.
PACK_ROWS = [
    (0.425, 0.05, 0.06, 0.1, 3.0),
    (0.44, 0.072, 0.074, 0.118, 3.2),
    (0.48, 0.085, 0.078, 0.126, 3.4),
    (0.55, 0.09, 0.08, 0.128, 3.5),
    (0.62, 0.086, 0.08, 0.127, 3.5),
    (0.67, 0.078, 0.079, 0.122, 3.3),
    (0.7, 0.068, 0.076, 0.112, 3.0),
    (0.712, 0.05, 0.066, 0.094, 2.6),
]


def pack_ring(row, n=36):
    z, out, back, hw, p = row
    return sring((PACK_X, 0, z), (-1, 0, 0), (0, 1, 0), n, out, back, hw, hw, p)


def build_backpack(M):
    rows = profile(PACK_ROWS, 3)
    rings = [pack_ring(r) for r in rows]
    z0 = PACK_ROWS[0][0]
    c0 = Vector((PACK_X - 0.006, 0, z0 - 0.008))
    rings.insert(0, sring(c0, (-1, 0, 0), (0, 1, 0), 36, 0.024, 0.03, 0.06, 0.06, 2.6))
    body = loft("Рюкзак", rings, M["leather"], cap_start=True, cap_end=True)
    # Soft leather: the load sags the sides a little and creases them.
    drape(body, (0, 0, 1), 0.04, 0.0022, (PACK_X - 0.06, 0, 0.5), 0.13, seed=0.9)
    cloth_relief(body, 0.0016, 0.04)
    # Lid: a leather flap over the top, hanging down the outer face.
    lid_pts = []
    cols = 13
    for r in range(9):
        t = r / 8
        # Back edge on the top behind, over the crown, down the outer face.
        a = lerp(-0.25, 1.0, t) * math.pi / 2
        x = PACK_X - 0.01 - math.sin(a) * 0.098
        z = 0.712 + math.cos(a) * 0.03 - max(0.0, t - 0.55) * 0.12
        row = []
        for c_ in range(cols):
            yy = (c_ / (cols - 1) - 0.5) * 0.262 * (1.0 - 0.06 * t)
            row.append(Vector((x, yy, z + 0.03)))
        lid_pts.append(row)
    lid = solid_sheet("Крышка рюкзака", lid_pts, 0.009, M["strap"], target=body, lift=0.0015)
    # Front pocket: a rounded box sewn to the outer face, with its own flap.
    px = PACK_X - 0.09
    pk_rows = [(0.45, 0.012, 0.075, 2.8), (0.47, 0.03, 0.088, 3.4), (0.53, 0.036, 0.092, 3.6),
               (0.58, 0.034, 0.09, 3.4), (0.6, 0.02, 0.08, 2.8)]
    pk_rings = [sring((px + 0.004, 0, z), (-1, 0, 0), (0, 1, 0), 32, d, 0.012, hw, hw, p) for z, d, hw, p in profile(pk_rows, 2)]
    pocket = loft("Карман рюкзака", pk_rings, M["leather"], cap_start=True, cap_end=True)
    cloth_relief(pocket, 0.001, 0.03)
    flap_pts = []
    for r in range(6):
        t = r / 5
        a = t * math.pi / 2
        x = px - 0.032 * math.sin(a) - 0.004
        z = 0.6 + 0.012 * math.cos(a) - max(0.0, t - 0.4) * 0.05
        flap_pts.append([Vector((x, (c_ / 10 - 0.5) * 0.19, z + 0.01)) for c_ in range(11)])
    flap = solid_sheet("Клапан рюкзака", flap_pts, 0.007, M["strap"], target=pocket, lift=0.001)
    # Rolled mat on the lid, with spiral ends and two straps.
    roll_x, roll_z, roll_r = PACK_X - 0.004, 0.78, 0.05
    roll = rod((roll_x, -0.128, roll_z), (roll_x, 0.128, roll_z), roll_r, vertices=40)
    apply_all(roll)
    for end in roll.data.vertices:
        end.co.y = max(-0.128, min(0.128, end.co.y))
    roll.data.update()
    roll = fuse([roll], "Коврик", M["mat"], voxel=0.0032, smooth=4)
    ends = [spiral_end((roll_x, y, roll_z), y, roll_r * 0.95, 3.2, M["jacket_dark"], "Торец коврика") for y in (-0.13, 0.13)]
    ties = []
    for y in (-0.07, 0.07):
        path = [Vector((roll_x + math.cos(a) * 0.058, y, roll_z + math.sin(a) * 0.058)) for a in [i / 40 * math.tau for i in range(41)]]
        tie = band(roll, path, 0.02, 0.006, M["strap"], "Стяжка")
        ties += [tie] + band_edges(roll, tie, path, 0.02, M["thread"], "Строчка стяжки", inset=0.003)
        ties.append(buckle(Vector((roll_x - 0.058, y, roll_z)), (-1, 0, 0), 0.022, M["metal"], M["strap"], "Пряжка стяжки", along=(0, 0, 1)))
    # Lid straps down the outer face to buckles on the pocket's top.
    shell = union_copy([body, lid, pocket, flap])
    for y in (-0.065, 0.065):
        # Drawn from well outside, round the crown and down the outer face:
        # each point lands on the outermost leather (lid, flap, pocket).
        path = []
        for i in range(41):
            a = i / 40 * math.pi * 0.62
            path.append(Vector((PACK_X - 0.02 - math.sin(a) * 0.3, y, 0.62 + math.cos(a) * 0.3)))
        path += [Vector((PACK_X - 0.35, y, 0.6 - i * 0.012)) for i in range(1, 9)]
        strap = band(shell, path, 0.019, 0.006, M["strap"], "Ремешок кармана", lift=0.0015)
        strap_path = [shell.closest_point_on_mesh(p)[1] for p in path]
        ties += [strap] + band_edges(shell, strap, strap_path, 0.019, M["thread"], "Строчка ремешка", inset=0.003)
        ok, bl, bn, _ = pocket.closest_point_on_mesh(Vector((px - 0.05, y, 0.555)))
        ties.append(buckle(bl + bn * 0.014, bn, 0.021, M["metal"], M["strap"], "Пряжка кармана", along=(0, 0, 1)))
    # Thermos on the near side, held by two straps.
    tx, ty = PACK_X + 0.004, -0.158
    th = rod((tx, ty, 0.44), (tx, ty, 0.6), 0.029, vertices=32)
    finish(th, M["thermos"], "Термос")
    cap = rod((tx, ty, 0.6), (tx, ty, 0.638), 0.027, vertices=32)
    finish(cap, M["metal"], "Крышка термоса")
    ribs = [finish(torus(0.0275, 0.0024, (tx, ty, z)), M["metal"], "Рифление") for z in (0.61, 0.619, 0.628)]
    holder = []
    for z in (0.475, 0.56):
        hp = ring_path((tx, ty, z), 0.032, 0.032)
        h = band(th, hp, 0.022, 0.006, M["strap"], "Держатель")
        holder += [h] + band_edges(th, h, hp, 0.022, M["thread"], "Строчка держателя", inset=0.003)
    holder.append(buckle(Vector((tx, ty - 0.037, 0.56)), (0, -1, 0), 0.019, M["metal"], M["strap"], "Пряжка держателя"))
    bpy.data.objects.remove(shell)
    seams = []
    for y in (-0.126, 0.126):
        seams.append(stitches(body, surface_path(body, (PACK_X - 0.06, y * 1.02, 0.69), (PACK_X - 0.06, y * 1.02, 0.45), 30),
                              M["thread"], "Шов рюкзака"))
    rim = []
    for k in range(41):
        a = k / 40
        rim.append(Vector((px - 0.05, (a - 0.5) * 0.17, 0.465)))
    seams.append(stitches(pocket, rim, M["thread"], "Строчка кармана рюкзака"))
    seams.append(stitches(flap, [Vector((px - 0.06, (k / 20 - 0.5) * 0.17, 0.575)) for k in range(21)], M["thread"], "Строчка клапана рюкзака"))
    return [body, lid, pocket, flap, roll, th, cap] + ends + ribs + ties + holder + seams


# ---------------------------------------------------------------- render

def look_at(obj, target):
    d = Vector(target) - obj.location
    obj.rotation_euler = d.to_track_quat("-Z", "Y").to_euler()


def stage(scene):
    world = bpy.data.worlds.new("Мир")
    scene.world = world
    world.use_nodes = True
    bg = next(n for n in world.node_tree.nodes if n.type == "BACKGROUND")
    bg.inputs["Color"].default_value = (*srgb("#223142"), 1)
    bg.inputs["Strength"].default_value = 0.0
    # Ambient comes from a separate light-only world colour.
    sun = bpy.data.lights.new("Солнце", "SUN")
    sun.energy = 6.0
    sun.color = srgb("#FFE9C8")
    sun.angle = math.radians(8)
    sun_obj = link(bpy.data.objects.new("Солнце", sun))
    sun_obj.rotation_euler = (math.radians(50), math.radians(-35), math.radians(-30))
    fill = bpy.data.lights.new("Заполняющий", "AREA")
    fill.energy = 45
    fill.size = 2.5
    fill.color = srgb("#EFE3CF")
    fill_obj = link(bpy.data.objects.new("Заполняющий", fill))
    fill_obj.location = (1.2, -2.2, 0.8)
    look_at(fill_obj, (0, 0, 0.5))
    rim = bpy.data.lights.new("Контровой", "AREA")
    rim.energy = 90
    rim.size = 1.0
    rim.color = srgb("#FFE2B0")
    rim_obj = link(bpy.data.objects.new("Контровой", rim))
    rim_obj.location = (-1.6, 1.4, 1.6)
    look_at(rim_obj, (0, 0, 0.6))
    ambient_world = world.node_tree.nodes.new("ShaderNodeBackground")
    ambient_world.inputs["Color"].default_value = (*srgb("#8A99AD"), 1)
    ambient_world.inputs["Strength"].default_value = 0.7
    lp = world.node_tree.nodes.new("ShaderNodeLightPath")
    mix = world.node_tree.nodes.new("ShaderNodeMixShader")
    out = next(n for n in world.node_tree.nodes if n.type == "OUTPUT_WORLD")
    world.node_tree.links.new(lp.outputs["Is Camera Ray"], mix.inputs["Fac"])
    world.node_tree.links.new(ambient_world.outputs["Background"], mix.inputs[1])
    world.node_tree.links.new(bg.outputs["Background"], mix.inputs[2])
    bg.inputs["Strength"].default_value = 1.0
    world.node_tree.links.new(mix.outputs["Shader"], out.inputs["Surface"])
    # Ground catcher for a contact shadow.
    bpy.ops.mesh.primitive_plane_add(size=6, location=(0, 0, 0))
    ground = bpy.context.active_object
    ground.name = "Земля"
    ground.is_shadow_catcher = True


SAMPLES = 128
CLOSEUPS = False


def render(scene, out_dir):
    scene.render.engine = "CYCLES"
    prefs = bpy.context.preferences.addons["cycles"].preferences
    for backend in ("OPTIX", "CUDA"):
        try:
            prefs.compute_device_type = backend
            prefs.get_devices()
            if any(d.type == backend for d in prefs.devices):
                for d in prefs.devices:
                    d.use = d.type == backend
                scene.cycles.device = "GPU"
                break
        except TypeError:
            continue
    scene.cycles.samples = SAMPLES
    scene.cycles.use_denoising = True
    scene.render.film_transparent = False
    # Standard keeps the golden orange of v2; AgX and PBR Neutral both
    # compress saturated highlights (the head turned peach). Exposure is
    # lowered a little so the lit faces do not clip.
    scene.view_settings.view_transform = "Standard"
    scene.view_settings.look = "None"
    scene.view_settings.exposure = -0.25
    scene.render.resolution_x = 1100
    scene.render.resolution_y = 1400
    cam_data = bpy.data.cameras.new("Камера")
    cam_data.type = "ORTHO"
    cam_data.ortho_scale = 1.32
    cam = link(bpy.data.objects.new("Камера", cam_data))
    scene.camera = cam
    views = {"side": ((0.0, -5.0, 0.52), (0.0, 0.0, 0.52)),
             "three-quarter": ((3.2, -3.8, 1.4), (0.0, 0.0, 0.5)),
             "back-quarter": ((-3.4, -3.6, 1.3), (0.0, 0.0, 0.5)),
             "front": ((5.0, -0.4, 0.6), (0.0, 0.0, 0.52))}
    if CLOSEUPS:
        # Close-ups for review: each hand and each boot, large.
        hy, by = HJ.arm_points("near")[2], HJ.LEG_Y
        wr = HJ.arm_points("near")[2]
        views = {
            "hand-near-side": ((wr.x + 0.05, -1.6, wr.z - 0.04), (wr.x + 0.01, wr.y, wr.z - 0.045), 0.24),
            "hand-near-front": ((1.6, wr.y - 0.25, wr.z - 0.0), (wr.x, wr.y, wr.z - 0.045), 0.24),
            "hand-far-front": ((1.6, -wr.y + 0.25, wr.z - 0.0), (wr.x, -wr.y, wr.z - 0.045), 0.24),
            "hand-near-back": ((-1.2, wr.y - 1.0, wr.z + 0.2), (wr.x, wr.y, wr.z - 0.045), 0.24),
            "boot-near-quarter": ((1.3, -1.3, 0.5), (0.04, -by, 0.08), 0.32),
            "boot-near-side": ((0.04, -1.6, 0.1), (0.04, -by, 0.09), 0.32),
            "boots-front": ((1.6, -0.1, 0.25), (0.04, 0.0, 0.09), 0.36),
            "boot-near-back": ((-1.3, -1.0, 0.4), (0.0, -by, 0.08), 0.32),
        }
        scene.render.resolution_x = 900
        scene.render.resolution_y = 900
        cam_data.ortho_scale = 0.3
    for name, view in views.items():
        pos, target = view[0], view[1]
        if len(view) > 2:
            cam_data.ortho_scale = view[2]
        cam.location = pos
        look_at(cam, target)
        scene.render.filepath = os.path.join(out_dir, f"hero-{name}.png")
        bpy.ops.render.render(write_still=True)


def main():
    args = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    out_dir = OUT
    global SAMPLES, CLOSEUPS
    CLOSEUPS = "--closeups" in args
    for a in args:
        if a.startswith("--out="):
            out_dir = a[6:]
        if a.startswith("--samples="):
            SAMPLES = int(a[10:])
    os.makedirs(out_dir, exist_ok=True)
    scene = reset()
    M = materials()
    groups = {"Голова": build_head(M), "Торс": build_torso(M), "Штаны": build_pants(M), "Рюкзак": build_backpack(M)}
    for side in ("near", "far"):
        groups["Рука " + side] = build_arm(M, side)
        groups["Ботинок " + side] = build_boot(M, side)
    for name, objs in groups.items():
        col = bpy.data.collections.new(name)
        scene.collection.children.link(col)
        for o in objs:
            for c in o.users_collection:
                c.objects.unlink(o)
            col.objects.link(o)
    tris = sum(sum(len(p.vertices) - 2 for p in o.data.polygons) for o in scene.objects if o.type == "MESH" and o.name != "Земля")
    print(f"HERO_BUILT parts={sum(len(v) for v in groups.values())} triangles={tris}")
    stage(scene)
    bpy.ops.wm.save_as_mainfile(filepath=os.path.join(out_dir, "hero.blend"))
    if "--render" in args:
        render(scene, out_dir)


main()
