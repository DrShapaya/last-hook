"""The hero for close-ups (the character screen): the detailed model itself,
lightly simplified, with every buckle, eyelet, lace, stitch and tread kept as
geometry. The climb's model (export_hero.py) bakes those into a flat texture,
which reads as painted on in a close-up.

1. Modifiers are applied, then each detailed object bakes its own colour,
   ambient occlusion and roughness into its vertices (no texture, no rays
   between objects: nothing to bleed and minutes instead of hours).
2. Each object is decimated where it does not show (big fabric surfaces to
   ~35%, small parts barely), to ~200k triangles in all.
3. Skeleton as export_hero.py; a detail is weighted as the part it sits on
   (the buckle on a sleeve follows the arm).
4. glTF: COLOR_0 = colour (rgb) + occlusion (a); TEXCOORD_0 = (wardrobe slot
   code + 0.5 if metal, roughness).

Run: blender --background docs/character/3d/hero.blend --python tools/blender/export_showcase.py
Output: game/assets/hero/model/hero.glb (the only hero model: the climb and
the character screen; export_hero.py keeps the skeleton and weights).
"""
import os
import sys
import time

import bpy
import numpy
from mathutils import Vector

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import export_hero as hero  # noqa: E402

OUT = os.path.join(hero.OUT_DIR, "hero.glb")
TARGET = 200000
CODES = {"head": 1, "jacket": 2, "boots": 3, "pants": 4, "gloves": 5, "backpack": 6}


def tris(o):
    return sum(len(p.vertices) - 2 for p in o.data.polygons)


def apply_modifiers(objects):
    depsgraph = bpy.context.evaluated_depsgraph_get()
    for o in objects:
        if not o.modifiers:
            continue
        mesh = bpy.data.meshes.new_from_object(o.evaluated_get(depsgraph))
        o.modifiers.clear()
        o.data = mesh


def bake_vertices(objects, kind, attribute):
    """Bakes into each object's own colour attribute (no selected-to-active)."""
    for o in objects:
        layer = o.data.color_attributes.get(attribute) or o.data.color_attributes.new(attribute, "FLOAT_COLOR", "CORNER")
        o.data.color_attributes.active_color = layer
    scene = bpy.context.scene
    bs = scene.render.bake
    bs.target = "VERTEX_COLORS"
    bs.use_selected_to_active = False
    metals = []
    if kind == "DIFFUSE":
        bs.use_pass_direct = False
        bs.use_pass_indirect = False
        bs.use_pass_color = True
        for m in bpy.data.materials:
            if m.use_nodes:
                for n in m.node_tree.nodes:
                    if n.type == "BSDF_PRINCIPLED" and n.inputs["Metallic"].default_value > 0:
                        metals.append((n, n.inputs["Metallic"].default_value))
                        n.inputs["Metallic"].default_value = 0.0
    bpy.ops.object.select_all(action="DESELECT")
    for o in objects:
        o.select_set(True)
    bpy.context.view_layer.objects.active = objects[0]
    started = time.time()
    bpy.ops.object.bake(type=kind)
    for n, value in metals:
        n.inputs["Metallic"].default_value = value
    print("BAKED", kind, round(time.time() - started, 1), flush=True)


def smooth_attribute(o, name, iterations):
    """Averages a corner colour attribute over each vertex, then over its
    neighbours a few times. Per-vertex samples of the procedural grime, wear
    and weave, and noisy occlusion, otherwise read as blotches and streaks."""
    mesh = o.data
    layer = mesh.color_attributes[name]
    n_loops = len(mesh.loops)
    n_verts = len(mesh.vertices)
    if n_loops == 0 or iterations <= 0:
        return
    corner = numpy.empty(n_loops * 4, numpy.float32)
    layer.data.foreach_get("color", corner)
    corner = corner.reshape(-1, 4)
    loop_vert = numpy.empty(n_loops, numpy.int32)
    mesh.loops.foreach_get("vertex_index", loop_vert)
    sums = numpy.zeros((n_verts, 4), numpy.float64)
    counts = numpy.zeros(n_verts, numpy.float64)
    numpy.add.at(sums, loop_vert, corner)
    numpy.add.at(counts, loop_vert, 1)
    values = sums / numpy.maximum(counts, 1)[:, None]
    edges = numpy.empty(len(mesh.edges) * 2, numpy.int32)
    mesh.edges.foreach_get("vertices", edges)
    a, b = edges[0::2], edges[1::2]
    for _ in range(iterations):
        acc = values.copy()
        num = numpy.ones(n_verts)
        numpy.add.at(acc, a, values[b])
        numpy.add.at(acc, b, values[a])
        numpy.add.at(num, a, 1)
        numpy.add.at(num, b, 1)
        values = acc / num[:, None]
    layer.data.foreach_set("color", values[loop_vert].astype(numpy.float32).ravel())


def metal_of(o):
    for slot in o.material_slots:
        m = slot.material
        if m and m.use_nodes:
            for n in m.node_tree.nodes:
                if n.type == "BSDF_PRINCIPLED" and n.inputs["Metallic"].default_value > 0.5:
                    return True
    return False


def owner_of(detail, sources):
    """The large part a detail lies closest to."""
    verts = detail.data.vertices
    step = max(1, len(verts) // 24)
    points = [detail.matrix_world @ verts[i].co for i in range(0, len(verts), step)]
    best, best_d = None, 1e9
    for src in sources:
        inverse = src.matrix_world.inverted()
        d = min(((src.matrix_world @ src.closest_point_on_mesh(inverse @ p)[1]) - p).length for p in points)
        if d < best_d:
            best, best_d = src, d
    return best


def pack(o, metal, code):
    """COLOR_0 = colour + occlusion; TEXCOORD_0 = (code + metal, roughness)."""
    mesh = o.data
    n = len(mesh.loops)
    col = numpy.empty(n * 4, numpy.float32)
    ao = numpy.empty(n * 4, numpy.float32)
    rough = numpy.empty(n * 4, numpy.float32)
    mesh.color_attributes["col"].data.foreach_get("color", col)
    mesh.color_attributes["ao"].data.foreach_get("color", ao)
    mesh.color_attributes["rough"].data.foreach_get("color", rough)
    col[3::4] = ao[0::4]
    out = mesh.color_attributes.new("color", "BYTE_COLOR", "CORNER")
    out.data.foreach_set("color", col)
    for name in ("col", "ao", "rough", "slot"):
        if name in mesh.color_attributes:
            mesh.color_attributes.remove(mesh.color_attributes[name])
    mesh.color_attributes.active_color = mesh.color_attributes["color"]
    mesh.color_attributes.render_color_index = mesh.color_attributes.find("color")
    while mesh.uv_layers:
        mesh.uv_layers.remove(mesh.uv_layers[0])
    uv = mesh.uv_layers.new(name="data")
    values = numpy.empty(n * 2, numpy.float32)
    values[0::2] = code + (0.5 if metal else 0.0)
    values[1::2] = rough[0::4]
    uv.data.foreach_set("uv", values)


def soften(o):
    """Takes the fine dents (the wear noise in the detailed shape) off the
    large fabric and leather parts; decimated, they turned into sharp pits,
    each lit as a dark dash. Folds and seams stay."""
    if tris(o) < 4000:
        return
    mod = o.modifiers.new("soften", "SMOOTH")
    mod.factor = 0.6
    mod.iterations = 4
    bpy.context.view_layer.objects.active = o
    bpy.ops.object.select_all(action="DESELECT")
    o.select_set(True)
    bpy.ops.object.modifier_apply(modifier=mod.name)


def decimate(o):
    t = tris(o)
    ratio = 1.0 if t < 800 else (0.6 if t < 4000 else 0.35)
    if ratio < 1.0:
        mod = o.modifiers.new("decimate", "DECIMATE")
        mod.ratio = ratio
        mod.use_collapse_triangulate = True
        bpy.context.view_layer.objects.active = o
        bpy.ops.object.select_all(action="DESELECT")
        o.select_set(True)
        bpy.ops.object.modifier_apply(modifier=mod.name)
    # Smooth normals again after collapsing: the fabric's soft wrinkles turned
    # into small facets with stale split normals, each lit as a dark dash.
    # Hard edges only where the surface really breaks (soles, buckles).
    bpy.context.view_layer.objects.active = o
    bpy.ops.object.select_all(action="DESELECT")
    o.select_set(True)
    if o.data.has_custom_normals:
        bpy.ops.mesh.customdata_custom_splitnormals_clear()
    bpy.ops.object.shade_smooth_by_angle(angle=0.7)


def main():
    hero.define_bones()
    hero.setup_cycles()
    scene = bpy.context.scene
    scene.cycles.samples = 64
    if scene.world is None:
        scene.world = bpy.data.worlds.new("Мир")
    scene.world.light_settings.distance = 0.05
    objects = [o for o in scene.objects if o.type == "MESH" and o.name != "Земля"]
    sources = [o for o in objects if hero.is_low_source(o)]
    apply_modifiers(objects)
    print("SOURCE_TRIS", sum(tris(o) for o in objects), flush=True)
    # The materials darken their creases with an occlusion node (8 samples):
    # sampled once per vertex it gives each vertex its own random darkening,
    # read as dirty smears. Off for the colour bake; the separate, smoothed
    # occlusion bake below darkens the creases instead.
    for m in bpy.data.materials:
        if m.use_nodes:
            for n in m.node_tree.nodes:
                if n.type == "AMBIENT_OCCLUSION":
                    n.inputs["Distance"].default_value = 0.0
    bake_vertices(objects, "DIFFUSE", "col")
    scene.cycles.samples = 256  # Occlusion per vertex is noisy at 64.
    bake_vertices(objects, "AO", "ao")
    scene.cycles.samples = 64
    bake_vertices(objects, "ROUGHNESS", "rough")
    for o in objects:
        # The thermos's camouflage is its design, not dirt: keep it sharp.
        smooth_attribute(o, "col", 0 if o.name.startswith("Термос") else 5)
        smooth_attribute(o, "ao", 8)
        smooth_attribute(o, "rough", 4)
    for o in objects:
        owner = o if o in sources else owner_of(o, sources)
        # A detail takes its part's slot (the hem and cuffs dye with the
        # jacket); the shader's hue window keeps straps and buckles theirs.
        pack(o, metal_of(o), CODES.get(hero.slot_of(owner.name), 0))
        if o in sources:
            soften(o)
        decimate(o)
        hero.weight_part(o, owner.name)
    total = sum(tris(o) for o in objects)
    print("SHOWCASE_TRIS", total, flush=True)
    bpy.ops.object.select_all(action="DESELECT")
    for o in objects:
        o.select_set(True)
    bpy.context.view_layer.objects.active = objects[0]
    bpy.ops.object.join()
    body = bpy.context.active_object
    body.name = "Витрина"
    mat = bpy.data.materials.new("Витрина")
    body.data.materials.clear()
    body.data.materials.append(mat)
    rig = hero.build_armature(body)
    for o in list(scene.objects):
        if o not in (body, rig):
            bpy.data.objects.remove(o)
    bpy.ops.object.select_all(action="DESELECT")
    body.select_set(True)
    rig.select_set(True)
    bpy.ops.export_scene.gltf(filepath=OUT, export_format="GLB", use_selection=True, export_apply=False,
                              export_skins=True, export_animations=False, export_yup=True,
                              export_vertex_color="ACTIVE", export_image_format="NONE", export_texcoords=True)
    print("SHOWCASE_EXPORTED", OUT, "tris", tris(body), flush=True)


main()
