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
const WoodPlatform := preload("res://scripts/wood_platform.gd")
const FloraModels := preload("res://scripts/flora_models.gd")
# A platform's back stands this far off the stone; its front stays behind
# the hero's plane (z 3.2).
const PLATFORM_GAP := .04
const PLATFORM_FRONT := 2.9
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

# How far a grip's stone leans from the host rock to its type's material.
func grip_tint() -> float:
	return .55

# Rest platforms are authored timber models (WoodPlatform): the shared grain
# under the models' own tones, the wood nudged towards the place's cool rock
# so it sits in the light.
func ledge_materials(profile: GripBiomeProfile) -> Dictionary:
	var wood: StandardMaterial3D = world.mat("ledge_wood_%s" % profile.id,Color.WHITE.lerp(profile.rock_palette["cool"],.10),false)
	wood.albedo_texture = load(WoodPlatform.grain_path())
	wood.vertex_color_use_as_albedo = true
	wood.roughness = .86
	var iron: StandardMaterial3D = world.mat("ledge_iron",Color.WHITE,false)
	iron.vertex_color_use_as_albedo = true
	iron.metallic = .5
	iron.roughness = .45
	var rope: StandardMaterial3D = world.mat("ledge_rope",Color.WHITE,false)
	rope.vertex_color_use_as_albedo = true
	rope.roughness = .95
	return {"wood":wood,"iron":iron,"rope":rope}

# The platform model of a rest ledge: the style whose supports fit the free
# face under the ledge, its back plane on the frontmost stone anywhere over
# its footprint (deck and supports), so no part of it enters the mountain,
# and its front short of the hero's plane.
func _place_platform(holder: Node3D, object: Dictionary, mount: SurfaceMount) -> Node3D:
	var left: float = object["left"]
	var right: float = object["right"]
	var top: float = object["top"]
	var width := right-left+.24
	var style := WoodPlatform.style_for(_room_under_ledge(object))
	var drop: float = WoodPlatform.DROP[style]
	var back := _front_over(Rect2(left-.12,top-drop-.02,width,drop+.02))+PLATFORM_GAP
	var model := WoodPlatform.instantiate(style,width,ledge_materials(mount.profile),quality!="battery")
	model.scale.z = clampf((PLATFORM_FRONT-back)/WoodPlatform.DEPTH,.55,1.0)
	model.position = Vector3(0,0,back-holder.position.z)
	holder.add_child(model)
	object["platform_style"] = style
	return model

# Free height under a ledge before the first grip, find, hazard or ledge
# below it that its supports would run into.
func _room_under_ledge(object: Dictionary) -> float:
	var left: float = object["left"]-.2
	var right: float = object["right"]+.2
	var top: float = object["top"]
	var room := 3.0
	for id in layout.nearby_ids(top-3.5,top+.5):
		var grip: Dictionary = layout.anchors[id]
		if grip.get("reserve",false) or grip.get("hidden",false): continue
		var q: Vector2 = grip["pos"]
		var size: Vector2 = grip["dimensions"]
		# The stone block of a grip reaches past its hitbox at the sides.
		if q.y<top and q.x+size.x*.65>left and q.x-size.x*.65<right: room = minf(room,top-q.y-size.y*.5-.12)
	for find in layout.finds:
		var q: Vector2 = find["pos"]
		if q.y<top and q.x+.45>left and q.x-.45<right: room = minf(room,top-q.y-.5)
	for obstacle in layout.obstacles:
		var q: Vector2 = obstacle["pos"]
		var half: Vector2 = obstacle["dimensions"]*.5
		if q.y<top and q.x+half.x>left and q.x-half.x<right: room = minf(room,top-q.y-half.y-.12)
	for ledge in layout.ledges:
		var other_top := float(ledge["top"])
		if other_top<top and float(ledge["right"])>left and float(ledge["left"])<right: room = minf(room,top-other_top-.3)
	return room

# The frontmost stone over an area, sampled finer than any facet.
func _front_over(area: Rect2) -> float:
	var front := -INF
	var columns := maxi(2,ceili(area.size.x/.2))
	var rows := maxi(2,ceili(area.size.y/.2))
	for column in range(columns+1):
		for row in range(rows+1):
			front = maxf(front,wall_depth(area.position+area.size*Vector2(float(column)/columns,float(row)/rows)))
	return front

# Give the playable stone a controlled contrast step against the host face.
# Type colour carries identity, while the luminance adjustment keeps the hold
# readable on both dark snow/forest bands and pale desert/sky bands.
func grip_stone_color(rock: Color, profile: GripBiomeProfile, kind: int) -> Color:
	var stone := rock.lerp(profile.material_color(kind),.24)
	var luminance := stone.r*.2126+stone.g*.7152+stone.b*.0722
	if luminance<.48:
		return stone.lightened(.12)
	return stone.darkened(.09)

# Mountains whose finds lie on the face itself, with only a contact shade.
func finds_without_pedestal() -> bool:
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

# Lets a long section build yield to the next frame while the world streams
# it in (see MountainWorld.build_pause). False: the section was unloaded.
func pause(owner) -> bool:
	if world is MountainWorld: return await (world as MountainWorld).build_pause(owner)
	return true

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
		_build_grass(holder,random,quality!="battery",1.0,profile_at(point.y),quality!="battery")

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

# The outcrop reaches below its hitbox; where the face round it stands
# further out than at the grip itself, the outcrop steps out by that much so
# no rock covers its foot, and its back runs that much deeper into the face.
# Its front never comes near the hero's plane (z 3.2).
const OUTCROP_Z_LIMIT := 1.95

func _outcrop_lift(object: Dictionary) -> float:
	var p: Vector2 = object["pos"]
	var size: Vector2 = object["dimensions"]
	var here := wall_depth(p)
	var area := Rect2(p.x-size.x*.65,p.y-size.y*.5-1.0,size.x*1.3,size.y+1.05)
	return clampf(_stone_front(area)-here,0,maxf(0,OUTCROP_Z_LIMIT-here))

# The furthest the face's stone reaches out anywhere over an area.
func _stone_front(area: Rect2) -> float:
	var front := -INF
	for column in range(4):
		for row in range(5):
			front = maxf(front,wall_depth(area.position+area.size*Vector2(column/3.0,row/4.0)))
	return front

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
	var spec := GripVisualSpec.for_grip(object,profile,_room_below(object))
	object["visual_spec"] = spec
	# Two frames on the host face: the socket stays with the wall, the block
	# sits on a pivot that a spring bends under load.
	var lift := _outcrop_lift(object)
	spec.back_embed += lift
	var frame := _block_frame(holder,mount,lift)
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
	# The host's own stone, a touch lighter and barely leaning to the type's
	# material: the block separates by its volume and light, never as a pale
	# plate laid on the face.
	var stone := grip_stone_color(rock,profile,kind)
	var front := _block_mesh(block,spec,stone,profile,kind)
	# No seam, ring or recess round the block: it stands out of the face,
	# and its contact is the real shadow it casts.
	_paint_band(block,spec,front,id)
	_block_cracks(object,block,spec,stone,front,profile)
	match kind:
		GripSpec.ROOT:
			# The timed root keeps its stone silhouette and mechanics, but no
			# branch or stick protrudes through the playable grip surface.
			pass
		GripSpec.SPRING: _spring_details(object,block,spec,profile,front)
		GripSpec.ICE: _ice_details(object,block,spec,profile,front)
		GripSpec.CRYSTAL: _crystal_details(object,block,spec,profile,front)
	if GripSpec.lifetime(object)=="permanent": _hardware(block,spec,profile,front)
	# Where a dial or marker sits on the front face, in holder space.
	var face := Vector2(spec.front_ring()[0].x*.15,(spec.front_ring()[0].y+spec.bounds().position.y)*.5)
	# The dial stands clear of the faceted face, so no plane cuts into it.
	object["face_point"] = frame*Vector3(face.x,face.y,_face_z(front,face,spec.protrusion())+spec.bulge+.06)
	object["dial_size"] = clampf((spec.front_ring()[0].y-spec.bounds().position.y)*.78,.34,.5)

# How far an outcrop may drop under its hitbox before it would reach a find,
# another grip or a ledge below it; loot and grips keep clear stone round them.
func _room_below(object: Dictionary) -> float:
	var p: Vector2 = object["pos"]
	var size: Vector2 = object["dimensions"]
	var bottom := p.y-size.y*.5
	var reach := size.x*.75
	var room := 1.4
	for find in layout.finds:
		var q: Vector2 = find["pos"]
		if q.y<bottom and absf(q.x-p.x)<reach+.5: room = minf(room,bottom-q.y-.6)
	for id in layout.nearby_ids(p.y-3.5,p.y):
		var other: Dictionary = layout.anchors[id]
		if other==object or other.get("reserve",false) or other.get("hidden",false): continue
		var q: Vector2 = other["pos"]
		var other_size: Vector2 = other["dimensions"]
		var other_top := q.y+other_size.y*.5+.05
		if other_top<bottom and absf(q.x-p.x)<reach+other_size.x*.7: room = minf(room,bottom-other_top-.25)
	for ledge in layout.ledges:
		var ledge_top := float(ledge["top"])
		if ledge_top<bottom and p.x+reach>float(ledge["left"]) and p.x-reach<float(ledge["right"]): room = minf(room,bottom-ledge_top-.3)
	return room

# Block axes in holder space: Z along the host face normal (kept facing the
# camera enough to read), X along the face, origin on the host face.
func _block_frame(holder: Node3D, mount: SurfaceMount, lift: float = 0.0) -> Transform3D:
	var normal := mount.socket_normal if mount.host_mass>=0 else mount.normal
	normal = holder.basis.inverse()*normal.normalized()
	# An outcrop stands out of the mountain, whatever slope of a mass it grows
	# from: a little turn to the side, hardly any pitch, never tipped up (its
	# top face would vanish and its underside face the camera).
	normal = Vector3(clampf(normal.x,-.3,.3),clampf(normal.y,-.18,.06),0)
	normal.z = sqrt(1.0-normal.x*normal.x-normal.y*normal.y)
	var across := Vector3.RIGHT-normal*normal.x
	across = across.normalized()
	var up := normal.cross(across).normalized()
	return Transform3D(Basis(across,up,normal),Vector3(0,0,mount.wall_local()+lift))

# A rock outcrop of the host face, built for a camera looking straight down
# -Z: depth itself never shows, only faces turned towards the camera. Rings
# run from inside the rock to the host face and out to the silhouette, which
# meets the face almost flush at the top and the foot and stands out on the
# flanks. From there the top face slopes forward and down to the front rim
# (it carries the paint), the flanks turn in and the underside runs back into
# the rock in shade. The front face leans back towards the foot and breaks
# into a few large planes, with grooves where cracks split the outcrop into
# stones. Returns the visible triangles - a height field over the whole
# silhouette - for paint, cracks and details on the real surface.
func _block_mesh(block: Node3D, spec: GripVisualSpec, stone: Color, profile: GripBiomeProfile, kind: int) -> Array:
	var depth := spec.protrusion()
	var bounds := spec.bounds()
	var top := spec.outline[spec.top_left].y
	var low := bounds.position.y
	var height := maxf(.01,top-low)
	var random := layout.rng(spec.seed_value,941)
	var weather: Dictionary = profile.weathering_rules
	# The sun and the form light already brighten the top face a lot; its
	# own tone stays a little under the stone so it reads as a lit cap.
	var top_color := stone.darkened(.05)
	if float(weather["snow"])>.5: top_color = Color("eef3f6")
	elif float(weather["dust"])>.5: top_color = stone.lerp(profile.rock_palette["warm"],.45)
	elif float(weather["moss"])>.5: top_color = stone.lightened(.12).lerp(profile.vegetation_set["leaf"],.08)
	# Each stone between the cracks has its own plane: out or back a little and
	# turned to its own side, so the stones catch the light differently.
	var edges: Array[float] = [bounds.position.x]
	for crack in spec.cracks: edges.append(float(crack))
	edges.sort()
	edges.append(bounds.end.x)
	var stones: Array = []
	for index in range(edges.size()-1):
		stones.append({"x":(edges[index]+edges[index+1])*.5,"offset":random.randf_range(-.05,.07),"turn":random.randf_range(-.28,.28),"pitch":random.randf_range(-.12,.06)})
	var stone_at := func(x: float) -> Dictionary:
		for index in range(edges.size()-2,-1,-1):
			if x>=edges[index]: return stones[index]
		return stones[0]
	var middle_y := (top+low)*.5
	var plane_z := func(point: Vector2) -> float:
		var own: Dictionary = stone_at.call(point.x)
		var z := depth*lerpf(1.0,.94,clampf((top-point.y)/height,0,1))+float(own["offset"])
		return z+float(own["turn"])*(point.x-float(own["x"]))+float(own["pitch"])*(point.y-middle_y)
	# The front face domes like the boulders of the face: it falls back
	# towards its rim, most at the flanks, so its facets turn to all sides.
	var face_mid := Vector2(bounds.get_center().x,(top+low)*.5+height*.08)
	var face_half := bounds.size*.5
	var crown := func(point: Vector2) -> float:
		var d := (point-face_mid)/face_half
		return depth*.30*clampf(d.x*d.x*1.1+d.y*d.y*.4,0,1.2)
	var groove := func(x: float) -> float:
		var dip := 0.0
		for crack in spec.cracks: dip = maxf(dip,clampf(1.0-absf(x-float(crack))/.16,0,1))
		return dip*.07
	# The part buried in the rock runs straight back along the view axis, not
	# along the tilted face normal: a deep back (an outcrop lifted out of a
	# hollow) would otherwise slide sideways and show past the silhouette as
	# a long slanted tail.
	var view_basis := Basis.IDENTITY
	var node: Node = block
	while node is Node3D:
		view_basis = (node as Node3D).basis*view_basis
		node = node.get_parent()
	var into_rock := view_basis.inverse()*Vector3.FORWARD
	into_rock *= spec.back_embed/maxf(.2,-into_rock.z)
	var back: Array = []
	for point in spec.ring(spec.rear_scale*.94,.04): back.append(Vector3(point.x,point.y,0.0)+into_rock)
	var wall: Array = []
	for point in spec.ring(.96): wall.append(Vector3(point.x,point.y,0.0))
	var silhouette: Array = []
	for point in spec.outline:
		var t := clampf((top-point.y)/height,0,1)
		silhouette.append(Vector3(point.x,point.y,depth*lerpf(.42,.5,sin(t*PI))*random.randf_range(.92,1.08)))
	var rim: Array = []
	for point in spec.front:
		# The lower rim stands nearly as far out as the face: the foot of the
		# face looks forward, not down into shade.
		var t := clampf((top-point.y)/height,0,1)
		rim.append(Vector3(point.x,point.y,float(plane_z.call(point))-float(crown.call(point))+random.randf_range(-.07,.03)*(1.0-t*.6)-float(groove.call(point.x))))
	# Front face: the rim, a few raised points and the crack grooves,
	# triangulated together so the face breaks into large planes.
	var face_points := PackedVector2Array(spec.front)
	var face_z: Array[float] = []
	for vertex in rim: face_z.append(vertex.z)
	var front_box := Rect2(spec.front[0],Vector2.ZERO)
	for point in spec.front: front_box = front_box.expand(point)
	for index in range(spec.facet_count):
		for attempt in range(12):
			var at := Vector2(random.randf_range(front_box.position.x,front_box.end.x),random.randf_range(front_box.position.y,front_box.end.y))
			at = front_box.get_center().lerp(at,.8)
			if not Geometry2D.is_point_in_polygon(at,spec.front): continue
			face_points.append(at)
			face_z.append(float(plane_z.call(at))-float(crown.call(at))+spec.bulge*random.randf_range(.3,.8)-float(groove.call(at.x))*.6)
			break
	for crack in spec.cracks:
		for step in range(1,4):
			var at := Vector2(float(crack)+random.randf_range(-.05,.05),lerpf(front_box.end.y,front_box.position.y,step/4.0))
			if not Geometry2D.is_point_in_polygon(at,spec.front): continue
			face_points.append(at)
			face_z.append(float(plane_z.call(at))-float(crown.call(at))-.06)
	var points := PackedVector3Array()
	var colors := PackedColorArray()
	var cap_points := PackedVector3Array()
	var cap_colors := PackedColorArray()
	var center := Vector3(bounds.get_center().x,bounds.get_center().y,(depth-spec.back_embed)*.5)
	var ice := kind==GripSpec.ICE
	# Lit tops lean to the weathered top colour, undersides fall into shade,
	# faces turned to the lower right a step darker.
	var shade_of := func(a: Vector3, b: Vector3, c: Vector3, salt: int) -> Color:
		var normal := (c-a).cross(b-a).normalized()
		if normal.z<0: normal = -normal
		# The top face is the lightest plane in the light, the front a step
		# under it; faces turned up and to the left get the most sun and form
		# light, so their own tone is held back to keep them stone, not chalk.
		var tone := stone.darkened(.07).lerp(top_color,clampf((normal.y-.25)/.35,0,1))
		tone = tone.darkened(clampf(normal.y-.2,0,.8)*.18+clampf(-normal.x-.3,0,.6)*.10)
		tone = tone.darkened(clampf(-normal.y-.2,0,.8)*.22)
		tone = tone.darkened(clampf(normal.x*.6-normal.y*.3,0,.6)*.16)
		var jitter := (facet_hash(salt,spec.seed_value,7.7)-.5)*.09
		return tone.lightened(jitter) if jitter>0 else tone.darkened(-jitter)
	var triangles: Array = []
	var salt := 0
	var layers := [[back,wall,false],[wall,silhouette,false],[silhouette,rim,true]]
	for layer in layers:
		for triangle in _zipper(layer[0],layer[1]):
			salt += 1
			var visible: bool = layer[2]
			var target := cap_points if ice and visible else points
			var target_colors := cap_colors if ice and visible else colors
			target.append_array(PackedVector3Array(triangle))
			target_colors.append(shade_of.call(triangle[0],triangle[1],triangle[2],salt))
			if visible: triangles.append([triangle[0],triangle[1],triangle[2],0])
	var indices := Geometry2D.triangulate_delaunay(face_points)
	for i in range(0,indices.size(),3):
		var a := face_points[indices[i]]
		var b := face_points[indices[i+1]]
		var c := face_points[indices[i+2]]
		if not Geometry2D.is_point_in_polygon((a+b+c)/3.0,spec.front): continue
		var triangle := [Vector3(a.x,a.y,face_z[indices[i]]),Vector3(b.x,b.y,face_z[indices[i+1]]),Vector3(c.x,c.y,face_z[indices[i+2]])]
		salt += 1
		var target := cap_points if ice else points
		var target_colors := cap_colors if ice else colors
		target.append_array(PackedVector3Array(triangle))
		target_colors.append(shade_of.call(triangle[0],triangle[1],triangle[2],salt))
		triangles.append([triangle[0],triangle[1],triangle[2],1])
	var body := _solid(block,"Каменный выступ",points,colors,stone_material,true,center)
	body.set_meta("visual_spec_bounds",bounds)
	if ice:
		# Clear ice over the stone where it freezes; a dusty salt crust where
		# the place is dry.
		var glaze := profile.material_color(GripSpec.ICE)
		var cover := .45 if float(weather["dust"])>.5 else .78
		for index in range(cap_colors.size()): cap_colors[index] = cap_colors[index].lerp(glaze,cover)
		_solid(block,"Ледяной скол",cap_points,cap_colors,_ice_material(),true,center)
	return triangles

# Triangles between two closed rings of different sizes, both starting at
# the same corner: walk round both, always advancing the one that lags.
static func _zipper(a: Array, b: Array) -> Array:
	var result: Array = []
	var n := a.size()
	var m := b.size()
	var i := 0
	var k := 0
	while i<n or k<m:
		if k>=m or (i<n and float(i+1)/n<=float(k+1)/m):
			result.append([a[i%n],a[(i+1)%n],b[k%m]])
			i += 1
		else:
			result.append([a[i%n],b[(k+1)%m],b[k%m]])
			k += 1
	return result

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

# The face triangles whose outline overlaps a path's box: lookups along a
# short line need not walk the whole face.
static func _triangles_over(triangles: Array, path: PackedVector2Array, margin: float) -> Array:
	var box := Rect2(path[0],Vector2.ZERO)
	for point in path: box = box.expand(point)
	box = box.grow(margin+.02)
	var result: Array = []
	for triangle in triangles:
		var a: Vector3 = triangle[0]
		var b: Vector3 = triangle[1]
		var c: Vector3 = triangle[2]
		if maxf(a.x,maxf(b.x,c.x))<box.position.x or minf(a.x,minf(b.x,c.x))>box.end.x: continue
		if maxf(a.y,maxf(b.y,c.y))<box.position.y or minf(a.y,minf(b.y,c.y))>box.end.y: continue
		result.append(triangle)
	return result

# Lines laid on the front face, following its facets.
func _face_strip(triangles: Array, path: PackedVector2Array, width: float, lift: float, depth: float) -> PackedVector3Array:
	var result := PackedVector3Array()
	triangles = _triangles_over(triangles,path,width)
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

# Paint across the top of the boulder: most of its width, a broad stroke laid
# on the real surface just under the top edge, with ragged ends, a wavering
# lower edge and a few worn spots where the stone shows through.
const PAINT_ROWS := 4

func _paint_band(block: Node3D, spec: GripVisualSpec, front: Array, id: int) -> void:
	var random := layout.rng(id,947)
	var paint: Color = spec.paint_profile["color"]
	var a := spec.outline[spec.top_left]
	var b := spec.outline[spec.top_right]
	var half := spec.front_width*float(spec.paint_profile["width"])*.5
	var mid := (a.x+b.x)*.5
	var left := maxf(mid-half,a.x+.04)
	var right := minf(mid+half,b.x-.04)
	var band := spec.top_band_height*.62
	var edge_y := func(x: float) -> float:
		return lerpf(a.y,b.y,(x-a.x)/(b.x-a.x))-.05
	# Only the planes under the band are searched: the rest of the face
	# never carries paint.
	var low_edge := minf(a.y,b.y)-.05-band*1.1
	var high_edge := maxf(a.y,b.y)
	var under: Array = []
	for triangle in front:
		var lowest := minf((triangle[0] as Vector3).y,minf((triangle[1] as Vector3).y,(triangle[2] as Vector3).y))
		var highest := maxf((triangle[0] as Vector3).y,maxf((triangle[1] as Vector3).y,(triangle[2] as Vector3).y))
		if highest>=low_edge and lowest<=high_edge: under.append(triangle)
	var segments := 12
	var xs: Array[float] = []
	var tops: Array[float] = []
	var bottoms: Array[float] = []
	var upper_walk := random.randf_range(0,.1)
	var lower_walk := random.randf_range(.9,1.0)
	for edge in range(segments+1):
		xs.append(lerpf(left,right,float(edge)/segments))
		upper_walk = clampf(upper_walk+random.randf_range(-.05,.05),0,.16)
		lower_walk = clampf(lower_walk+random.randf_range(-.07,.07),.78,1.06)
		tops.append(upper_walk)
		bottoms.append(lower_walk)
	# Keep both ends in the same shallow band. Large endpoint drops made the
	# paint read as long orange sticks hanging inside the grip.
	tops[0] += random.randf_range(0,.05)
	tops[segments] += random.randf_range(0,.05)
	# A restrained worn patch keeps the stroke organic without breaking its
	# compact silhouette.
	if random.randf()<.5:
		var worn := random.randi_range(3,segments-3)
		bottoms[worn] = random.randf_range(.78,.9)
	# One grid of points on the real surface, rows close enough that the
	# band hugs every crease; each column only looks at the planes under it.
	var grid: Array = []
	for edge in range(segments+1):
		var x := xs[edge]
		var column := _triangles_over(under,PackedVector2Array([Vector2(x,low_edge),Vector2(x,high_edge)]),.0)
		var points_in_column: Array[Vector3] = []
		for row in range(PAINT_ROWS+1):
			var y := float(edge_y.call(x))-lerpf(tops[edge]*band*.5,bottoms[edge]*band,float(row)/PAINT_ROWS)
			points_in_column.append(Vector3(x,y,_face_z(column,Vector2(x,y),spec.protrusion())+.035))
		grid.append(points_in_column)
	var points := PackedVector3Array()
	var colors := PackedColorArray()
	for segment in range(segments):
		var tone := paint.lightened(random.randf_range(0,.02)) if random.randf()<.5 else paint.darkened(random.randf_range(0,.03))
		for row in range(PAINT_ROWS):
			var p0: Vector3 = grid[segment][row]
			var p1: Vector3 = grid[segment+1][row]
			var p2: Vector3 = grid[segment+1][row+1]
			var p3: Vector3 = grid[segment][row+1]
			points.append_array(PackedVector3Array([p0,p1,p2,p0,p2,p3]))
			# Fresh at the top, a little worn and dusty towards the lower edge.
			var shade := tone.darkened(.07*row/PAINT_ROWS)
			colors.append(shade)
			colors.append(shade)
	var material := _vertex_material("grip_paint")
	material.roughness = .62
	material.metallic_specular = .35
	var strip := _flat_surface(block,"Полоса состояния",points,colors,material,false)
	strip.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

# Natural cracks from the lower corners towards the middle; roots get deep,
# longer ones that can turn to the alarm colour before the break.
func _block_cracks(_object: Dictionary, block: Node3D, _spec: GripVisualSpec, _stone: Color, _front: Array, _profile: GripBiomeProfile) -> void:
	# Preserve a semantic marker for gameplay/tests, but do not draw crack strips
	# on the front face. The long dark/orange strips read as sticks embedded in
	# the grip rather than stone detail.
	var marker := Node3D.new()
	marker.name = "Трещина"
	block.add_child(marker)

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
	# Keep the route cue as a semantic marker for gameplay/tests. The former
	# large chevron was rendered as two orange sticks across the stone face.
	var direction_marker := Node3D.new()
	direction_marker.name = "Направление выхода"
	direction_marker.set_meta("direction",GripSpec.exit_direction(object))
	block.add_child(direction_marker)

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
		var foot := Vector2(signf(direction.x)*spec.front_width*.28,top-spec.top_band_height*.5)
		var base := Vector3(foot.x,foot.y,_face_z(front,foot,spec.protrusion()))
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
	# Only as deep as the unlifted block: the lifted back runs along the view
	# axis, and a pin along the tilted normal would poke out of it.
	var reach := spec.protrusion()+minf(spec.back_embed,.45)
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
				# The old tall, orange lashing strips looked like sticks growing
				# through the grip. Use two small inset stone-coloured plates so a
				# permanent grip keeps its fixing without a protruding line.
				var plate: MeshInstance3D = world.box("Канатное крепление",Vector3.ZERO,Vector3(.14,.08,.04),metal,block)
				plate.position = Vector3(spec.front_width*x,y+spec.front_height*.12,face_z.call(spec.front_width*x)+.012)
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

# --- Hazards and shelves ------------------------------------------------------

func build_obstacle(object: Dictionary, parent: Node3D) -> void:
	var holder := Node3D.new()
	parent.add_child(holder)
	var p: Vector2 = object["pos"]
	var mount := mount_at(p,object["dimensions"],{},OBSTACLE_STANDOFF)
	# Hazards stand out of the rock like any other block: a low profile on its
	# mount, no recess or painted shade round it. Danger reads from
	# the red-brown stone silhouette, without decorative sticks or bright lines.
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
	_outcrop(holder,refined,clampf(wall-.3,-2.4,-.5),.18,.56,height*.20,height*.24,.84,color,obstacle_material)
	# Keep the obstacle as a clean stone hazard. Cracks, warm edge glints and
	# ember overlays looked like wooden sticks embedded in the rock.

func build_ledge(object: Dictionary, parent: Node3D) -> void:
	# A rest ledge is a timber platform model standing on the face: its deck
	# is the physical top (_place_platform).
	var left: float = object["left"]
	var right: float = object["right"]
	var top: float = object["top"]
	var center := Vector2((left+right)*.5,top)
	var width := right-left
	var mount := mount_at(center-Vector2(0,.3),Vector2(width,.6),{},LEDGE_STANDOFF)
	mount.layout_point = center
	var holder := Node3D.new()
	holder.name = "Площадка отдыха_%d" % int(roundf(top*10))
	parent.add_child(holder)
	holder.position = mount.holder_position()
	object["visual"] = holder
	object["mount"] = mount
	_place_platform(holder,object,mount)

# --- Decor clusters -------------------------------------------------------------

func _build_grass(holder: Node3D, random: RandomNumberGenerator, shadows: bool, spread: float = 1.0, profile: GripBiomeProfile = null, detail: bool = true) -> void:
	# A painted plant of the place's climate (FloraModels): tufts and bushes,
	# desert plants or snow plants, swaying from the root.
	var used := profile if profile!=null else GripBiomeProfile.named("forest")
	FloraModels.plant(holder,FloraModels.pick_top(used,random),shadows,clampf(spread,.85,1.15))

func _build_cactus(holder: Node3D, random: RandomNumberGenerator, _profile: GripBiomeProfile, shadows: bool) -> void:
	# Desert rim plant: one of the painted cacti.
	FloraModels.plant(holder,FloraModels.pick_cactus(random),shadows)

func _build_snow_cap(holder: Node3D, random: RandomNumberGenerator, rim: float) -> void:
	# Where nothing grows, a rim keeps snowy stones or a drift of snowy scree.
	FloraModels.plant(holder,FloraModels.pick(["stone_snow","scree_snow"][random.randi_range(0,1)],random),quality!="battery",clampf(rim,.9,1.15))

func _build_roots(holder: Node3D, random: RandomNumberGenerator, profile: GripBiomeProfile, rim: float) -> void:
	# Under an overhang the place's vines, roots, frosted creepers or icicles
	# hang out of the crack.
	FloraModels.plant(holder,FloraModels.pick_hanging(profile,random),quality!="battery",clampf(rim,.9,1.1))

# A crystal cluster of the place's kind for decor and landmarks
# (FloraModels).
func _crystal_sprite(holder: Node3D, random: RandomNumberGenerator, profile: GripBiomeProfile, shadows: bool, scale: float = 1.0) -> void:
	FloraModels.plant(holder,FloraModels.pick_crystal(profile,random),shadows,scale)

# The small faceted cluster a crystal grip carries on its top.
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
		_crystal_bits(bits,random,body.darkened(.3),false)

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

func _build_pebbles(holder: Node3D, random: RandomNumberGenerator, profile: GripBiomeProfile, shadows: bool) -> void:
	# Loose stones of the place: a boulder or a little scree (FloraModels).
	FloraModels.plant(holder,FloraModels.pick_stone(profile,random),shadows)

# Small faceted bits at the foot of a grip's crystal.
func _crystal_bits(holder: Node3D, random: RandomNumberGenerator, base: Color, shadows: bool) -> void:
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

func _skirt(parent: Node3D, outline: PackedVector2Array, z_rim: float, z_wall: float, color: Color, side: float, below: float, support_material: Material = null) -> MeshInstance3D:
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
	var used_material: Material = stone_material if support_material==null else support_material
	var mesh := _flat_surface(parent,"Каменное основание",points,colors,used_material,false)
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
