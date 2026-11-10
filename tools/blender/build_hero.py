"""Build the 3D hero (docs/CHARACTER_3D_PLAN.md) in Blender from code.

The look follows game/assets/hero/pioneer/reference-v2.png: a rounded mustard
cube head with a side strap, green jacket with a hood collar, pocket and a
crossing strap, dark cargo pants with knee patches, hiking boots and a leather
backpack with a rolled mat and a thermos.

Each part is assembled from simple solids and fused into one smooth surface
with a voxel remesh, so primitives never show as seams. Straps are ribbons laid
on the part's surface. Materials are procedural (fabric weave, leather grain,
worn paint, brushed metal); baking them to textures for Godot comes later.

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

# Joint layout (hero units), shared with the rig later.
J = {
    "head": 0.72, "neck": 0.69, "shoulder": (-0.005, 0.655), "elbow": (0.0, 0.555), "wrist": (0.01, 0.46),
    "hip": 0.44, "knee": 0.255, "ankle": 0.085,
}
ARM_Y = 0.145  # Shoulder distance from the body centre line.
LEG_Y = 0.076  # Legs apart enough that the thighs never fuse into one piece (a web at wide strides).


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
    parts = [bpy.context.active_object, ball(r1, p1), ball(r2, p2)]
    return join(parts)


def torus(major, minor, loc, rot=(0, 0, 0), scale=(1, 1, 1)):
    bpy.ops.mesh.primitive_torus_add(major_radius=major, minor_radius=minor, location=loc, rotation=rot,
                                     major_segments=48, minor_segments=16)
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
    rim = [c + n * 0.03 + side * math.cos(a) * rx * 0.82 + up * math.sin(a) * rz * 0.82
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


def buckle(loc, normal, size, mat_metal, mat_strap, name):
    """A square metal buckle frame with its prong, facing `normal`."""
    n = Vector(normal).normalized()
    rot = Vector((0, 0, 1)).rotation_difference(n).to_euler()
    frame = rounded((size, size * 1.15, size * 0.18), loc, size * 0.12, rot)
    hole = cube((size * 0.62, size * 0.78, size), loc, rot)
    mod = frame.modifiers.new("hole", "BOOLEAN")
    mod.object = hole
    mod.operation = "DIFFERENCE"
    apply_all(frame)
    bpy.data.objects.remove(hole)
    finish(frame, mat_metal, name)
    return frame


# ---------------------------------------------------------------- parts

def build_head(M):
    top, h, d, w = 1.0, 0.285, 0.358, 0.30  # Height, depth along X, width along Y.
    cz = top - h / 2
    cx = 0.03
    core = rounded((d, w, h), (cx, 0, cz), 0.075, segments=8)
    sub = core.modifiers.new("sub", "SUBSURF")
    sub.levels = 2
    apply_all(core)
    finish(core, M["head"], "Голова")
    cloth_relief(core, 0.0015, 0.06)
    # A shallow handle-like ridge on top, as on the reference.
    ridge = rod((cx - 0.11, 0, top - 0.003), (cx + 0.07, 0, top - 0.003), 0.016, vertices=24)
    ridge.scale = (1, 1, 0.6)
    apply_all(ridge)
    finish(ridge, M["head"], "Ручка")
    # Eyes on the front (+X) face: dark rounded capsules with a glint.
    eyes = []
    face_x = cx + d / 2
    for y in (-0.045, 0.045):
        # A pill (capsule) flattened onto the face: fully round ends, as on v2.
        ec = Vector((face_x - 0.003, y * 1.1, cz + 0.035))
        e = rod(ec - Vector((0, 0, 0.026)), ec + Vector((0, 0, 0.026)), 0.023, vertices=32)
        e.scale = (0.3, 1, 1)
        apply_all(e)
        finish(e, M["eye"], "Глаз")
        g = ball(0.0095, (face_x + 0.0055, y * 1.1 - 0.004, cz + 0.062), (0.4, 0.95, 1.35), 16)
        finish(g, M["glint"], "Блик")
        eyes += [e, g]
    # Side strap with a big buckle on the near side (-Y), like a goggle band.
    strap_z = cz - 0.005
    path = [p for p in ring_path((cx, 0, strap_z), w / 2 + 0.02, d / 2 + 0.02, steps=96) if p.x < cx + d / 2 - 0.06]
    path.sort(key=lambda p: math.atan2(p.y, p.x - cx) % math.tau)
    strap = band(core, path, 0.045, 0.01, M["strap"], "Ремень головы", lift=0.003)
    seams = band_edges(core, strap, path, 0.045, M["thread"], "Строчка ремня головы")
    plate = rounded((0.11, 0.022, 0.095), (cx - 0.04, -w / 2 - 0.012, strap_z), 0.014)
    finish(plate, M["sole"], "Пластина")
    bk = buckle((cx - 0.035, -w / 2 - 0.026, strap_z), (0, -1, 0), 0.06, M["metal"], M["strap"], "Пряжка головы")
    tab = rounded((0.05, 0.016, 0.07), (cx - 0.075, -w / 2 - 0.03, strap_z), 0.01)
    finish(tab, M["strap"], "Язычок")
    return [core, ridge, strap, plate, bk, tab] + eyes + seams


def build_torso(M):
    z0, z1 = 0.39, J["neck"] + 0.005
    parts = [
        # A padded barrel, not a box: rounder edges, and a chest and a belly
        # that fill the jacket out (the owner: "the body is square").
        rounded((0.235, 0.26, z1 - z0 - 0.06), (0.0, 0, (z0 + z1) / 2 - 0.01), 0.1, segments=8),
        ball(0.128, (0.006, 0, 0.575), (1.0, 1.06, 0.82)),
        ball(0.12, (0.004, 0, 0.47), (1.02, 1.08, 0.78)),
        ball(0.06, (0.0, -ARM_Y + 0.05, J["shoulder"][1] - 0.02), (1.1, 1, 0.8)),
        ball(0.06, (0.0, ARM_Y - 0.05, J["shoulder"][1] - 0.02), (1.1, 1, 0.8)),
        # Slightly flared hem.
        rod((0.0, -0.11, z0 + 0.03), (0.0, 0.11, z0 + 0.03), 0.07, vertices=24),
    ]
    parts[-1].scale = (1.75, 1, 0.55)
    apply_all(parts[-1])
    jacket = fuse(parts, "Куртка", M["jacket"], smooth=12)
    # Folds where the jacket bunches: around the waist and under the arms.
    drape(jacket, (0, 0, 1), 0.028, 0.005, (0.0, 0, z0 + 0.07), 0.16)
    drape(jacket, (0.4, 0, 1), 0.03, 0.0035, (0.02, -0.13, 0.58), 0.09, seed=1.7)
    drape(jacket, (0.4, 0, 1), 0.03, 0.0035, (0.02, 0.13, 0.58), 0.09, seed=3.1)
    cloth_relief(jacket, 0.0012, 0.06)
    # Hood folded into a tall soft collar around the neck, open at the front.
    hood = fuse([torus(0.082, 0.04, (-0.012, 0, z1 + 0.0), scale=(1.05, 1.15, 1.45)),
                 ball(0.065, (-0.075, 0, z1 + 0.01), (1.0, 1.45, 0.8))], "Капюшон", M["jacket_dark"])
    drape(hood, (0, 0, 1), 0.02, 0.003, (-0.02, 0, z1), 0.12, seed=0.6)
    cloth_relief(hood, 0.0012, 0.05)
    neck = rod((0.01, 0, z1 - 0.04), (0.012, 0, J["head"] + 0.03), 0.036, vertices=24)
    finish(neck, M["skin"], "Шея")
    # Chest pocket with a flap and a press stud on the near side.
    ok, loc, n, _ = jacket.closest_point_on_mesh(Vector((0.12, -0.12, 0.475)))
    face = Vector((0, -1, 0)).rotation_difference(n).to_euler()
    pocket = rounded((0.074, 0.016, 0.078), loc + n * 0.004, 0.008, rot=face)
    finish(pocket, M["jacket"], "Карман")
    up = Vector((0, 0, 1))
    flap = rounded((0.08, 0.02, 0.028), loc + n * 0.009 + up * 0.036, 0.007, rot=face)
    finish(flap, M["jacket_dark"], "Клапан")
    stud = ball(0.0065, loc + n * 0.021 + up * 0.03, (1, 1, 1), 12)
    finish(stud, M["metal"], "Кнопка")
    side = n.cross(up).normalized()
    pocket_rim = [loc + n * 0.03 + side * 0.033 * a + up * zz for a, zz in
                  [(-1, 0.022), (-1, -0.035), (1, -0.035), (1, 0.022)]]
    pocket_rim = [pocket_rim[i].lerp(pocket_rim[i + 1], k / 8) for i in range(3) for k in range(9)]
    pocket_seam = stitches(pocket, pocket_rim, M["thread_dark"], "Строчка кармана куртки")
    # Zip line down the front.
    zip_path = surface_path(jacket, (0.14, -0.01, z1 - 0.03), (0.14, -0.01, z0 + 0.02), 20)
    zipper = band(jacket, zip_path, 0.01, 0.003, M["jacket_dark"], "Планка молнии")
    teeth = stitches(jacket, zip_path, M["metal"], "Зубцы молнии", spacing=0.0045, length=0.006, radius=0.0016, lift=0.0035)
    hem_path = ring_path((0.0, 0, z0 + 0.028), 0.138, 0.128, steps=72)
    hem = band(jacket, hem_path, 0.034, 0.006, M["jacket_dark"], "Подол")
    hem_seams = band_edges(jacket, hem, hem_path, 0.034, M["thread_dark"], "Строчка подола")
    # Backpack strap: over the near shoulder, down the chest to the side.
    strap_path = surface_path(jacket, (-0.05, -0.11, z1 - 0.005), (0.07, -0.125, 0.47), 30, bulge=(0.03, -0.03, 0.02))
    strap = band(jacket, strap_path, 0.034, 0.008, M["strap"], "Лямка")
    strap_seams = band_edges(jacket, strap, strap_path, 0.034, M["thread"], "Строчка лямки")
    flap_seam = stitches(flap, [loc + n * 0.04 + up * 0.026 + side * k for k in (-0.035, 0.035)],
                         M["thread_dark"], "Строчка клапана")
    # Chest strap across the front with a buckle, and a leather zip pull.
    chest_path = surface_path(jacket, (0.08, -0.13, 0.6), (0.08, 0.13, 0.6), 30, bulge=(0.08, 0, 0))
    chest = band(jacket, chest_path, 0.022, 0.006, M["strap"], "Нагрудный ремень")
    chest_seams = band_edges(jacket, chest, chest_path, 0.022, M["thread"], "Строчка нагрудного ремня", inset=0.003)
    ok, cl, cn, _ = jacket.closest_point_on_mesh(Vector((0.16, -0.02, 0.6)))
    chest_bk = buckle(cl + cn * 0.01, cn, 0.026, M["metal"], M["strap"], "Пряжка нагрудного ремня")
    ok, zl, zn, _ = jacket.closest_point_on_mesh(Vector((0.16, -0.01, z1 - 0.04)))
    pull = rounded((0.006, 0.012, 0.03), zl + zn * 0.006 - Vector((0, 0, 0.018)), 0.003)
    finish(pull, M["strap"], "Бегунок")
    # On the strap itself, down on the chest: at the shoulder (y -0.14) the
    # buckle sat in the arm's joint and poked out of the sleeve.
    ok, bl, bn, _ = jacket.closest_point_on_mesh(strap_path[int(len(strap_path) * 0.62)])
    bk = buckle(bl + bn * 0.012, bn, 0.03, M["metal"], M["strap"], "Пряжка лямки")
    return ([jacket, hood, neck, pocket, flap, stud, zipper, teeth, hem, strap, bk, flap_seam, pocket_seam, chest, chest_bk, pull]
            + hem_seams + strap_seams + chest_seams)


def arm_points(side):
    y = -ARM_Y if side == "near" else ARM_Y
    s, e, w = J["shoulder"], J["elbow"], J["wrist"]
    return Vector((s[0], y, s[1])), Vector((e[0] + 0.012, y - 0.01 * (1 if side == "near" else -1), e[1])), \
        Vector((w[0] + 0.02, y - 0.012 * (1 if side == "near" else -1), w[1]))


def build_arm(M, side):
    sh, el, wr = arm_points(side)
    sleeve = fuse([rod(sh, el, 0.053, 0.049), rod(el, wr, 0.049, 0.047), ball(0.055, sh)],
                  "Рукав " + side, M["jacket"])
    folds(sleeve, el, (wr - sh), 3, 0.022, 0.003, 0.035)
    drape(sleeve, (wr - sh), 0.024, 0.0038, (sh + el) / 2, 0.06, seed=0.4 if side == "near" else 2.2)
    drape(sleeve, (wr - sh), 0.02, 0.0032, (el + wr) / 2, 0.055, seed=1.3 if side == "near" else 2.9)
    cloth_relief(sleeve, 0.001, 0.05)
    # Cuff: a leather strap with a buckle just above the wrist.
    cuff_c = wr + (el - wr).normalized() * 0.02
    path = ring_path(cuff_c, 0.052, 0.052)
    cuff = band(sleeve, path, 0.032, 0.008, M["strap"], "Манжета " + side)
    cuff_seams = band_edges(sleeve, cuff, path, 0.032, M["thread"], "Строчка манжеты")
    out = Vector((0, -1 if side == "near" else 1, 0))
    bk = buckle(cuff_c + out * 0.056, out, 0.028, M["metal"], M["strap"], "Пряжка манжеты " + side)
    shoulder_seam = stitches(sleeve, ring_path(sh - Vector((0, 0, 0.035)), 0.056, 0.056, steps=64), M["thread_dark"], "Шов плеча")
    glove = build_glove(M, wr, (wr - el).normalized(), side)
    return [sleeve, cuff, bk, shoulder_seam] + cuff_seams + glove


def build_glove(M, wrist, down, side):
    """A gloved hand hanging relaxed, built like a real hand.

    Seen from the side we look at the back of the hand: the four fingers sit
    in a row from front (index) to back (little finger) and curl toward the
    thigh; the thumb lies along the index finger. Each finger has three
    segments with knuckles, the leather keeps small gaps between fingers.
    """
    side_y = -1 if side == "near" else 1
    inward = Vector((0, -side_y, 0))  # Toward the body: the palm faces it.
    fwd = (Vector((1, 0, 0)) - down * Vector((1, 0, 0)).dot(down)).normalized()
    palm_c = wrist + down * 0.05
    # Back of the hand: a broad flat block, wider than the wrist, like a glove.
    # Rotation is set at creation: after apply_all the origin is the world
    # origin, and rotating then would swing the block out of the hand.
    palm = rounded((0.088, 0.046, 0.074), palm_c, 0.02, rot=Vector((0, 0, 1)).rotation_difference(down).to_euler(), segments=5)
    parts = [rod(wrist - down * 0.015, wrist + down * 0.012, 0.031, 0.033, 24), palm]
    # Index, middle, ring, little: offset along the row, length, thickness.
    fingers = [(0.03, 1.0, 0.0108), (0.01, 1.08, 0.0112), (-0.01, 1.02, 0.0108), (-0.03, 0.85, 0.0096)]
    for row, length, r in fingers:
        knuckle = palm_c + down * 0.034 + fwd * row - inward * 0.006
        parts.append(ball(r * 1.2, knuckle))  # Knuckle bump on the back of the hand.
        # Relaxed curl: down, then in toward the palm, the tip tucked under.
        p1 = knuckle + down * 0.028 * length
        p2 = p1 + (down * 0.45 + inward).normalized() * 0.024 * length
        p3 = p2 + (-down * 0.35 + inward).normalized() * 0.017 * length
        parts += [rod(knuckle, p1, r, r * 0.96, 16), rod(p1, p2, r * 0.96, r * 0.92, 16), rod(p2, p3, r * 0.92, r * 0.85, 16)]
    # Thumb: a thick pad from the inner front of the palm, tip resting on the index finger.
    t0 = palm_c + fwd * 0.036 + inward * 0.016 + down * 0.008
    t1 = t0 + (down + fwd * 0.3 + inward * 0.3).normalized() * 0.026
    t2 = t1 + (down * 0.7 + inward * 0.5).normalized() * 0.018
    parts += [ball(0.019, t0), rod(t0, t1, 0.0145, 0.0135, 16), rod(t1, t2, 0.0135, 0.012, 16)]
    glove = fuse(parts, "Перчатка " + side, M["glove"], voxel=0.0022, smooth=4)
    # Seam along the back of the hand and stitched cuff edge of the glove.
    seams = [stitches(glove, [palm_c - inward * 0.035 + fwd * x - down * 0.012 for x in (0.04, 0.0, -0.04)],
                      M["thread"], "Строчка перчатки " + side),
             stitches(glove, [wrist + down * 0.02 + fwd * 0.046 * math.cos(t) + Vector((0, 0.03 * math.sin(t), 0))
                              for t in [i / 48 * math.tau for i in range(49)]], M["thread"], "Край перчатки " + side)]
    return [glove] + seams


def build_pants(M):
    hip = J["hip"]
    pelvis = rounded((0.19, 0.21, 0.09), (0.0, 0, hip + 0.005), 0.06, segments=6)
    legs = []
    hem_z = 0.15  # The pant leg ends just over the boot top, like v2.
    for side, y in (("near", -LEG_Y), ("far", LEG_Y)):
        h = Vector((-0.005, y, hip))
        k = Vector((0.012, y, J["knee"]))
        a = Vector((0.004, y, hem_z))
        legs += [rod(h, k, 0.068, 0.062), rod(k, a, 0.062, 0.066)]
    pants = fuse([pelvis] + legs, "Штаны", M["pants"])
    for v in pants.data.vertices:  # A flat hem instead of a rounded cap.
        if v.co.z < hem_z:
            v.co.z = hem_z
    pants.data.update()
    for side, y in (("near", -LEG_Y), ("far", LEG_Y)):
        folds(pants, (0.0, y, J["knee"]), (0, 0, 1), 3, 0.02, 0.0035, 0.032)
        # Cloth bunching above the boots and loose folds down the shin and thigh.
        folds(pants, (0.0, y, hem_z + 0.035), (0, 0, 1), 3, 0.016, 0.004, 0.035)
        drape(pants, (0.3, 0, 1), 0.03, 0.004, (0.0, y, (J["knee"] + hem_z) / 2), 0.08, seed=0.7 if side == "near" else 2.4)
        drape(pants, (-0.3, 0, 1), 0.035, 0.0035, (0.0, y, (hip + J["knee"]) / 2), 0.09, seed=1.9 if side == "near" else 3.6)
    cloth_relief(pants, 0.0015, 0.05)
    extra = []
    for side, y in (("near", -LEG_Y), ("far", LEG_Y)):
        # Knee patch on the front of the knee, slightly padded.
        patch, rim = oval_patch(pants, (0.12, y - (0.02 if side == "near" else -0.02), J["knee"] + 0.01), 0.03, 0.044,
                                0.007, M["patch"], "Наколенник " + side, lift=0.0045)
        extra.append(stitches(patch, rim, M["thread"], "Строчка наколенника " + side))
        # Thigh strap with a buckle.
        tz = hip - 0.085
        path = ring_path((0.0, y, tz), 0.078, 0.078)
        strap = band(pants, path, 0.026, 0.007, M["strap"], "Ремень бедра " + side)
        out = Vector((0, -1 if side == "near" else 1, 0))
        bk = buckle(Vector((0.0, y, tz)) + out * 0.084, out, 0.024, M["metal"], M["strap"], "Пряжка бедра " + side)
        extra += [patch, strap, bk]
    # Cargo pocket on the outer side of the near thigh, stitched, with a flap.
    ok, loc, n, _ = pants.closest_point_on_mesh(Vector((0.0, -LEG_Y - 0.09, hip - 0.15)))
    cargo = rounded((0.075, 0.022, 0.085), loc + n * 0.006, 0.012)
    finish(cargo, M["pants"], "Карман брюк")
    cargo_flap = rounded((0.08, 0.026, 0.028), loc + n * 0.01 + Vector((0, 0, 0.045)), 0.008)
    finish(cargo_flap, M["pants"], "Клапан брюк")
    corners = [(-0.03, 0.03), (-0.03, -0.035), (0.03, -0.035), (0.03, 0.03)]
    rim = []
    for (x0, z0), (x1, z1) in zip(corners, corners[1:]):
        rim += [loc + n * 0.03 + Vector((x0 + (x1 - x0) * k / 8, 0, z0 + (z1 - z0) * k / 8)) for k in range(9)]
    cargo_seam = stitches(cargo, rim, M["thread_pants"], "Строчка кармана")
    extra += [cargo, cargo_flap, cargo_seam]
    for y in (-LEG_Y - 0.065, LEG_Y + 0.065):
        extra.append(stitches(pants, surface_path(pants, (0.0, y, hip - 0.03), (0.0, y * 0.95, hem_z + 0.01), 40),
                              M["thread_pants"], "Боковой шов"))
    for y in (-LEG_Y, LEG_Y):  # Stitched hem.
        extra.append(stitches(pants, ring_path((0.004, y, hem_z + 0.012), 0.068, 0.068, steps=64), M["thread_pants"], "Строчка низа"))
    belt_path = ring_path((-0.005, 0, hip + 0.035), 0.108, 0.112)
    belt = band(pants, belt_path, 0.028, 0.007, M["strap"], "Пояс")
    return [pants, belt] + extra


def build_boot(M, side):
    y = -LEG_Y if side == "near" else LEG_Y
    shaft = rod((0.0, y, 0.075), (0.0, y, 0.165), 0.06, 0.056, 32)  # Its round bottom stays inside the sole.
    foot = rounded((0.19, 0.112, 0.078), (0.04, y, 0.05), 0.04, segments=6)
    toe = ball(0.05, (0.093, y, 0.06), (1.05, 1, 0.8))
    upper = fuse([shaft, foot, toe], "Ботинок " + side, M["boot"], voxel=0.004)
    cloth_relief(upper, 0.0012, 0.03)
    # Chunky sole: a stitched welt band, the sole, a heel block and deep lugs.
    welt_band = rounded((0.204, 0.116, 0.014), (0.043, y, 0.04), 0.006)
    finish(welt_band, M["welt"], "Рант подошвы " + side)
    sole = rounded((0.208, 0.12, 0.03), (0.043, y, 0.022), 0.012)
    finish(sole, M["sole"], "Подошва " + side)
    heel = rounded((0.06, 0.116, 0.02), (-0.03, y, 0.004), 0.006)
    finish(heel, M["sole"], "Каблук " + side)
    lugs = [heel]
    for i in range(6):
        lug = rounded((0.016, 0.118, 0.018), (0.02 + i * 0.022, y, 0.004), 0.005, segments=2)
        finish(lug, M["sole"], "Протектор")
        lugs.append(lug)
    collar = torus(0.056, 0.011, (0.0, y, 0.162), scale=(1, 1, 0.9))  # Padded top, under the pant hem.
    finish(collar, M["glove"], "Отворот " + side)
    welt = stitches(welt_band, [Vector((0.043 + math.cos(a) * 0.116, y + math.sin(a) * 0.071, 0.042)) for a in
                                [i / 96 * math.tau for i in range(97)]], M["thread"], "Рант " + side)
    cap = [Vector((0.075 + 0.02 * math.cos(t), y + 0.07 * math.sin(t), 0.07 + 0.012 * math.cos(t)))
           for t in [math.pi / 2 + i / 24 * math.pi for i in range(25)]]
    toe_cap = stitches(upper, cap, M["thread"], "Носок " + side)
    laces = []
    holes = []
    for i in range(5):  # Up the shaft front to the pant hem, big metal eyelets like v2.
        z = 0.142 - i * 0.017
        x = 0.07 + i * 0.008
        row = []
        for dy in (-0.024, 0.024):
            ok, loc, n, _ = upper.closest_point_on_mesh(Vector((x, y + dy, z)))
            eyelet = torus(0.0095, 0.0032, loc + n * 0.002, rot=Vector((0, 0, 1)).rotation_difference(n).to_euler())
            finish(eyelet, M["metal"], "Люверс")
            laces.append(eyelet)
            row.append((loc, n))
        holes.append(row)
    for upper_row, lower_row in zip(holes, holes[1:]):
        for (pa, na), (pb, nb) in ((upper_row[0], lower_row[1]), (upper_row[1], lower_row[0])):
            lace = rod(pa + na * 0.006, pb + nb * 0.006, 0.0042, vertices=10)
            finish(lace, M["lace"], "Шнурок")
            laces.append(lace)
    top = holes[0]
    centre = (top[0][0] + top[1][0]) / 2 + top[0][1] * 0.008
    for dy in (-1, 1):
        loop = torus(0.013, 0.0038, centre + Vector((0.006, dy * 0.014, 0.006)), rot=(0, math.radians(70), 0))
        finish(loop, M["lace"], "Бант")
        laces.append(loop)
    return [upper, sole, collar, welt, toe_cap] + lugs + laces


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


def build_backpack(M):
    back_x = -0.105  # The hero's back surface.
    bx = back_x - 0.095
    # One soft leather bag from top to bottom: the box with a ball under it
    # read as half a crate, half a sack. A pillow filling the whole body
    # bulges it evenly; the bottom rounds off like a loaded pack.
    body = rounded((0.18, 0.25, 0.28), (bx, 0, 0.55), 0.075, segments=8)
    fill = ball(0.13, (bx - 0.012, 0, 0.545), (0.78, 1.0, 1.04))
    body = fuse([body, fill], "Рюкзак", M["leather"], voxel=0.004, smooth=10)
    drape(body, (0, 0, 1), 0.035, 0.0025, (bx - 0.06, 0, 0.5), 0.14, seed=0.9)
    cloth_relief(body, 0.002, 0.04)
    # Lid over the top, a little wider than the body.
    lid = rounded((0.2, 0.27, 0.045), (bx - 0.005, 0, 0.69), 0.02, segments=4)
    finish(lid, M["strap"], "Крышка рюкзака")
    # Front pocket: a box with a slight bulge, not a pill.
    pocket = rounded((0.075, 0.205, 0.16), (bx - 0.13, 0, 0.5), 0.02, segments=4)
    sub = pocket.modifiers.new("sub", "SUBSURF")
    sub.levels = 1
    apply_all(pocket)
    finish(pocket, M["leather"], "Карман рюкзака")
    flap = rounded((0.082, 0.212, 0.055), (bx - 0.133, 0, 0.585), 0.015, segments=4)
    finish(flap, M["strap"], "Клапан рюкзака")
    # Rolled mat on the lid, with spiral ends and two straps.
    roll_x, roll_z, roll_r = bx - 0.005, 0.757, 0.052
    roll = rod((roll_x, -0.13, roll_z), (roll_x, 0.13, roll_z), roll_r, vertices=40)
    apply_all(roll)  # Vertices in world space, so y is along the roll.
    for end in roll.data.vertices:  # Flat ends: a rolled mat, not a capsule.
        end.co.y = max(-0.13, min(0.13, end.co.y))
    roll.data.update()
    roll = fuse([roll], "Коврик", M["mat"], voxel=0.0035, smooth=4)
    ends = [spiral_end((roll_x, y, roll_z), y, roll_r * 0.95, 3.2, M["jacket_dark"], "Торец коврика") for y in (-0.132, 0.132)]
    ties = []
    for y in (-0.075, 0.075):
        path = [Vector((roll_x + math.cos(a) * 0.06, y, roll_z + math.sin(a) * 0.06))
                for a in [i / 40 * math.tau for i in range(41)]]
        tie = band(roll, path, 0.022, 0.006, M["strap"], "Стяжка")
        ties += [tie] + band_edges(roll, tie, path, 0.022, M["thread"], "Строчка стяжки", inset=0.003)
        ties.append(buckle(Vector((roll_x - 0.06, y, roll_z)), (-1, 0, 0), 0.024, M["metal"], M["strap"], "Пряжка стяжки"))
    # Vertical straps over the pocket with buckles.
    px = bx - 0.168
    for y in (-0.06, 0.06):
        path = surface_path(pocket, (px - 0.01, y, 0.6), (px - 0.01, y, 0.43), 14)
        strap = band(pocket, path, 0.02, 0.006, M["strap"], "Ремешок кармана")
        ties += [strap] + band_edges(pocket, strap, path, 0.02, M["thread"], "Строчка ремешка", inset=0.003)
        ties.append(buckle(Vector((px - 0.004, y, 0.53)), (-1, 0, 0), 0.022, M["metal"], M["strap"], "Пряжка кармана"))
    # Thermos: worn green paint, ribbed metal cap, held by two wide straps.
    tx, ty = bx + 0.01, -0.158
    th = rod((tx, ty, 0.43), (tx, ty, 0.6), 0.03, vertices=32)
    finish(th, M["thermos"], "Термос")
    cap = rod((tx, ty, 0.6), (tx, ty, 0.64), 0.028, vertices=32)
    finish(cap, M["metal"], "Крышка термоса")
    ribs = [finish(torus(0.0285, 0.0025, (tx, ty, z)), M["metal"], "Рифление") for z in (0.61, 0.62, 0.63)]
    holder = []
    for z in (0.465, 0.555):
        hp = ring_path((tx, ty, z), 0.033, 0.033)
        h = band(th, hp, 0.024, 0.006, M["strap"], "Держатель")
        holder += [h] + band_edges(th, h, hp, 0.024, M["thread"], "Строчка держателя", inset=0.003)
    holder.append(buckle(Vector((tx, ty - 0.038, 0.555)), (0, -1, 0), 0.02, M["metal"], M["strap"], "Пряжка держателя"))
    # Seams: pocket rim, flap edge, body sides.
    seams = []
    fx = px - 0.004
    seams.append(stitches(flap, [Vector((fx - 0.02, -0.1 + i * 0.01, 0.562)) for i in range(21)], M["thread"], "Строчка клапана рюкзака"))
    corners = [(-0.095, 0.57), (-0.095, 0.43), (0.095, 0.43), (0.095, 0.57)]
    rim = []
    for (y0, z0), (y1, z1) in zip(corners, corners[1:]):
        rim += [Vector((fx - 0.03, y0 + (y1 - y0) * k / 10, z0 + (z1 - z0) * k / 10)) for k in range(11)]
    seams.append(stitches(pocket, rim, M["thread"], "Строчка кармана рюкзака"))
    for y in (-0.128, 0.128):
        seams.append(stitches(body, surface_path(body, (bx - 0.08, y, 0.67), (bx - 0.08, y, 0.43), 30),
                              M["thread"], "Шов рюкзака"))
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
    scene.cycles.samples = 128
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
             "back-quarter": ((-3.4, -3.6, 1.3), (0.0, 0.0, 0.5))}
    for name, (pos, target) in views.items():
        cam.location = pos
        look_at(cam, target)
        scene.render.filepath = os.path.join(out_dir, f"hero-{name}.png")
        bpy.ops.render.render(write_still=True)


def main():
    args = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    out_dir = OUT
    for a in args:
        if a.startswith("--out="):
            out_dir = a[6:]
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
