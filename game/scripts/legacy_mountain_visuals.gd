class_name LegacyMountainVisuals
extends MountainVisuals

# Locations on generator v4 keep their side cliffs, but grips, shelves and
# hazards come from the shared MountainVisuals builder with the location's
# profile: no separate rectangular grip system remains. The mount is a flat
# stone plane at the depth the old boxes stood on.
const MOUNT_Z := 1.7

func wall_depth(_point: Vector2) -> float:
	return MOUNT_Z

func surface_normal(_point: Vector2) -> Vector3:
	return Vector3.BACK

func open_at(_point: Vector2) -> bool:
	# The legacy face has no stone above its grips: sky everywhere between cliffs.
	return true

func socket_margin() -> float:
	# No wall surrounds these grips, so a wide nest would read as a disc
	# hanging in the sky: keep only a thin collar of stone round the root.
	return .08

func zone_color(height: float) -> Color:
	return profile_at(height).rock_palette["base"]

func build_chunk(index: int, parent: Node3D) -> void:
	for slice in range(6):
		var sample := index*6+slice
		var y := sample*4.0
		var random := layout.rng(sample,32)
		var palette: Dictionary = profile_at(y).rock_palette
		for side in [-1,1]:
			var a := layout.outer_edge(y,side)
			var b := layout.outer_edge(y+4,side)
			var outer: float = side*10.0
			var surface := SurfaceTool.new()
			surface.begin(Mesh.PRIMITIVE_TRIANGLES)
			var vertices := [Vector3(minf(a,outer),y,-2),Vector3(maxf(a,outer),y,-2),Vector3(maxf(b,outer),y+4,-2),Vector3(minf(b,outer),y+4,-2)]
			for vertex_index in [0,2,1,0,3,2]: surface.add_vertex(vertices[vertex_index])
			var mesh := MeshInstance3D.new()
			mesh.mesh = surface.commit()
			var color := (palette["cool"] as Color).darkened(.35).lightened(random.randf_range(0,.1))
			mesh.material_override = world.mat("legacy_cliff_%s" % color.to_html(),color)
			mesh.material_override.cull_mode = BaseMaterial3D.CULL_DISABLED
			mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
			parent.add_child(mesh)
			world.box("Пласт скалы",Vector3(side*random.randf_range(5.5,6.5),y+random.randf_range(.5,3.5),-.8),Vector3(random.randf_range(1,2),random.randf_range(.35,1.2),.3),world.mat("legacy_facet_%s_%d" % [profile_at(y).id,sample%3],(palette["cool"] as Color).darkened(.2).lightened((sample%3)*.035)),parent)
		world.box("Дальний хребет",Vector3(random.randf_range(-2,2),y+2,-5),Vector3(random.randf_range(2,5),4.1,.1),world.mat("legacy_distant_%s" % profile_at(y).id,(palette["cool"] as Color).darkened(.5)),parent)
