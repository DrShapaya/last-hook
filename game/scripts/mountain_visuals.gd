class_name MountainVisuals
extends RefCounted

# Shared visual API for every mountain style. Subclasses describe their stone
# (wall_depth, surface_normal, open sky); grips, shelves, hazards and decor are
# then built once here, from a SurfaceMount and the place's GripBiomeProfile.
# Gameplay polygons are never changed by anything in this file.

var world: Node3D
var layout: MountainLayout
var quality := "balanced"
var stone_material := ShaderMaterial.new()
var obstacle_material := ShaderMaterial.new()
const ROCK_COLORS := [Color("657478"),Color("777667"),Color("929387"),Color("3b4c59")]
# A grip's rim stands this far in front of its mount; shelves and hazards
# use the same rule, so every object has one contact with the stone.
const GRIP_STANDOFF := .30
const LEDGE_STANDOFF := .30
const OBSTACLE_STANDOFF := .32
# Soft, cool contact shade for styles without a baked occlusion term.
const CONTACT_SHADER := "shader_type spatial; render_mode unshaded, cull_disabled, blend_mix, depth_draw_never, shadows_disabled; uniform float opacity = .22; void fragment(){ vec2 p=UV*2.0-1.0; float d=length(p); ALBEDO=vec3(.07,.09,.12); ALPHA=smoothstep(1.0,.15,d)*opacity; }"

func _init(owner_world: Node3D, source: MountainLayout) -> void:
	world = owner_world
	layout = source
	stone_material.shader = preload("res://shaders/massif_rock.gdshader")
	stone_material.set_shader_parameter("snow_override",0.0)
	stone_material.set_shader_parameter("facet_strength",1.0)
	stone_material.set_shader_parameter("detail_strength",.45)
	stone_material.set_shader_parameter("material_tint",1.0)
	obstacle_material.shader = stone_material.shader
	obstacle_material.set_shader_parameter("snow_override",0.0)
	obstacle_material.set_shader_parameter("material_tint",1.0)
	obstacle_material.set_shader_parameter("detail_strength",.6)

func set_quality(value: String) -> void:
	quality = value if value in ["high","balanced","battery"] else "balanced"

func profile_at(height: float) -> GripBiomeProfile:
	return GripBiomeProfile.named(layout.profile_id_at(height))

func rock_color() -> Color:
	return ROCK_COLORS[layout.location%4]

func zone_color(height: float) -> Color:
	if layout.location!=0: return rock_color()
	var colors := [Color("657478"),Color("77786f"),Color("888779"),Color("91aeb9"),Color("796660"),Color("9aa5b5")]
	var t := clampf(height/20,0,5)
	var index := mini(int(t),4)
	return colors[index].lerp(colors[index+1],smoothstep(.65,1.0,t-index))

func vertex(point: Vector2) -> Vector3:
	var depth := 1.1+.24*sin(point.x*1.7+point.y*.6)+.16*sin(point.y*2.1-point.x)
	return Vector3(point.x,point.y,depth)

# --- Mounts -----------------------------------------------------------------------

func wall_depth(point: Vector2) -> float:
	return vertex(point).z

func surface_normal(point: Vector2) -> Vector3:
	var dx := (wall_depth(point+Vector2(.08,0))-wall_depth(point-Vector2(.08,0)))/.16
	var dy := (wall_depth(point+Vector2(0,.08))-wall_depth(point-Vector2(0,.08)))/.16
	return Vector3(-dx,-dy,1).normalized()

func open_at(point: Vector2) -> bool:
	return layout.rock_field(point)<0

func support_root_of(_object: Dictionary) -> Vector2:
	return Vector2.INF

# Widest ring of the stone nest outside an object's root.
func socket_margin() -> float:
	return .35

# How far a grip's stone leans from the host rock to its type's material.
func grip_tint() -> float:
	return .55

# How dark the socket ring around an object is, as a share of the profile's.
func socket_shade() -> float:
	return 1.0

# Mountains that build a shelf of the face under every find skip pedestals.
func provides_find_shelves() -> bool:
	return false

# Mount of a find: it stands well in front of deep stone, so the hero never
# passes behind it; a pedestal reaches back to the wall.
func mount_find(find: Dictionary) -> SurfaceMount:
	var point: Vector2 = find["pos"]
	var wall_z := wall_depth(point)
	return mount_at(point,Vector2(.9,.7),{},clampf(wall_z+.75,1.7,2.4)-wall_z)

# Styles with occlusion baked into the stone need no separate contact decal.
func baked_contact() -> bool:
	return false

func mount_at(point: Vector2, footprint: Vector2, object: Dictionary = {}, standoff: float = GRIP_STANDOFF) -> SurfaceMount:
	# The only place a mount is made: from a layout point that was already
	# verified by the generator. Nothing here may move that point.
	var mount := SurfaceMount.new()
	var z := wall_depth(point)
	mount.layout_point = point
	mount.standoff = standoff
	mount.position = Vector3(point.x,point.y,z)
	mount.normal = surface_normal(point)
	var along := Vector3.RIGHT-mount.normal*mount.normal.x
	mount.tangent = along.normalized() if along.length_squared()>.0001 else Vector3.RIGHT
	mount.depth = clampf(footprint.y*.5+.25,.25,.9)
	var root := support_root_of(object) if not object.is_empty() else Vector2.INF
	mount.support_root = Vector3(root.x,root.y,wall_depth(root)) if root.is_finite() else mount.position-mount.normal*mount.depth
	mount.cavity_scale = footprint*.5+Vector2(.22,.18)
	var open := 0
	for step in range(1,4):
		if open_at(point+Vector2(0,footprint.y*.5+step*.6)): open += 1
	mount.exposure = open/3.0
	var h := .35
	var around := wall_depth(point+Vector2(h,0))+wall_depth(point-Vector2(h,0))+wall_depth(point+Vector2(0,h))+wall_depth(point-Vector2(0,h))
	mount.curvature = clampf((4.0*z-around)/(h*h)*.1,-1,1)
	mount.profile = profile_at(point.y)
	mount.biome_material = mount.profile.material_name(GripSpec.STONE)
	mount.surface_color = zone_color(point.y)
	mount.chip_color = mount.surface_color.lerp(mount.profile.rock_palette["warm"],.35).lightened(.08)
	return mount

func sample_point(x: int, y: int) -> Vector2:
	var random := layout.rng(x*9781+y*6271,66)
	var jitter := Vector2(random.randf_range(-.42,.42),random.randf_range(-.42,.42))
	return Vector2(-20.0+x*1.25,y*1.2)+jitter*.72

func _triangle(surface: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, color: Color) -> void:
	for p in [a,b,c]:
		surface.set_color(color)
		surface.add_vertex(p)

func _clip_triangle(surface: SurfaceTool, points: Array[Vector2], fields: Array[float], color: Color) -> void:
	var polygon: Array[Vector2] = []
	var cuts: Array[Vector2] = []
	for i in range(3):
		var j := (i+1)%3
		if fields[i]>=0: polygon.append(points[i])
		if (fields[i]>=0)!=(fields[j]>=0):
			var p := points[i].lerp(points[j],fields[i]/(fields[i]-fields[j]))
			polygon.append(p)
			cuts.append(p)
	for i in range(1,polygon.size()-1):
		_triangle(surface,vertex(polygon[0]),vertex(polygon[i]),vertex(polygon[i+1]),color)
	# Do not close rock-field holes with dark triangles. They are deliberate
	# mountain voids and must reveal the continuous sky backdrop behind them.

func build_chunk(index: int, parent: Node3D) -> void:
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	var samples: Dictionary = {}
	var sample_positions: Dictionary = {}
	var bottom := index*24.0
	for x in range(33):
		for y in range(21):
			var point := sample_point(x,index*20+y)
			samples[Vector2i(x,y)] = layout.rock_field(point)
			sample_positions[Vector2i(x,y)] = point
	for x in range(32):
		for y in range(20):
			var a: Vector2 = sample_positions[Vector2i(x,y)]
			var b: Vector2 = sample_positions[Vector2i(x+1,y)]
			var c: Vector2 = sample_positions[Vector2i(x+1,y+1)]
			var d: Vector2 = sample_positions[Vector2i(x,y+1)]
			var random := layout.rng(index*1000+x*17+y,65)
			var color := zone_color((a.y+c.y)*.5).lightened(random.randf_range(-.055,.055))
			_clip_triangle(surface,[a,b,c],[samples[Vector2i(x,y)],samples[Vector2i(x+1,y)],samples[Vector2i(x+1,y+1)]],color)
			_clip_triangle(surface,[a,c,d],[samples[Vector2i(x,y)],samples[Vector2i(x+1,y+1)],samples[Vector2i(x,y+1)]],color.lightened(random.randf_range(-.045,.045)))
	surface.generate_normals()
	var instance := MeshInstance3D.new()
	instance.mesh = surface.commit()
	var material: StandardMaterial3D = world.mat("mountain_vertex",Color.WHITE,false)
	material.vertex_color_use_as_albedo = true
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	instance.material_override = material
	# The mountain surface receives shadows from gameplay objects, but casting
	# its own low-poly shadow creates broken dark wedges across the climb route.
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(instance)
	# Small vegetation accents on open, upward stone, from the place's profile.
	var random := layout.rng(index,67)
	for n in range(24):
		var point := Vector2(random.randf_range(-17.5,17.5),bottom+random.randf_range(.3,23.7))
		if layout.rock_field(point)<1.0 or not open_at(point+Vector2(0,1.2)): continue
		var holder := Node3D.new()
		holder.name = "Процедурный декор_%d" % n
		parent.add_child(holder)
		holder.position = Vector3(point.x,point.y,wall_depth(point)+.02)
		holder.scale = Vector3.ONE*1.2
		_build_grass(holder,random,quality=="high",1.0,profile_at(point.y),quality!="battery")

func beam(a: Vector3, b: Vector3, radius: float, color: Color, parent: Node3D) -> MeshInstance3D:
	var cylinder := CylinderMesh.new()
	cylinder.top_radius = radius*.8
	cylinder.bottom_radius = radius
	cylinder.height = a.distance_to(b)
	cylinder.radial_segments = 7
	var instance := MeshInstance3D.new()
	instance.mesh = cylinder
	instance.material_override = world.mat("wood_%s" % color.to_html(),color,false)
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	parent.add_child(instance)
	instance.position = (a+b)*.5
	instance.quaternion = Quaternion(Vector3.UP,(b-a).normalized())
	return instance

func anchor_polygon(dimensions: Vector2) -> PackedVector2Array:
	return MountainLayout.grip_polygon(dimensions)

static func object_polygon(object: Dictionary) -> PackedVector2Array:
	if object.has("polygon"): return object["polygon"]
	var half: Vector2 = object["dimensions"]*.5
	return PackedVector2Array([Vector2(-half.x,-half.y),Vector2(half.x,-half.y),half,Vector2(-half.x,half.y)])

# --- Grips --------------------------------------------------------------------------

func grip_material_name(object: Dictionary) -> String:
	# The type's own material in every lifetime: permanence adds fixings, it
	# never turns ice or a bough into the same dark granite.
	return profile_at(Vector2(object.get("pos",Vector2.ZERO)).y).material_name(GripSpec.kind_of(object))

const ROUND_FAMILIES := ["bough","wet_slab","clear_ice","salt_glass","cloud_glass","ice_crust","pumice","fibrous_root","frozen_branch","rope_root","hanging_mount","cloth_band"]

func build_anchor(object: Dictionary, parent: Node3D) -> void:
	var mount := mount_at(object["pos"],object["dimensions"],object,GRIP_STANDOFF)
	build_grip(object,parent,mount)

# One builder for every location. A grip is a broken block of stone jutting
# out of its host rock: the gameplay polygon stays the hitbox, and the block's
# own volume comes from GripVisualSpec. Its back runs into the rock along the
# host face normal, the type's paint lies on the top-front chamfer, and the
# type shows in the block's proportions, material and few embedded details.
func build_grip(object: Dictionary, parent: Node3D, mount: SurfaceMount) -> void:
	var p: Vector2 = object["pos"]
	var kind := GripSpec.kind_of(object)
	var id := int(object.get("id",0))
	var profile := mount.profile
	var family := profile.family(kind)
	var holder := Node3D.new()
	holder.name = "Зацеп_%d" % id
	parent.add_child(holder)
	holder.position = mount.holder_position()
	holder.rotation = mount.tilt()
	object["visual"] = holder
	object["mount"] = mount
	# Hook contacts snap to this outline: it is gameplay and stays exactly as
	# it was, inside the polygon; the stone block drawn around it is larger.
	var outline := _grip_outline(object_polygon(object),id)
	if family in ROUND_FAMILIES: outline = _rounded(outline,2)
	elif family in ["dry_slab","cracked_beam"]: outline = _jagged(outline,id)
	elif family=="masonry": outline = _masonry_outline(outline)
	object["surface"] = outline
	var spec := GripVisualSpec.for_grip(object,profile)
	object["visual_spec"] = spec
	# Two frames on the host face: the socket stays with the wall, the block
	# sits on a pivot that a spring bends under load.
	var frame := _block_frame(holder,mount)
	var socket := Node3D.new()
	socket.name = "Опора"
	socket.transform = frame
	holder.add_child(socket)
	var pivot := Node3D.new()
	pivot.name = "Изгиб" if kind==GripSpec.SPRING else "Наклон"
	holder.add_child(pivot)
	var block := Node3D.new()
	block.name = "Блок"
	block.transform = frame
	pivot.add_child(block)
	var rock := zone_color(p.y)
	# Lighter than the wall and leaning to the type's stone, so the block
	# separates by its own volume, not by an outline.
	var stone := rock.lightened(.06).lerp(profile.material_color(kind),.16)
	var front := _block_mesh(block,spec,stone,profile,kind)
	_contact_seam(socket,spec,rock,profile,id)
	_paint_band(block,spec,stone,id)
	_block_cracks(object,block,spec,stone,front,profile)
	match kind:
		GripSpec.ROOT: _root_details(object,block,spec,profile,front)
		GripSpec.SPRING: _spring_details(object,block,spec,profile,front)
		GripSpec.ICE: _ice_details(object,block,spec,profile,front)
		GripSpec.CRYSTAL: _crystal_details(object,block,spec,profile,front)
	if GripSpec.lifetime(object)=="permanent": _hardware(block,spec,profile,front)
	# Where a dial or marker sits on the front face, in holder space.
	var face := Vector2(spec.front_ring()[0].x*.15,(spec.front_ring()[0].y+spec.bounds().position.y)*.5)
	object["face_point"] = frame*Vector3(face.x,face.y,_face_z(front,face,spec.protrusion())+.03)
	object["dial_size"] = clampf((spec.front_ring()[0].y-spec.bounds().position.y)*.78,.34,.5)

# Block axes in holder space: Z along the host face normal (kept facing the
# camera enough to read), X along the face, origin on the host face.
func _block_frame(holder: Node3D, mount: SurfaceMount) -> Transform3D:
	var normal := mount.socket_normal if mount.host_mass>=0 else mount.normal
	normal = holder.basis.inverse()*normal.normalized()
	if normal.z<.6: normal = Vector3(normal.x,normal.y,.6).normalized()
	var across := Vector3.RIGHT-normal*normal.x
	across = across.normalized()
	var up := normal.cross(across).normalized()
	return Transform3D(Basis(across,up,normal),Vector3(0,0,mount.wall_local()))

# Four rings of the outline - back in the rock, at the host face, the full
# shoulder and the chamfered front - joined by side faces, plus a front face
# split into a few large facets. Returns the front triangles for placing
# paint, cracks and details on the real surface.
func _block_mesh(block: Node3D, spec: GripVisualSpec, stone: Color, profile: GripBiomeProfile, kind: int) -> Array:
	var depth := spec.protrusion()
	var rings := [spec.ring(spec.rear_scale*.94,.04),spec.ring(spec.rear_scale),spec.outline,spec.front_ring()]
	var depths := [-spec.back_embed,0.0,spec.shoulder(),depth]
	var weather: Dictionary = profile.weathering_rules
	var top_color := stone.lightened(.10)
	if float(weather["snow"])>.5: top_color = Color("eef3f6")
	elif float(weather["dust"])>.5: top_color = stone.lerp(profile.rock_palette["warm"],.45)
	elif float(weather["moss"])>.5: top_color = stone.lerp(profile.vegetation_set["leaf"],.18)
	var points := PackedVector3Array()
	var colors := PackedColorArray()
	var cap_points := PackedVector3Array()
	var cap_colors := PackedColorArray()
	var center := Vector3(0,0,(depth-spec.back_embed)*.5)
	var count := spec.outline.size()
	var ice := kind==GripSpec.ICE
	var front: PackedVector2Array = rings[3]
	var top := front[spec.top_left].y
	var low := spec.bounds().position.y
	# Front face: a fan from 1-3 raised points, each owning the edges nearest
	# to it, and a rim of uneven depth, so the face breaks into a few large
	# planes. The chamfers meet the same rim.
	var random := layout.rng(spec.seed_value,941)
	var apexes: Array[Vector3] = []
	var apex_count := clampi(spec.facet_count-2,1,3)
	for index in range(apex_count):
		var t := (index+.5)/apex_count-.5
		apexes.append(Vector3(t*spec.front_width*.62+random.randf_range(-.06,.06),lerpf(low,top,random.randf_range(.36,.6)),depth+random.randf_range(.09,.16)))
	var rims: Array[float] = []
	for index in range(count): rims.append(depth+(0.0 if index in [spec.top_left,spec.top_right] else random.randf_range(-.07,.02)))
	for layer in range(3):
		var a: PackedVector2Array = rings[layer]
		var b: PackedVector2Array = rings[layer+1]
		for i in range(count):
			var j := (i+1)%count
			var edge := spec.outline[j]-spec.outline[i]
			var facing := Vector2(edge.y,-edge.x).normalized()
			var tone := stone
			if facing.y>.55: tone = top_color
			elif facing.y<-.45: tone = stone.darkened(.30)
			else: tone = stone.darkened(.08+.06*clampf(-facing.x,0,1))
			if layer==2 and facing.y>.55: tone = stone.lightened(.04)
			var zi: float = rims[i] if layer==2 else depths[layer+1]
			var zj: float = rims[j] if layer==2 else depths[layer+1]
			var quad := [Vector3(a[i].x,a[i].y,depths[layer]),Vector3(a[j].x,a[j].y,depths[layer]),Vector3(b[j].x,b[j].y,zj),Vector3(b[i].x,b[i].y,zi)]
			var target := cap_points if ice and layer==2 else points
			var target_colors := cap_colors if ice and layer==2 else colors
			target.append_array(PackedVector3Array([quad[0],quad[1],quad[2]]))
			target_colors.append(tone)
			target.append_array(PackedVector3Array([quad[0],quad[2],quad[3]]))
			target_colors.append(tone.darkened(.02))
	var triangles: Array = []
	var owner_of := func(point: Vector2) -> int:
		var best := 0
		for index in range(apexes.size()):
			if absf(apexes[index].x-point.x)<absf(apexes[best].x-point.x): best = index
		return best
	for i in range(count):
		var j := (i+1)%count
		var here: int = owner_of.call((front[i]+front[j])*.5)
		var next: int = owner_of.call((front[j]+front[(j+1)%count])*.5)
		triangles.append([apexes[here],Vector3(front[i].x,front[i].y,rims[i]),Vector3(front[j].x,front[j].y,rims[j]),here])
		if next!=here: triangles.append([apexes[here],Vector3(front[j].x,front[j].y,rims[j]),apexes[next],next])
	for index in range(triangles.size()):
		var triangle: Array = triangles[index]
		var shade := (facet_hash(int(triangle[3]),spec.seed_value,3.1)-.5)*.10+(facet_hash(index,spec.seed_value,7.7)-.5)*.05
		# The lower front turns away from the light, as on a real ledge.
		var middle_y := (float((triangle[0] as Vector3).y)+float((triangle[1] as Vector3).y)+float((triangle[2] as Vector3).y))/3.0
		shade -= clampf((top-middle_y)/maxf(.01,top-low)-.5,0,1)*.10
		var face := stone.lightened(shade) if shade>0 else stone.darkened(-shade)
		var target := cap_points if ice else points
		var target_colors := cap_colors if ice else colors
		target.append_array(PackedVector3Array([triangle[0],triangle[1],triangle[2]]))
		target_colors.append(face)
	var body := _solid(block,"Каменный выступ",points,colors,stone_material,true,center)
	body.set_meta("visual_spec_bounds",spec.bounds())
	if ice:
		# Clear ice over the stone where it freezes; a dusty salt crust where
		# the place is dry.
		var glaze := profile.material_color(GripSpec.ICE)
		var cover := .45 if float(weather["dust"])>.5 else .78
		for index in range(cap_colors.size()): cap_colors[index] = cap_colors[index].lerp(glaze,cover)
		_solid(block,"Ледяной скол",cap_points,cap_colors,_ice_material(),true,center)
	return triangles

# Faceted mesh with outward normals, for closed volumes seen from any side.
func _solid(parent: Node3D, mesh_name: String, points: PackedVector3Array, colors: PackedColorArray, material: Material, shadows: bool, center: Vector3) -> MeshInstance3D:
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in range(0,points.size(),3):
		var normal := (points[i+2]-points[i]).cross(points[i+1]-points[i]).normalized()
		if normal.dot((points[i]+points[i+1]+points[i+2])/3.0-center)<0: normal = -normal
		for k in range(3):
			surface.set_color(colors[i/3])
			surface.set_normal(normal)
			surface.add_vertex(points[i+k])
	var mesh := MeshInstance3D.new()
	mesh.name = mesh_name
	mesh.mesh = surface.commit()
	mesh.material_override = material
	mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if shadows else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mesh)
	return mesh

# Height of the faceted front face at a point (block space).
func _face_z(triangles: Array, point: Vector2, fallback: float) -> float:
	for triangle in triangles:
		var a: Vector3 = triangle[0]
		var b: Vector3 = triangle[1]
		var c: Vector3 = triangle[2]
		var weights := _barycentric(point,Vector2(a.x,a.y),Vector2(b.x,b.y),Vector2(c.x,c.y))
		if weights.x>=-.001 and weights.y>=-.001 and weights.z>=-.001: return a.z*weights.x+b.z*weights.y+c.z*weights.z
	return fallback

static func _barycentric(p: Vector2, a: Vector2, b: Vector2, c: Vector2) -> Vector3:
	var v0 := b-a
	var v1 := c-a
	var v2 := p-a
	var d := v0.x*v1.y-v1.x*v0.y
	if absf(d)<.000001: return Vector3(-1,-1,-1)
	var v := (v2.x*v1.y-v1.x*v2.y)/d
	var w := (v0.x*v2.y-v2.x*v0.y)/d
	return Vector3(1.0-v-w,v,w)

# Lines laid on the front face, following its facets.
func _face_strip(triangles: Array, path: PackedVector2Array, width: float, lift: float, depth: float) -> PackedVector3Array:
	var result := PackedVector3Array()
	for i in range(path.size()-1):
		var a := path[i]
		var b := path[i+1]
		var taper := 1.0-float(i)/path.size()*.55
		var n := Vector2(-(b-a).y,(b-a).x).normalized()*width*taper
		var corners := [a+n,b+n*.7,b-n*.7,a-n]
		var lifted: Array[Vector3] = []
		for corner in corners: lifted.append(Vector3(corner.x,corner.y,_face_z(triangles,corner,depth)+lift))
		result.append_array(PackedVector3Array([lifted[0],lifted[1],lifted[2],lifted[0],lifted[2],lifted[3]]))
	return result

# The contact with the host rock: an uneven seam along the rear footprint,
# darker than the wall without an outline, with a few chips running off
# into the face. No ring of equal width and no disc.
func _contact_seam(socket: Node3D, spec: GripVisualSpec, rock: Color, profile: GripBiomeProfile, id: int) -> void:
	var random := layout.rng(id,943)
	var rear := spec.ring(spec.rear_scale)
	var center := Vector2.ZERO
	for point in rear: center += point
	center /= rear.size()
	var points := PackedVector3Array()
	var colors := PackedColorArray()
	var shade := float(profile.light_and_shadow_tuning["socket"])
	var widths: Array[float] = []
	for index in range(rear.size()): widths.append(random.randf_range(.03,.11)*(1.4 if rear[index].y<center.y else 1.0))
	for i in range(rear.size()):
		var j := (i+1)%rear.size()
		var oi := rear[i]+(rear[i]-center).normalized()*widths[i]
		var oj := rear[j]+(rear[j]-center).normalized()*widths[j]
		var deep := rock.darkened(shade*random.randf_range(.75,1.05))
		points.append_array(PackedVector3Array([Vector3(rear[i].x,rear[i].y,.004),Vector3(rear[j].x,rear[j].y,.004),Vector3(oj.x,oj.y,.016)]))
		colors.append(deep)
		points.append_array(PackedVector3Array([Vector3(rear[i].x,rear[i].y,.004),Vector3(oj.x,oj.y,.016),Vector3(oi.x,oi.y,.016)]))
		colors.append(deep.lerp(rock,.45))
	# Two or three breaks of the host face running from the seam.
	for chip in range(random.randi_range(2,3)):
		var at := rear[random.randi_range(0,rear.size()-1)]
		var away := (at-center).normalized().rotated(random.randf_range(-.6,.6))
		var a := at+away*.03
		var b := a+away*random.randf_range(.14,.30)
		var n := Vector2(-away.y,away.x)*.012
		points.append_array(PackedVector3Array([Vector3(a.x+n.x,a.y+n.y,.018),Vector3(b.x,b.y,.018),Vector3(a.x-n.x,a.y-n.y,.018)]))
		colors.append(rock.darkened(shade*.8))
	var seam := _flat_surface(socket,"Каменное гнездо",points,colors,stone_material,false)
	seam.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# Moss or snow collects in the seam above the block.
	var weather: Dictionary = profile.weathering_rules
	var fill := Color(0,0,0,0)
	if float(weather["snow"])>.5: fill = Color("f2f6f8")
	elif float(weather["moss"])>.5: fill = profile.vegetation_set["leaf"]
	if fill.a==0: return
	var tufts := PackedVector3Array()
	var tuft_colors := PackedColorArray()
	var top := rear[spec.top_left].y
	for index in range(random.randi_range(3,5)):
		var x := lerpf(rear[spec.top_left].x,rear[spec.top_right].x,random.randf_range(.05,.95))
		var size := random.randf_range(.05,.10)
		tufts.append_array(PackedVector3Array([Vector3(x-size,top+.01,.03),Vector3(x+size,top+.01,.03),Vector3(x+random.randf_range(-.03,.03),top+size*1.1,.04)]))
		tuft_colors.append(fill.darkened(random.randf_range(0,.15)))
	_flat_surface(socket,"Мох и снег в шве" if fill.a>0 else "Шов",tufts,tuft_colors,_vertex_material("grip_seam_fill"),false)

# Paint on the top-front chamfer: most of the block's width, ragged ends,
# a worn lower edge and a few spots where the stone shows through. It lies on
# the chamfer itself, never in front of the block.
func _paint_band(block: Node3D, spec: GripVisualSpec, stone: Color, id: int) -> void:
	var random := layout.rng(id,947)
	var back_a := spec.outline[spec.top_left]
	var back_b := spec.outline[spec.top_right]
	var front := spec.front_ring()
	var front_a := front[spec.top_left]
	var front_b := front[spec.top_right]
	var paint: Color = spec.paint_profile["color"]
	var half := spec.front_width*float(spec.paint_profile["width"])*.5
	var middle := (back_a.x+back_b.x)*.5
	var left := maxf(middle-half,maxf(back_a.x,front_a.x)+.02)
	var right := minf(middle+half,minf(back_b.x,front_b.x)-.02)
	var on_chamfer := func(x: float, v: float) -> Vector3:
		var s := back_a.lerp(back_b,(x-back_a.x)/(back_b.x-back_a.x))
		var f := front_a.lerp(front_b,(x-front_a.x)/(front_b.x-front_a.x))
		var shoulder := Vector3(x,s.y,spec.shoulder())
		var face := Vector3(x,f.y,spec.protrusion())
		var along := face-shoulder
		var normal := Vector3.RIGHT.cross(along).normalized()
		if normal.y<0: normal = -normal
		return shoulder.lerp(face,v)+normal*.007
	# Edges are shared between strokes, so the ragged border is continuous:
	# the top edge wavers a little, the lower edge has a few worn notches and
	# both ends are chipped back.
	var segments := 16
	var tops: Array[float] = []
	var bottoms: Array[float] = []
	var xs: Array[float] = []
	for edge in range(segments+1):
		xs.append(lerpf(left,right,float(edge)/segments))
		tops.append(random.randf_range(.02,.08))
		bottoms.append(random.randf_range(.9,.99) if random.randf()>.28 else random.randf_range(.72,.84))
	xs[0] += random.randf_range(.01,.05)
	xs[segments] -= random.randf_range(.01,.05)
	tops[0] += random.randf_range(.12,.3)
	bottoms[0] -= random.randf_range(.08,.25)
	tops[segments] += random.randf_range(.1,.3)
	bottoms[segments] -= random.randf_range(.05,.22)
	var points := PackedVector3Array()
	var colors := PackedColorArray()
	var worn := 0
	for segment in range(segments):
		var tone := paint.lightened(random.randf_range(0,.04)) if random.randf()<.5 else paint.darkened(random.randf_range(0,.06))
		var x0 := xs[segment]
		var x1 := xs[segment+1]
		var upper := [tops[segment],tops[segment+1]]
		var lower := [bottoms[segment],bottoms[segment+1]]
		# Worn patch: the stone shows through the lower part of one stroke.
		if worn<2 and segment>1 and segment<segments-2 and random.randf()<.12:
			worn += 1
			lower = [random.randf_range(.45,.6),random.randf_range(.45,.6)]
		var a: Vector3 = on_chamfer.call(x0,upper[0])
		var b: Vector3 = on_chamfer.call(x1,upper[1])
		var c: Vector3 = on_chamfer.call(x1,lower[1])
		var d: Vector3 = on_chamfer.call(x0,lower[0])
		points.append_array(PackedVector3Array([a,b,c,a,c,d]))
		colors.append(tone)
		colors.append(tone.darkened(.03))
	var material := _vertex_material("grip_paint")
	material.roughness = .62
	material.metallic_specular = .35
	var band := _flat_surface(block,"Полоса состояния",points,colors,material,false)
	band.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

# Natural cracks from the lower corners towards the middle; roots get deep,
# longer ones that can turn to the alarm colour before the break.
func _block_cracks(object: Dictionary, block: Node3D, spec: GripVisualSpec, stone: Color, front: Array, profile: GripBiomeProfile) -> void:
	var random := layout.rng(spec.seed_value,951)
	var ring := spec.front_ring()
	var count := ring.size()
	var center := Vector2(0,(ring[spec.top_left].y+spec.bounds().position.y)*.5)
	var starts: Array[Vector2] = []
	var lowest := 0
	for index in range(count):
		if ring[index].y<ring[lowest].y: lowest = index
	starts.append(ring[posmod(lowest-1,count)])
	starts.append(ring[(lowest+1)%count])
	var reach := .38
	var width := .016
	if spec.crack_pattern=="deep":
		starts.append(ring[lowest])
		starts.append(ring[posmod(lowest-2,count)])
		reach = .58
		width = .026
	var points := PackedVector3Array()
	for start in starts:
		var path := PackedVector2Array([start.lerp(center,.04)])
		var at := path[0]
		for step in range(3):
			at = at.lerp(center,reach/3.0)+Vector2(random.randf_range(-.05,.05),random.randf_range(-.03,.03))
			path.append(at)
		points.append_array(_face_strip(front,path,width,.006,spec.protrusion()))
	var colors := PackedColorArray()
	for index in range(points.size()/3): colors.append(stone.darkened(.5))
	var material := _vertex_material("grip_crack")
	if spec.crack_pattern=="deep":
		# Its own copy: the root's cracks redden in the last half second.
		material = material.duplicate() as StandardMaterial3D
		object["crack_material"] = material
	var cracks := _flat_surface(block,"Трещина",points,colors,material,false)
	cracks.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

func _root_details(_object: Dictionary, block: Node3D, spec: GripVisualSpec, profile: GripBiomeProfile, front: Array) -> void:
	# In the forest a root breaks out of the seam and holds the block; other
	# places keep the bare cracked stone.
	if float(profile.weathering_rules["moss"])<.5: return
	var random := layout.rng(spec.seed_value,953)
	var points := PackedVector3Array()
	var low := spec.bounds().position.y
	for strand in range(2):
		var x := spec.front_width*(-.3 if strand==0 else .22)+random.randf_range(-.05,.05)
		var path := PackedVector2Array([Vector2(x,low+.02),Vector2(x+random.randf_range(-.08,.08),low+spec.front_height*.25),Vector2(x+random.randf_range(-.1,.1),low+spec.front_height*.42)])
		points.append_array(_face_strip(front,path,.03,.012,spec.protrusion()))
	var colors := PackedColorArray()
	for index in range(points.size()/3): colors.append(profile.material_color(GripSpec.ROOT).darkened(.1*(index%2)))
	_flat_surface(block,"Корень",points,colors,_vertex_material("grip_root"),false)

func _spring_details(object: Dictionary, block: Node3D, spec: GripVisualSpec, profile: GripBiomeProfile, front: Array) -> void:
	# A fixing set into the top face, and a short relief arrow cut into the
	# face below the paint, pointing where the spring throws.
	var hardware: Dictionary = profile.attachment_hardware
	var metal: StandardMaterial3D = world.mat("grip_spring_%s" % profile.id,hardware["metal"],false)
	metal.metallic = .6
	metal.roughness = .35
	var top := spec.outline[spec.top_left].y
	var plate: MeshInstance3D = world.box("Пружинное крепление",Vector3.ZERO,Vector3(.26,.05,.2),metal,block)
	plate.position = Vector3(spec.front_width*.18,top+.012,spec.shoulder()*.45)
	var bolt: MeshInstance3D = world.box("Пружинное крепление_болт",Vector3.ZERO,Vector3(.07,.12,.07),metal,block)
	bolt.position = plate.position+Vector3(0,.04,0)
	var direction := GripSpec.exit_direction(object)
	var ring := spec.front_ring()
	var anchor := Vector2(0,ring[spec.top_left].y-spec.front_height*.22)
	var side := Vector2(-direction.y,direction.x)
	var tail := anchor-direction*.15
	var neck := anchor+direction*.05
	var tip := anchor+direction*.18
	var shape := PackedVector2Array([tail+side*.035,neck+side*.035,neck+side*.09,tip,neck-side*.09,neck-side*.035,tail-side*.035])
	var points := PackedVector3Array()
	var colors := PackedColorArray()
	var paint: Color = spec.paint_profile["color"]
	for lift_index in range(2):
		# A dark rim offset down-right reads as the relief's own shadow.
		var offset := Vector2(.012,-.012) if lift_index==0 else Vector2.ZERO
		var lift := .006 if lift_index==0 else .014
		var tone := paint.darkened(.6) if lift_index==0 else paint.darkened(.28)
		for index in [[0,1,5],[0,5,6],[2,3,4]]:
			var tri := PackedVector3Array()
			for k in index:
				var at: Vector2 = shape[k]+offset
				tri.append(Vector3(at.x,at.y,_face_z(front,at,spec.protrusion())+lift))
			points.append_array(tri)
			colors.append(tone)
	_flat_surface(block,"Направление выхода",points,colors,_vertex_material("grip_arrow"),false).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

func _ice_details(object: Dictionary, block: Node3D, spec: GripVisualSpec, profile: GripBiomeProfile, front: Array) -> void:
	# A shallow groove across the ice where the hook travels, with a pale
	# polished lip; dust streaks in the desert, icicles only in snow.
	var direction := GripSpec.slide_direction(object)
	var ring := spec.front_ring()
	var start := Vector2(-direction.x*spec.front_width*.18,ring[spec.top_left].y-spec.front_height*.16)
	var path := PackedVector2Array([start,start+direction*spec.front_width*.22,start+direction*spec.front_width*.44])
	var points := _face_strip(front,path,.026,.008,spec.protrusion())
	var colors := PackedColorArray()
	var glaze := profile.material_color(GripSpec.ICE)
	for index in range(points.size()/3): colors.append(glaze.darkened(.28))
	var lip := PackedVector2Array()
	for point in path: lip.append(point+Vector2(0,.03))
	var shine := _face_strip(front,lip,.008,.012,spec.protrusion())
	points.append_array(shine)
	for index in range(shine.size()/3): colors.append(glaze.lightened(.4))
	if float(profile.weathering_rules["dust"])>.5:
		for offset in [-.06,.07]:
			var dust := PackedVector2Array()
			for point in path: dust.append(point+Vector2(0,offset))
			var streak := _face_strip(front,dust,.01,.01,spec.protrusion())
			points.append_array(streak)
			for index in range(streak.size()/3): colors.append(profile.rock_palette["warm"])
	_flat_surface(block,"Борозда скольжения",points,colors,_vertex_material("grip_groove"),false).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	if float(profile.weathering_rules["snow"])>.5:
		_icicles(block,spec.bounds().position.y+spec.front_height*.12,spec.front_width*.7,spec.seed_value,spec.protrusion()*.8)

func _crystal_details(object: Dictionary, block: Node3D, spec: GripVisualSpec, profile: GripBiomeProfile, front: Array) -> void:
	var random := layout.rng(spec.seed_value,957)
	var palette: Dictionary = profile.crystal_set
	var top := spec.outline[spec.top_left].y
	# Mineral vein: from a lower corner through the face to the top edge.
	var ring := spec.front_ring()
	var low := spec.bounds().position.y
	var vein := PackedVector2Array([Vector2(-spec.front_width*.30,low+spec.front_height*.12),Vector2(-spec.front_width*.12,low+spec.front_height*.45),Vector2(-spec.front_width*.02,ring[spec.top_left].y-.02)])
	var points := _face_strip(front,vein,.03,.008,spec.protrusion())
	var colors := PackedColorArray()
	for index in range(points.size()/3): colors.append((palette["body"] as Color).lerp(palette["lit"],float(index%2)*.5))
	_flat_surface(block,"Минеральная жила",points,colors,_crystal_material(profile),false)
	# The cluster grows out of the seam behind the top face.
	var cluster := Node3D.new()
	cluster.position = Vector3(-spec.front_width*.05,top-.04,spec.shoulder()*.35)
	cluster.scale = Vector3.ONE*.3
	cluster.rotation.x = -.35
	block.add_child(cluster)
	_build_crystal(cluster,random,false,3,profile)
	# Two crystal spurs on the top-front edge, each pointing at one verified
	# exit, half sunk into the stone.
	var exits := GripSpec.choice_exits(object)
	if exits.size()<2: return
	var spurs := PackedVector3Array()
	var spur_colors := PackedColorArray()
	var origin: Vector2 = object["pos"]
	for exit_id in exits:
		if int(exit_id)>=layout.anchors.size(): continue
		var direction: Vector2 = (layout.anchors[int(exit_id)]["pos"]-origin).normalized()
		var base := Vector3(signf(direction.x)*spec.front_width*.28,top-spec.top_band_height*.5,spec.shoulder())
		var axis := Vector3(direction.x,direction.y,.35).normalized()
		var side := Vector3(-axis.y,axis.x,0).normalized()
		var up := axis.cross(side).normalized()
		var tip := base+axis*.34
		for corner in range(6):
			var a0 := TAU*corner/6.0
			var a1 := TAU*(corner+1)/6.0
			var o0 := side*cos(a0)*.05+up*sin(a0)*.05
			var o1 := side*cos(a1)*.05+up*sin(a1)*.05
			spurs.append_array(PackedVector3Array([base+o0,base+axis*.24+o0,base+axis*.24+o1,base+o0,base+axis*.24+o1,base+o1,base+axis*.24+o0,tip,base+axis*.24+o1]))
			var face := (palette["body"] as Color).lerp(palette["lit"],clampf(cos(a0)*.5+.5,0,1))
			spur_colors.append_array(PackedColorArray([face,face.darkened(.08),face.lerp(palette["pale"],.4)]))
	_flat_surface(block,"Выходы кристалла",spurs,spur_colors,_crystal_material(profile),false)

func _hardware(block: Node3D, spec: GripVisualSpec, profile: GripBiomeProfile, front: Array) -> void:
	# Fixings of a permanent grip: set into the lower front face and running
	# back into the stone, in the style of the place.
	var hardware: Dictionary = profile.attachment_hardware
	var metal: StandardMaterial3D = world.mat("grip_hw_%s" % profile.id,hardware["metal"],false)
	metal.metallic = .55
	metal.roughness = .38
	var accent: StandardMaterial3D = world.mat("grip_hw_accent_%s" % profile.id,hardware["accent"],false)
	accent.metallic = .7
	accent.roughness = .3
	var y := spec.bounds().position.y+spec.front_height*.3
	var reach := spec.protrusion()+spec.back_embed
	var face_z := func(x: float) -> float: return _face_z(front,Vector2(x,y),spec.protrusion())
	match str(hardware["style"]):
		"ring":
			var x := spec.front_width*.3
			var ring := MeshInstance3D.new()
			ring.name = "Кольцо крепления"
			var torus := TorusMesh.new()
			torus.inner_radius = .07
			torus.outer_radius = .11
			ring.mesh = torus
			ring.material_override = metal
			ring.position = Vector3(x,y-.07,face_z.call(x)+.03)
			ring.rotation.x = PI*.5
			block.add_child(ring)
			var pin: MeshInstance3D = world.box("Металлическое крепление",Vector3.ZERO,Vector3(.06,.06,reach),metal,block)
			pin.position = Vector3(x,y,face_z.call(x)-reach*.5+.02)
		"rivets":
			for x in [-.28,0.0,.28]:
				var rivet: MeshInstance3D = world.box("Металлическое крепление",Vector3.ZERO,Vector3(.06,.06,reach),accent,block)
				rivet.position = Vector3(spec.front_width*x,y,face_z.call(spec.front_width*x)-reach*.5+.02)
		"dowel":
			for x in [-.3,.3]:
				var dowel: MeshInstance3D = world.box("Золотое крепление",Vector3.ZERO,Vector3(.07,.07,reach),accent,block)
				dowel.position = Vector3(spec.front_width*x,y,face_z.call(spec.front_width*x)-reach*.5+.025)
		"lashing":
			for x in [-.26,.26]:
				var lash: MeshInstance3D = world.box("Канатное крепление",Vector3.ZERO,Vector3(.05,spec.front_height*.9,.05),accent,block)
				lash.position = Vector3(spec.front_width*x,y+spec.front_height*.1,face_z.call(spec.front_width*x)+.02)
				lash.rotation.z = .3*signf(x)
		_:
			for side in [-1,1]:
				var x: float = side*spec.front_width*.32
				var plate: MeshInstance3D = world.box("Металлическое крепление",Vector3.ZERO,Vector3(.1,spec.front_height*.4,.04),metal,block)
				plate.position = Vector3(x,y,face_z.call(x)+.02)
				var bolt: MeshInstance3D = world.box("Золотое крепление",Vector3.ZERO,Vector3(.05,.05,reach),accent,block)
				bolt.position = Vector3(x,y+.05,face_z.call(x)-reach*.5+.03)

func _masonry_outline(outline: PackedVector2Array) -> PackedVector2Array:
	# Dressed stone: the knob's bounds with small chamfers, inside the outline.
	var low := Vector2(INF,INF)
	var high := Vector2(-INF,-INF)
	for point in outline:
		low = low.min(point)
		high = high.max(point)
	low += Vector2(.06,.04)
	high -= Vector2(.06,.04)
	var c := minf(.12,(high.y-low.y)*.25)
	var box := PackedVector2Array([Vector2(low.x+c,low.y),Vector2(high.x-c,low.y),Vector2(high.x,low.y+c),Vector2(high.x,high.y-c),Vector2(high.x-c,high.y),Vector2(low.x+c,high.y),Vector2(low.x,high.y-c),Vector2(low.x,low.y+c)])
	var result := PackedVector2Array()
	for point in box:
		if Geometry2D.is_point_in_polygon(point,outline): result.append(point)
	return result if result.size()>=4 else outline

func _socket(holder: Node3D, outline: PackedVector2Array, mount: SurfaceMount, wall: float, rock: Color) -> void:
	# The stone nest: an uneven ring of the host rock just outside the root,
	# recessed towards the object and flush with the face outside, so the
	# object sits in a cavity instead of standing on the wall.
	var center := Vector2.ZERO
	for point in outline: center += point
	center /= maxf(1,outline.size())
	var random := RandomNumberGenerator.new()
	random.seed = int(absf(mount.position.x*733.0+mount.position.y*977.0))+11
	var socket := float(mount.profile.light_and_shadow_tuning["socket"])*socket_shade()
	var points := PackedVector3Array()
	var colors := PackedColorArray()
	var inner := PackedVector2Array()
	var outer := PackedVector2Array()
	for point in outline:
		var direction := (point-center).normalized()
		var base := point+direction*(.14+.30*clampf(-direction.y,0,1))+Vector2(0,-.30*.35)
		inner.append(base)
		var margin := Vector2(mount.cavity_scale.x-absf(point.x-center.x),mount.cavity_scale.y-absf(point.y-center.y)).max(Vector2(.12,.10))
		outer.append(base+direction*minf(margin.length(),socket_margin())*random.randf_range(.75,1.2))
	for i in range(outline.size()):
		var j := (i+1)%outline.size()
		var facing := ((outline[i]+outline[j])*.5-center).normalized()
		var deep := rock.darkened(socket*(1.0+.4*clampf(-facing.y,0,1)))
		var lip := rock.lightened(.04*clampf(facing.dot(Vector2(-.6,.8)),0,1))
		points.append_array(PackedVector3Array([Vector3(inner[i].x,inner[i].y,wall-.10),Vector3(outer[j].x,outer[j].y,wall+.01),Vector3(inner[j].x,inner[j].y,wall-.10)]))
		colors.append(deep)
		points.append_array(PackedVector3Array([Vector3(inner[i].x,inner[i].y,wall-.10),Vector3(outer[i].x,outer[i].y,wall+.01),Vector3(outer[j].x,outer[j].y,wall+.01)]))
		colors.append(deep.lerp(lip,.55))
	_flat_surface(holder,"Каменное гнездо",points,colors,stone_material,false)

func _contact_shade(holder: Node3D, size: Vector2, z: float, opacity: float) -> void:
	var quad := QuadMesh.new()
	quad.size = size
	var material := ShaderMaterial.new()
	material.shader = world.shader("contact_shade",CONTACT_SHADER)
	material.set_shader_parameter("opacity",opacity)
	var shade := MeshInstance3D.new()
	shade.name = "Контактная тень"
	shade.mesh = quad
	shade.material_override = material
	shade.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# Offset down-right with the sun, so the object reads as attached.
	shade.position = Vector3(.12,-.16,z)
	holder.add_child(shade)

func _chips(holder: Node3D, stone: Color, bottom: float, width: float, wall: float, id: int) -> void:
	# A disposable grip already shows where it will break: a few chips at its
	# foot, cut from the same stone.
	var chips := Node3D.new()
	chips.name = "Сколы"
	chips.position = Vector3(width*(.22 if id%2==0 else -.22),bottom-.06,wall+.12)
	chips.scale = Vector3.ONE*.4
	holder.add_child(chips)
	_build_pebbles(chips,layout.rng(id,918),stone,false)

# --- Hazards and shelves ------------------------------------------------------

func build_obstacle(object: Dictionary, parent: Node3D) -> void:
	var holder := Node3D.new()
	parent.add_child(holder)
	var p: Vector2 = object["pos"]
	var mount := mount_at(p,object["dimensions"],{},OBSTACLE_STANDOFF)
	# Hazards are set into the rock like any other block: a low profile on its
	# mount, a dark seam all round, rubble at the foot. Danger reads from the
	# red-brown stone, ember-lit cracks and a warm glint on upper edges only.
	holder.position = mount.holder_position()
	object["visual"] = holder
	object["mount"] = mount
	var polygon := PackedVector2Array()
	for point in SolidGeometry.polygon(object): polygon.append(point-p)
	var variant := int(object.get("variant",0))
	var tints := [Color("7a5040"),Color("6e4a44"),Color("7c5640")]
	var color: Color = zone_color(p.y).darkened(.30).lerp(tints[variant%3],.45)
	var refined := _refine_polygon(polygon)
	var wall := mount.wall_local()
	var top := _polygon_top(polygon)
	var bottom := -_polygon_top(_mirror_y(polygon))
	var height := top-bottom
	_socket(holder,refined,mount,wall,zone_color(p.y))
	_outcrop(holder,refined,clampf(wall-.3,-2.4,-.5),.18,.56,height*.20,height*.24,.84,color,obstacle_material)
	var random := RandomNumberGenerator.new()
	random.seed = int(absf(p.x*733.0+p.y*977.0))+variant
	var width := _polygon_width(polygon)
	for crack in range(2 if width<2.0 else 3):
		var start := Vector2(lerpf(-width*.3,width*.3,(crack+.5)/3.0)+random.randf_range(-.1,.1),top-height*.22)
		var path := PackedVector2Array([start])
		for step in range(3):
			path.append(path[-1]+Vector2(random.randf_range(-.14,.14),-height*random.randf_range(.12,.2)))
		_crack(holder,path,.035,.61,color.darkened(.55))
		if quality!="battery": _crack(holder,path,.012,.62,Color("e07040"),"obstacle_ember")
	_edge_glint(holder,refined,.03,.58,Color("e0925f"))
	if not baked_contact(): _contact_shade(holder,Vector2(width,height)+Vector2(1.0,.9),wall+.03,float(mount.profile.light_and_shadow_tuning["contact"]))

func build_ledge(object: Dictionary, parent: Node3D) -> void:
	# A rest ledge is a shelf of the mountain: its top bevel is exactly the
	# physical top, the front has thickness, the root runs into the stone
	# through a socket, the underside is dark, and grass only grows on the lip.
	var left: float = object["left"]
	var right: float = object["right"]
	var top: float = object["top"]
	var center := Vector2((left+right)*.5,top)
	var width := right-left
	var style := int(object.get("style",posmod(int(absf(center.x*97.0+top*31.0)),3)))
	var polygon := PackedVector2Array()
	if style==0: # broad cantilever with a broken front lip
		polygon = PackedVector2Array([Vector2(-width*.50,0),Vector2(width*.40,0),Vector2(width*.50,-.16),Vector2(width*.34,-.48),Vector2(-width*.44,-.42),Vector2(-width*.54,-.16)])
	elif style==1: # saddle shaped shelf, slightly asymmetric
		polygon = PackedVector2Array([Vector2(-width*.50,0),Vector2(-width*.12,.07),Vector2(width*.46,0),Vector2(width*.50,-.22),Vector2(width*.28,-.5),Vector2(-width*.42,-.38)])
	else: # wedge anchored into the mountain
		polygon = PackedVector2Array([Vector2(-width*.50,0),Vector2(width*.50,.04),Vector2(width*.39,-.30),Vector2(width*.08,-.58),Vector2(-width*.47,-.35)])
	# The stone is sampled under the lip, where the shelf enters the wall; the
	# holder stays on the layout's walking line.
	var mount := mount_at(center-Vector2(0,.3),Vector2(width,.6),{},LEDGE_STANDOFF)
	mount.layout_point = center
	var holder := Node3D.new()
	holder.name = "Площадка отдыха_%d" % int(roundf(top*10))
	parent.add_child(holder)
	holder.position = mount.holder_position()
	object["visual"] = holder
	object["mount"] = mount
	var rock := zone_color(top).lerp(mount.profile.rock_palette["warm"],.2).darkened(.04)
	var wall := mount.wall_local()
	_socket(holder,polygon,mount,wall,zone_color(top))
	_outcrop(holder,polygon,clampf(wall-.3,-2.2,-.5),.30,.62,.16,.20,.84,rock,stone_material)
	# A deep skirt under the shelf is its underside: it falls back into the
	# wall in cool shade, so the shelf has visible thickness from the front.
	_skirt(holder,polygon,.29,wall-.06,zone_color(top),.16,.55)
	# Light walking surface over a shaded front edge, so the landing reads
	# against the rock and the sky behind it.
	_contour(holder,polygon,.09,.84,rock.darkened(.5),rock.lightened(.32))
	if not baked_contact(): _contact_shade(holder,Vector2(width+1.0,1.4),wall+.03,float(mount.profile.light_and_shadow_tuning["contact"]))
	var lip := RandomNumberGenerator.new()
	lip.seed = int(absf(center.x*997.0+top*131.0))
	for tuft in range(3 if quality!="battery" else 1):
		var grass := Node3D.new()
		grass.position = Vector3(lerpf(-width*.4,width*.4,lip.randf()),-.02,.62)
		grass.scale = Vector3.ONE*.75
		holder.add_child(grass)
		_build_grass(grass,lip,false,1.0,mount.profile,quality!="battery")

# --- Decor clusters -------------------------------------------------------------

func _build_grass(holder: Node3D, random: RandomNumberGenerator, shadows: bool, spread: float = 1.0, profile: GripBiomeProfile = null, detail: bool = true) -> void:
	# A clump that grows from a dark cushion of soil: 3-5 broad leaves give
	# the silhouette, stems and fine blades fill it, lengths and tints vary.
	# Without detail the fine blades go, the cushion and broad leaves stay.
	var used := profile if profile!=null else GripBiomeProfile.named("forest")
	var plants: Dictionary = used.vegetation_set
	var dark: Color = plants["root"]
	var mid: Color = plants["leaf"]
	var light: Color = plants["tip"]
	var frost := bool(plants.get("frost",false))
	var dry := bool(plants.get("dry",false))
	var points := PackedVector3Array()
	var colors := PackedColorArray()
	# Cushion: a low faceted mound of soil and grit in the crack, close to the
	# host rock's tone so it reads as filled crevice, not a hole.
	var soil: Color = (plants["soil"] as Color).lerp(used.rock_palette["base"],.45)
	var corners := 7
	var cushion := PackedVector3Array()
	for corner in range(corners):
		var angle := TAU*corner/corners+random.randf_range(-.2,.2)
		cushion.append(Vector3(cos(angle)*.26*spread,sin(angle)*.07-.02,.0))
	var crown := Vector3(0,.03,.07)
	for corner in range(corners):
		points.append_array(PackedVector3Array([crown,cushion[corner],cushion[(corner+1)%corners]]))
		colors.append(soil.darkened(.04 if corner%2==0 else .12))
	var leaves := random.randi_range(3,5)
	var stems := random.randi_range(4,6)
	var fine := random.randi_range(6,10) if detail else 0
	for blade in range(leaves+stems+fine):
		var group := 0 if blade<leaves else 1 if blade<leaves+stems else 2
		var u := random.randf_range(-.5,.5)
		var angle := u*(1.9 if group==0 else 2.4)+random.randf_range(-.15,.15)
		var length: float = [random.randf_range(.42,.62),random.randf_range(.30,.48),random.randf_range(.18,.34)][group]*(1.0-absf(u)*.4)
		var w: float = [random.randf_range(.08,.12),random.randf_range(.04,.06),random.randf_range(.02,.035)][group]
		if dry: length *= .8
		var z := .04+float(group)*.02+random.randf_range(0,.02)
		var root := Vector3(u*.34*spread,random.randf_range(-.02,.02),z)
		var direction := Vector3(sin(angle),cos(angle),0)
		var across := Vector3(direction.y,-direction.x,0)*w
		var bend := Vector3(direction.x*.18,-absf(direction.x)*.14,0)*length
		var middle := root+direction*length*.5
		var tip := root+direction*length+bend+Vector3(0,0,.03)
		var tone := mid.lerp(light,random.randf_range(.2,.7))
		var tip_tone := Color("f2f7f8") if frost else light if blade%3!=1 else mid
		points.append_array(PackedVector3Array([root-across,root+across,middle+across*.8]))
		colors.append(dark)
		points.append_array(PackedVector3Array([root-across,middle+across*.8,middle-across*.8]))
		colors.append(dark.lerp(tone,.4))
		points.append_array(PackedVector3Array([middle-across*.8,middle+across*.8,tip]))
		colors.append(tone.lerp(tip_tone,.6))
	_flat_surface(holder,"Трава",points,colors,_vertex_material("decor_grass_v5"),shadows)

func _build_cactus(holder: Node3D, random: RandomNumberGenerator, profile: GripBiomeProfile, shadows: bool) -> void:
	# Desert rim plant: a ribbed trunk with one or two raised arms, rooted in
	# a small mound of sand and grit.
	var plants: Dictionary = profile.vegetation_set
	var body: Color = (plants["leaf"] as Color).lerp(Color("5f7a3a"),.6)
	var points := PackedVector3Array()
	var colors := PackedColorArray()
	var height := random.randf_range(.9,1.3)
	_column(points,colors,Vector3(0,-.05,.12),Vector3.UP,.13,.10,height,body)
	for arm in range(random.randi_range(1,2)):
		var side := -1.0 if (arm==0)==(random.randf()<.5) else 1.0
		var at := random.randf_range(.3,.55)*height
		var elbow := Vector3(side*.26,at+.05,.12)
		_column(points,colors,Vector3(side*.06,at,.12),Vector3(side,.25,0).normalized(),.07,.07,.22,body.darkened(.05))
		_column(points,colors,elbow,Vector3.UP,.075,.06,random.randf_range(.25,.4),body)
	_flat_surface(holder,"Кактус",points,colors,_vertex_material("decor_plant"),shadows)
	var mound := Node3D.new()
	mound.name = "Песчаный холмик"
	mound.scale = Vector3.ONE*.7
	holder.add_child(mound)
	_build_pebbles(mound,random,(plants["soil"] as Color).lerp(profile.rock_palette["warm"],.5),false)

func _column(points: PackedVector3Array, colors: PackedColorArray, base: Vector3, axis: Vector3, bottom: float, top: float, length: float, color: Color) -> void:
	# A six-sided faceted column with a pointed cap, lit from the upper left.
	var side := Vector3(axis.y,-axis.x,0).normalized()
	var tip := base+axis*length
	for corner in range(6):
		var a0 := TAU*corner/6.0
		var a1 := TAU*(corner+1)/6.0
		var d0 := side*cos(a0)+Vector3.BACK*sin(a0)
		var d1 := side*cos(a1)+Vector3.BACK*sin(a1)
		var facing := -(cos(a0)+cos(a1))*.4
		var face := color.lightened(.14*facing) if facing>0 else color.darkened(-.2*facing)
		points.append_array(PackedVector3Array([base+d0*bottom,tip+d0*top,tip+d1*top,base+d0*bottom,tip+d1*top,base+d1*bottom]))
		colors.append(face)
		colors.append(face.darkened(.03))
		points.append_array(PackedVector3Array([tip+d0*top,tip+axis*top*.8,tip+d1*top]))
		colors.append(face.lightened(.08))

func _build_snow_cap(holder: Node3D, random: RandomNumberGenerator, rim: float) -> void:
	# Where nothing grows, an upper rim keeps a cornice of old snow: a lens
	# lying on the stone with a brighter lip and a soft blue underside.
	var outline := PackedVector2Array()
	var width := random.randf_range(.7,1.1)*rim
	for corner in range(8):
		var angle := TAU*corner/8.0
		outline.append(Vector2(cos(angle)*width,sin(angle)*.16+(.05 if sin(angle)>0 else -.02)))
	var snow := _outcrop(holder,outline,-.12,.02,.16,.08,.05,.8,Color("e9f1f4"),_vertex_material("decor_snow"))
	snow.name = "Снежный карниз"
	snow.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

func _build_roots(holder: Node3D, random: RandomNumberGenerator, profile: GripBiomeProfile, rim: float) -> void:
	# Under a forest overhang, roots of the plants above hang out of the
	# crack: thin tapering strands with a tuft of moss where they emerge.
	var color: Color = (profile.vegetation_set["root"] as Color).lerp(Color("5a4630"),.6)
	for strand in range(random.randi_range(2,4)):
		var x := random.randf_range(-.45,.45)*rim
		var path := PackedVector2Array([Vector2(x,.05)])
		for step in range(random.randi_range(2,4)):
			path.append(path[-1]+Vector2(random.randf_range(-.1,.1),-random.randf_range(.18,.32)))
		_crack(holder,path,.028,.06,color.darkened(random.randf_range(0,.15)))
	var moss := Node3D.new()
	moss.position = Vector3(0,.06,0)
	moss.scale = Vector3(1,-.5,1)*.6
	holder.add_child(moss)
	_build_grass(moss,random,false,rim,profile,false)

func _build_crystal(holder: Node3D, random: RandomNumberGenerator, shadows: bool, count: int = 4, profile: GripBiomeProfile = null) -> void:
	# A mineral grown from a crack: a dark cup at the root, the tallest
	# crystal sunk deepest, 2-5 side crystals of their own height and lean,
	# and a few fallen bits at the base. Emission stays a faint accent.
	var used := profile if profile!=null else GripBiomeProfile.named("forest")
	var palette: Dictionary = used.crystal_set
	var body: Color = palette["body"]
	var lit: Color = palette["lit"]
	var pale: Color = palette["pale"]
	# Collar of the host rock the cluster breaks out of.
	var host: Color = used.rock_palette["base"]
	var collar := PackedVector2Array()
	for corner in range(7):
		var angle := TAU*corner/7.0+random.randf_range(-.2,.2)
		collar.append(Vector2(cos(angle)*.62,sin(angle)*.24-.08))
	_outcrop(holder,collar,-.18,.0,.16,.08,.08,.7,host.lightened(.04),stone_material).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var points := PackedVector3Array()
	var colors := PackedColorArray()
	var cup := host.darkened(.55)
	var rim := 7
	for corner in range(rim):
		var a0 := TAU*corner/rim
		var a1 := TAU*(corner+1)/rim
		var r0 := .42*random.randf_range(.85,1.1)
		points.append_array(PackedVector3Array([Vector3(0,-.02,.02),Vector3(cos(a0)*r0,sin(a0)*.14-.04,.04),Vector3(cos(a1)*r0,sin(a1)*.14-.04,.04)]))
		colors.append(cup.lightened(.06 if corner%2==0 else 0.0))
	var total := clampi(count,3,6)
	for index in range(total):
		var t := (float(index)/maxf(1,total-1)-.5) if total>1 else 0.0
		var central := index==total/2
		var height := random.randf_range(1.0,1.6)*(1.0-absf(t)*.7)*(1.15 if central else 1.0)
		var radius := random.randf_range(.14,.20)*(1.0-absf(t)*.3)
		# The central crystal starts below the face: it grows out of the rock.
		var base := Vector3(t*.62,-.05-(.14 if central else .04),.06+index*.015)
		var axis := Vector3(sin(t*1.2+random.randf_range(-.18,.18)),cos(t*1.1),0).normalized()
		var side := Vector3(axis.y,-axis.x,0)
		var shaft := base+axis*height*.72
		var tip := base+axis*height
		for corner in range(6):
			var a0 := TAU*corner/6.0
			var a1 := TAU*(corner+1)/6.0
			var o0 := side*cos(a0)*radius+Vector3(0,0,sin(a0)*radius)
			var o1 := side*cos(a1)*radius+Vector3(0,0,sin(a1)*radius)
			var facing := (cos(a0)+cos(a1))*.5
			var face := body.lerp(lit,clampf(-facing*.8+.25,0,1))
			points.append_array(PackedVector3Array([base+o0,shaft+o0,shaft+o1]))
			colors.append(face)
			points.append_array(PackedVector3Array([base+o0,shaft+o1,base+o1]))
			colors.append(face.darkened(.08))
			points.append_array(PackedVector3Array([shaft+o0,tip,shaft+o1]))
			colors.append(face.lerp(pale,.45))
	_flat_surface(holder,"Кристалл",points,colors,_crystal_material(used),shadows)
	if quality!="battery":
		var bits := Node3D.new()
		bits.name = "Обломки"
		bits.position = Vector3(0,-.06,.05)
		bits.scale = Vector3.ONE*.5
		holder.add_child(bits)
		_build_pebbles(bits,random,body.darkened(.3),false)

# --- Shared mesh helpers (used by every mountain style) ----------------------

static func facet_hash(i: int, j: int, salt: float) -> float:
	return fposmod(sin(i*127.1+j*311.7+salt)*43758.5453,1.0)

func _flat_surface(parent: Node3D, name: String, points: PackedVector3Array, colors: PackedColorArray, material: Material, shadows: bool) -> MeshInstance3D:
	# Faceted mesh with one normal per triangle and per-triangle colours.
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in range(0,points.size(),3):
		var normal := (points[i+2]-points[i]).cross(points[i+1]-points[i]).normalized()
		if normal.z<0: normal = -normal
		for k in range(3):
			surface.set_color(colors[i/3])
			surface.set_normal(normal)
			surface.add_vertex(points[i+k])
	var mesh := MeshInstance3D.new()
	mesh.name = name
	mesh.mesh = surface.commit()
	mesh.material_override = material
	mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if shadows else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mesh)
	return mesh

func _vertex_material(key: String, emission: float = 0.0) -> StandardMaterial3D:
	var material: StandardMaterial3D = world.mat(key,Color.WHITE,false)
	material.vertex_color_use_as_albedo = true
	material.vertex_color_is_srgb = true
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	if emission>0:
		material.emission_enabled = true
		material.emission = Color("2f7fd0")
		material.emission_energy_multiplier = emission
	return material

func _build_pebbles(holder: Node3D, random: RandomNumberGenerator, base: Color, shadows: bool) -> void:
	for index in range(random.randi_range(1,3)):
		var r := random.randf_range(.12,.24)
		var outline := PackedVector2Array()
		for corner in range(6):
			var angle := TAU*corner/6.0+random.randf_range(-.3,.3)
			outline.append(Vector2(cos(angle)*r*1.35,sin(angle)*r*.8))
		var pebble := Node3D.new()
		pebble.position = Vector3((index-1.5)*.30+random.randf_range(-.06,.06),r*.5,.0)
		holder.add_child(pebble)
		var tone := base.lightened(random.randf_range(-.02,.06))
		var mesh := _outcrop(pebble,outline,-.12,.06,.26,r*.45,r*.40,.66,tone,stone_material)
		_skirt(pebble,outline,.05,-.06,base,.04,.06).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if shadows else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

func _edge_glint(parent: Node3D, polygon: PackedVector2Array, width: float, z: float, color: Color) -> void:
	# A thin warm line only on edges facing up, where the sun would catch.
	var center := Vector2.ZERO
	for point in polygon: center += point
	center /= polygon.size()
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	var count := 0
	for i in range(polygon.size()):
		var a: Vector2 = polygon[i]
		var b: Vector2 = polygon[(i+1)%polygon.size()]
		var outward := Vector2(-(b-a).y,(b-a).x).normalized()
		if outward.dot((a+b)*.5-center)<0: outward = -outward
		if outward.y<.35: continue
		var inward := -outward*width
		_triangle(surface,Vector3(a.x,a.y,z),Vector3(b.x,b.y,z),Vector3(b.x+inward.x,b.y+inward.y,z),color)
		_triangle(surface,Vector3(a.x,a.y,z),Vector3(b.x+inward.x,b.y+inward.y,z),Vector3(a.x+inward.x,a.y+inward.y,z),color)
		count += 1
	if count==0: return
	var mesh := MeshInstance3D.new()
	mesh.name = "Тёплая кромка"
	mesh.mesh = surface.commit()
	var material: StandardMaterial3D = world.mat("obstacle_glint",Color.WHITE,false)
	material.vertex_color_use_as_albedo = true
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	mesh.material_override = material
	mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mesh)

func _contour(parent: Node3D, outline: PackedVector2Array, width: float, z: float, dark: Color, light: Color) -> void:
	# Unlit band along the inside of an outline: light on edges facing up,
	# dark elsewhere. It only reads in front, so it never casts a shadow.
	var center := Vector2.ZERO
	for point in outline: center += point
	center /= maxf(1,outline.size())
	var inner := PackedVector2Array()
	for point in outline:
		inner.append(point+(center-point).normalized()*minf(width,point.distance_to(center)*.5))
	var points := PackedVector3Array()
	var colors := PackedColorArray()
	for i in range(outline.size()):
		var j := (i+1)%outline.size()
		var a := outline[i]
		var b := outline[j]
		var outward := Vector2(-(b-a).y,(b-a).x).normalized()
		if outward.dot((a+b)*.5-center)<0: outward = -outward
		var tone := light if outward.y>.35 else dark
		points.append_array(PackedVector3Array([Vector3(a.x,a.y,z),Vector3(b.x,b.y,z),Vector3(inner[j].x,inner[j].y,z)]))
		colors.append(tone)
		points.append_array(PackedVector3Array([Vector3(a.x,a.y,z),Vector3(inner[j].x,inner[j].y,z),Vector3(inner[i].x,inner[i].y,z)]))
		colors.append(tone)
	var material := _vertex_material("grip_contour")
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_flat_surface(parent,"Контур",points,colors,material,false)

func _rounded(points: PackedVector2Array, passes: int) -> PackedVector2Array:
	# Chaikin corner cutting: a smoother outline that only shrinks inwards.
	var result := points
	for step in range(passes):
		var next := PackedVector2Array()
		for i in range(result.size()):
			var a := result[i]
			var b := result[(i+1)%result.size()]
			next.append(a.lerp(b,.25))
			next.append(a.lerp(b,.75))
		result = next
	return result

func _jagged(points: PackedVector2Array, seed_value: int) -> PackedVector2Array:
	# Crumbling edge: extra notches pulled inwards between the corners.
	var random := RandomNumberGenerator.new()
	random.seed = seed_value*613+3
	var center := Vector2.ZERO
	for point in points: center += point
	center /= points.size()
	var result := PackedVector2Array()
	for i in range(points.size()):
		var a := points[i]
		var b := points[(i+1)%points.size()]
		result.append(a)
		if a.distance_to(b)>.25:
			var notch := a.lerp(b,random.randf_range(.35,.65))
			result.append(notch+(center-notch)*random.randf_range(.12,.24))
	return result

func _icicles(holder: Node3D, bottom: float, width: float, seed_value: int, z: float = .30) -> void:
	var random := layout.rng(seed_value,916)
	var points := PackedVector3Array()
	var colors := PackedColorArray()
	for index in range(3):
		var x := (index-1)*width*.24+random.randf_range(-.05,.05)
		var length := random.randf_range(.18,.32)
		var r := .05
		var base := Vector3(x,bottom+.06,z)
		var tip := base+Vector3(0,-length,0)
		points.append_array(PackedVector3Array([base+Vector3(-r,0,0),tip,base+Vector3(r,0,0)]))
		colors.append(Color("cfeeff"))
		points.append_array(PackedVector3Array([base+Vector3(r,0,0),tip,base+Vector3(0,0,r)]))
		colors.append(Color("9fd0ea"))
	_flat_surface(holder,"Сосульки",points,colors,_ice_material(),false)

func _ice_material() -> StandardMaterial3D:
	var material := _vertex_material("grip_ice")
	material.roughness = .12
	material.metallic_specular = .9
	material.rim_enabled = true
	material.rim = .45
	material.rim_tint = .2
	return material


func _grip_outline(polygon: PackedVector2Array, seed_value: int) -> PackedVector2Array:
	# An angular knob of rock inside the gameplay polygon: each corner is
	# pulled in by a deterministic amount and the top edge gets one chipped
	# notch, so grips share the broad facets of the boulders. Only the
	# underside drops slightly, to show the dark lower face.
	var random := RandomNumberGenerator.new()
	random.seed = seed_value*7919+17
	var center := Vector2.ZERO
	for point in polygon: center += point
	center /= polygon.size()
	var bottom := -_polygon_top(_mirror_y(polygon))
	var result := PackedVector2Array()
	var top_edge := 0
	var top_y := -INF
	for i in range(polygon.size()):
		var middle: Vector2 = (polygon[i]+polygon[(i+1)%polygon.size()])*.5
		if middle.y>top_y:
			top_y = middle.y
			top_edge = i
	for i in range(polygon.size()):
		var point: Vector2 = polygon[i]
		point += (center-point)*random.randf_range(.03,.13)
		if point.y<center.y: point.y -= .12*clampf((center.y-point.y)/maxf(.01,center.y-bottom),0,1)
		result.append(point)
		if i==top_edge:
			var next: Vector2 = polygon[(i+1)%polygon.size()]
			var notch := point.lerp(next,random.randf_range(.35,.6))
			result.append(notch+(center-notch)*random.randf_range(.10,.2))
	return _dedupe(result)

func _mirror_y(points: PackedVector2Array) -> PackedVector2Array:
	var result := PackedVector2Array()
	for point in points: result.append(Vector2(point.x,-point.y))
	return result

func _outcrop(parent: Node3D, outline: PackedVector2Array, z_back: float, z_rim: float, z_cap: float, top_band: float, low_band: float, squeeze: float, base: Color, material: Material, top_tint: Color = Color(0,0,0,0)) -> MeshInstance3D:
	# A stone outcrop seen straight on: a lit top bevel tilted towards the sun,
	# a front face, and a broad underside sloping back into shade. The outer
	# rim is the outline itself, so the shell never grows past it.
	var low := INF
	var high := -INF
	var center := Vector2.ZERO
	for point in outline:
		low = minf(low,point.y)
		high = maxf(high,point.y)
		center += point
	center /= maxf(1,outline.size())
	var inner := PackedVector2Array()
	for point in outline:
		var t := (point.y-low)/maxf(.01,high-low)
		inner.append(Vector2(center.x+(point.x-center.x)*squeeze,lerpf(low+low_band,high-top_band,t)))
	var points := PackedVector3Array()
	var colors := PackedColorArray()
	var count := outline.size()
	var apex := Vector3(center.x-(high-low)*.25,lerpf(low+low_band,high-top_band,.62),z_cap+.18)
	for i in range(count):
		var j := (i+1)%count
		var tone := (facet_hash(i,count,base.r*31.0)-.5)*.14
		var face := base.lightened(tone) if tone>=0 else base.darkened(-tone)
		points.append_array(PackedVector3Array([apex,Vector3(inner[i].x,inner[i].y,z_cap),Vector3(inner[j].x,inner[j].y,z_cap)]))
		colors.append(face.lightened(.04))
		# Bevel tone follows its facing: up is lit, down is the dark underside.
		var facing := ((outline[i]+outline[j])*.5-center).normalized().y
		var bevel := face.lightened(.12*facing) if facing>0 else face.darkened(-.08*facing)
		# Moss and similar caps sit on the upward bevels.
		if top_tint.a>0 and facing>.3: bevel = top_tint.lerp(bevel,.45)
		points.append_array(PackedVector3Array([Vector3(outline[i].x,outline[i].y,z_rim),Vector3(outline[j].x,outline[j].y,z_rim),Vector3(inner[j].x,inner[j].y,z_cap)]))
		colors.append(bevel)
		points.append_array(PackedVector3Array([Vector3(outline[i].x,outline[i].y,z_rim),Vector3(inner[j].x,inner[j].y,z_cap),Vector3(inner[i].x,inner[i].y,z_cap)]))
		colors.append(bevel)
		var side := face.darkened(.10)
		var root_a := center+(outline[i]-center)*.94
		var root_b := center+(outline[j]-center)*.94
		points.append_array(PackedVector3Array([Vector3(root_a.x,root_a.y,z_back),Vector3(root_b.x,root_b.y,z_back),Vector3(outline[j].x,outline[j].y,z_rim)]))
		colors.append(side)
		points.append_array(PackedVector3Array([Vector3(root_a.x,root_a.y,z_back),Vector3(outline[j].x,outline[j].y,z_rim),Vector3(outline[i].x,outline[i].y,z_rim)]))
		colors.append(side)
	var mesh := _flat_surface(parent,"Каменный выступ",points,colors,material,true)
	return mesh

func _skirt(parent: Node3D, outline: PackedVector2Array, z_rim: float, z_wall: float, color: Color, side: float, below: float) -> MeshInstance3D:
	# The root of an object: a ring of facets in the massif's own stone and
	# shader, sloping from the object's rim back into the boulder. It is
	# widest under the object, so every grip, hazard and shelf reads as a
	# knob of the rock instead of a plate laid on it.
	var center := Vector2.ZERO
	for point in outline: center += point
	center /= outline.size()
	var points := PackedVector3Array()
	var colors := PackedColorArray()
	var outer := PackedVector2Array()
	for point in outline:
		var direction := (point-center).normalized()
		outer.append(point+direction*(side+below*clampf(-direction.y,0,1))+Vector2(0,-below*.35))
	for i in range(outline.size()):
		var j := (i+1)%outline.size()
		var facing := ((outline[i]+outline[j])*.5-center).normalized()
		var light := facing.dot(Vector2(-.6,.8))
		# The lower part is the object's underside: clearly darker than the face.
		var tone := color.lightened(.08*light) if light>0 else color.darkened(-.24*light)
		tone = tone.lightened((facet_hash(i,outline.size(),color.g*17.0)-.5)*.06)
		points.append_array(PackedVector3Array([Vector3(outline[i].x,outline[i].y,z_rim),Vector3(outer[j].x,outer[j].y,z_wall),Vector3(outline[j].x,outline[j].y,z_rim)]))
		colors.append(tone)
		points.append_array(PackedVector3Array([Vector3(outline[i].x,outline[i].y,z_rim),Vector3(outer[i].x,outer[i].y,z_wall),Vector3(outer[j].x,outer[j].y,z_wall)]))
		colors.append(tone.darkened(.03))
	# Flush with the wall, so it never casts a shadow of its own.
	var mesh := _flat_surface(parent,"Каменное основание",points,colors,stone_material,false)
	return mesh

func _dedupe(points: PackedVector2Array) -> PackedVector2Array:
	var result := PackedVector2Array()
	for point in points:
		if result.is_empty() or result[-1].distance_to(point)>.02: result.append(point)
	if result.size()>1 and result[0].distance_to(result[-1])<.02: result.remove_at(result.size()-1)
	return result

func _polygon_top(points: PackedVector2Array) -> float:
	var top := -INF
	for point in points: top = maxf(top,point.y)
	return top

func _polygon_width(points: PackedVector2Array) -> float:
	var low := INF
	var high := -INF
	for point in points:
		low = minf(low,point.x)
		high = maxf(high,point.x)
	return high-low

func _crack(parent: Node3D, points: PackedVector2Array, width: float, z: float, color: Color, glow_key: String = "") -> void:
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in range(points.size()-1):
		var a := points[i]
		var b := points[i+1]
		var taper := 1.0-float(i)/points.size()*.6
		var n := Vector2(-(b-a).y,(b-a).x).normalized()*width*taper
		_triangle(surface,Vector3(a.x+n.x,a.y+n.y,z),Vector3(b.x+n.x*.7,b.y+n.y*.7,z),Vector3(b.x-n.x*.7,b.y-n.y*.7,z),color)
		_triangle(surface,Vector3(a.x+n.x,a.y+n.y,z),Vector3(b.x-n.x*.7,b.y-n.y*.7,z),Vector3(a.x-n.x,a.y-n.y,z),color)
	var mesh := MeshInstance3D.new()
	mesh.name = "Трещина"
	mesh.mesh = surface.commit()
	var material: StandardMaterial3D = world.mat("stone_crack" if glow_key.is_empty() else glow_key,Color.WHITE,false)
	material.vertex_color_use_as_albedo = true
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	if not glow_key.is_empty():
		# Faint ember light deep in the hazard's cracks.
		material.emission_enabled = true
		material.emission = color
		material.emission_energy_multiplier = .6
	mesh.material_override = material
	mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mesh)

func _crystal_material(profile: GripBiomeProfile = null) -> StandardMaterial3D:
	var used := profile if profile!=null else GripBiomeProfile.named("forest")
	var material: StandardMaterial3D = world.mat("decor_crystal_%s" % used.id,Color.WHITE,false)
	material.vertex_color_use_as_albedo = true
	material.vertex_color_is_srgb = true
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	material.roughness = .22
	material.metallic_specular = .8
	material.emission_enabled = true
	material.emission = used.crystal_set["emission"]
	material.emission_energy_multiplier = float(used.crystal_set["energy"])*float(used.light_and_shadow_tuning["emission_scale"])
	material.rim_enabled = true
	material.rim = .25
	material.rim_tint = .5
	return material

func _refine_polygon(polygon: PackedVector2Array) -> PackedVector2Array:
	# Add edge break points without changing the gameplay silhouette. This gives
	# obstacles a denser, more deliberate mesh than the six-point collision
	# contour alone.
	var refined := PackedVector2Array()
	for i in range(polygon.size()):
		var a: Vector2 = polygon[i]
		var b: Vector2 = polygon[(i+1)%polygon.size()]
		refined.append(a)
		refined.append(a.lerp(b,.46))
	return refined
