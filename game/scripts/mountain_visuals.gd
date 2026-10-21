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
	return GripBiomeProfile.for_place(layout.location,height)

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
const WOOD_FAMILIES := ["fibrous_root","frozen_branch","rope_root","cracked_beam"]
const SPRING_FAMILIES := ["bough","cloth_band","ice_crust","spring_bracket","hanging_mount"]
const GLAZE_FAMILIES := ["wet_slab","salt_glass","clear_ice","polished_tile","cloud_glass"]
const CRYSTAL_FAMILIES := ["quartz_cluster","amber_geode","ice_cluster","seam_mineral","glow_quartz"]

func build_anchor(object: Dictionary, parent: Node3D) -> void:
	# One builder for every location: the grip is a knob of the host rock set
	# in a socket of the same stone, its silhouette and material come from the
	# type in the place's profile, and lifetime adds fixings or chips on top.
	var p: Vector2 = object["pos"]
	var kind := GripSpec.kind_of(object)
	var id := int(object.get("id",0))
	var dimensions: Vector2 = object["dimensions"]
	var mount := mount_at(p,dimensions,object,GRIP_STANDOFF)
	var profile := mount.profile
	var family := profile.family(kind)
	var holder := Node3D.new()
	holder.name = "Зацеп_%d" % id
	parent.add_child(holder)
	holder.position = mount.holder_position()
	holder.rotation = mount.tilt()
	object["visual"] = holder
	object["mount"] = mount
	var rock := zone_color(p.y)
	# The type's material over the host rock: lighter than the wall so the
	# grip separates, but still a stone of the same mountain, not a plate.
	var stone := rock.lerp(profile.material_color(kind),grip_tint()).darkened(.08)
	var style := posmod(id*7+kind,5)
	var outline := _grip_outline(object_polygon(object),id)
	if family in ROUND_FAMILIES: outline = _rounded(outline,2)
	elif family in ["dry_slab","cracked_beam"]: outline = _jagged(outline,id)
	elif family=="masonry": outline = _masonry_outline(outline)
	# Hook contacts snap to this drawn silhouette, not to the wider assist polygon.
	object["surface"] = outline
	var material := _grip_material(profile,kind)
	var wall := mount.wall_local()
	var back := clampf(wall-.25,-2.8,-.45)
	var top := _polygon_top(outline)
	var bottom := -_polygon_top(_mirror_y(outline))
	var height := top-bottom
	var width := _polygon_width(outline)
	var front_top := top-height*.32
	var weather: Dictionary = profile.weathering_rules
	var top_tint := Color(0,0,0,0)
	if family=="bough" or (kind==GripSpec.STONE and float(weather["moss"])>.5 and style==4): top_tint = profile.vegetation_set["leaf"]
	if family in ["frosted","frozen_branch","ice_crust"]: top_tint = Color("eef4f6")
	# A soft shade line, not a frame: the grip separates by its own volume.
	var rim_dark := stone.darkened(.28)
	_socket(holder,outline,mount,wall,rock)
	# Springs carry their shell on a pivot that bends under load.
	var shell_parent := holder
	if family in SPRING_FAMILIES:
		shell_parent = Node3D.new()
		shell_parent.name = "Изгиб"
		holder.add_child(shell_parent)
	var squeeze := .66 if family in CRYSTAL_FAMILIES else .74
	if family in ["dry_slab","masonry"] or (family in ["angular","layered"] and style==2 and width>1.2):
		# Split outcrop: blocks with dark joints between them.
		var cuts := [-width*.18,width*.18] if family=="dry_slab" else [0.0]
		var edges := [-INF]+cuts+[INF]
		for piece in range(edges.size()-1):
			var part := PackedVector2Array()
			for point in outline: part.append(Vector2(clampf(point.x,float(edges[piece])+.03,float(edges[piece+1])-.03),point.y))
			_outcrop(shell_parent,_dedupe(part),back,.30-piece*.02,.72-piece*.04,height*.32,height*.34,squeeze,stone.darkened(piece*.04),material,top_tint)
	else:
		_outcrop(shell_parent,outline,back,.32,.76,height*.32,height*.34,squeeze,stone,material,top_tint)
	# A dark contour with a sunlit upper lip, drawn inside the outline: the
	# silhouette separates from the rock behind without growing the grip.
	_contour(shell_parent,outline,.055,.98,rim_dark,stone.lightened(float(profile.light_and_shadow_tuning["rim"])))
	_grip_details(object,shell_parent,family,profile,stone,top,bottom,width,height,front_top,wall,style)
	if GripSpec.lifetime(object)=="permanent": _hardware(holder,profile,width,height,front_top,wall)
	if not baked_contact(): _contact_shade(holder,Vector2(width,height)+Vector2(.9,.8),wall+.03,float(profile.light_and_shadow_tuning["contact"]))
	# Short status strip inset in the front face just under the top bevel:
	# inside the silhouette, on the shell's own centre line.
	var strip_color: Color = MountainWorld.COLORS[kind]
	var strip_material: StandardMaterial3D = world.mat("grip_strip_%d" % kind,strip_color,false)
	strip_material.emission_enabled = true
	strip_material.emission = strip_color
	strip_material.emission_energy_multiplier = .45
	var middle := 0.0
	for point in outline: middle += point.x
	middle /= maxf(1,outline.size())
	var strip: MeshInstance3D = world.box("Полоса состояния",holder.position,Vector3(minf(width*.4,.7),.075,.03),strip_material,shell_parent)
	strip.position = Vector3(middle*.7,top-height*.40,.86)
	strip.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

func _grip_material(profile: GripBiomeProfile, kind: int) -> Material:
	var gloss := profile.gloss(kind)
	if gloss<.3: return stone_material
	var key := "grip_gloss_%s_%d" % [profile.id,kind]
	var material := _vertex_material(key)
	material.roughness = lerpf(.5,.1,gloss)
	material.metallic_specular = lerpf(.5,.9,gloss)
	material.rim_enabled = true
	material.rim = float(profile.light_and_shadow_tuning["rim"])
	material.rim_tint = .3
	if kind==GripSpec.CRYSTAL:
		material.emission_enabled = true
		material.emission = profile.crystal_set["emission"]
		material.emission_energy_multiplier = float(profile.crystal_set["energy"])*float(profile.light_and_shadow_tuning["emission_scale"])*1.5
	return material

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

func _grip_details(object: Dictionary, holder: Node3D, family: String, profile: GripBiomeProfile, stone: Color, top: float, bottom: float, width: float, height: float, front_top: float, wall: float, style: int) -> void:
	var id := int(object.get("id",0))
	var dark := stone.darkened(.55)
	match family:
		"angular", "frosted":
			if style in [0,3,4]:
				var start := Vector2(width*(-.16 if style!=3 else .14),front_top-.02)
				_crack(holder,PackedVector2Array([start,start+Vector2(.07,-height*.18),start+Vector2(.02,-height*.36),start+Vector2(.08,-height*.5)]),.026,.77,dark)
		"layered":
			# Bedding planes of sandstone across the face.
			for band in [.3,.62]:
				var y: float = bottom+height*float(band)
				_crack(holder,PackedVector2Array([Vector2(-width*.36,y),Vector2(-width*.05,y+.02),Vector2(width*.34,y-.01)]),.018,.77,stone.darkened(.3))
		"masonry":
			_crack(holder,PackedVector2Array([Vector2(-width*.42,bottom+height*.5),Vector2(width*.42,bottom+height*.5)]),.02,.77,stone.lightened(.25))
			for x in [-.18,.2]:
				_crack(holder,PackedVector2Array([Vector2(width*x,bottom+height*.52),Vector2(width*x,front_top+.02)]),.02,.77,stone.lightened(.25))
		"pumice":
			var pores := layout.rng(id,917)
			for pore in range(5):
				var at := Vector2(pores.randf_range(-.35,.35)*width,pores.randf_range(bottom+height*.25,front_top))
				_crack(holder,PackedVector2Array([at,at+Vector2(.05,-.03)]),.03,.77,dark)
		"dry_slab":
			for crack in [-.3,.3]:
				var start := Vector2(width*crack,front_top-.02)
				_crack(holder,PackedVector2Array([start,start+Vector2(.05,-height*.2),start+Vector2(-.02,-height*.42)]),.024,.77,dark)
			var crumbs := Node3D.new()
			crumbs.position = Vector3(0,bottom-.12,wall+.1)
			crumbs.scale = Vector3.ONE*.55
			holder.add_child(crumbs)
			_build_pebbles(crumbs,layout.rng(id,913),stone,false)
		"fibrous_root", "frozen_branch", "rope_root", "cracked_beam":
			# Wood, not stone: fibres along the length and both ends driven into
			# cracks of the host rock, which crumbles when the root gives way.
			var fibre := stone.lightened(.28) if family!="frozen_branch" else Color("e8f2f6")
			for lane in range(3):
				var y := bottom+height*(.3+lane*.18)
				_crack(holder,PackedVector2Array([Vector2(-width*.42,y),Vector2(-width*.1,y+.03),Vector2(width*.2,y-.01),Vector2(width*.42,y+.02)]),.012,.80,fibre)
			for side in [-1.0,1.0]:
				var end := Vector2(side*width*.5,bottom+height*.45)
				_crack(holder,PackedVector2Array([end,end+Vector2(side*.16,-.12),end+Vector2(side*.22,-.32)]),.03,.5,stone.darkened(.7))
			if family=="rope_root":
				for x in [-.22,.22]:
					_crack(holder,PackedVector2Array([Vector2(width*x-.08,bottom+.04),Vector2(width*x+.08,front_top)]),.025,.82,Color("e6d3a6"))
			var crumbs := Node3D.new()
			crumbs.position = Vector3(0,bottom-.12,wall+.1)
			crumbs.scale = Vector3.ONE*.5
			holder.add_child(crumbs)
			_build_pebbles(crumbs,layout.rng(id,913),zone_color(object["pos"].y),false)
		"bough", "cloth_band", "ice_crust", "spring_bracket", "hanging_mount":
			match family:
				"bough":
					var tuft := Node3D.new()
					tuft.position = Vector3(width*(.28 if id%2==0 else -.28),top-.06,.36)
					tuft.scale = Vector3.ONE*.6
					holder.add_child(tuft)
					_build_grass(tuft,layout.rng(id,914),false,.7,profile)
				"cloth_band":
					_crack(holder,PackedVector2Array([Vector2(-width*.45,front_top-.05),Vector2(0,front_top-.12),Vector2(width*.45,front_top-.05)]),.05,.82,Color("efe2bf"))
				"spring_bracket":
					for turn in range(4):
						var x := lerpf(-width*.25,width*.25,turn/3.0)
						_crack(holder,PackedVector2Array([Vector2(x-.06,bottom+height*.25),Vector2(x+.06,bottom+height*.7)]),.022,.82,Color("c9ced3"))
				"hanging_mount":
					for x in [-.3,.3]:
						_crack(holder,PackedVector2Array([Vector2(width*x,top),Vector2(width*x*.6,top+.32)]),.02,.6,Color("e6d3a6"))
			_exit_chevrons(holder,GripSpec.exit_direction(object),front_top,profile)
		"wet_slab", "salt_glass", "clear_ice", "polished_tile", "cloud_glass":
			if family=="clear_ice" or (family=="wet_slab" and float(profile.weathering_rules["snow"])>.5): _icicles(holder,bottom,width,id)
			_slide_track(holder,GripSpec.slide_direction(object),top,height,stone)
			# A dry slide reads through dust: pale streaks blown along the slope.
			if float(profile.weathering_rules["dust"])>.5:
				var along := GripSpec.slide_direction(object)
				for offset in [-.12,.12]:
					var start := Vector2(offset*width,top-height*.3)
					_crack(holder,PackedVector2Array([start,start+along*width*.3,start+along*width*.55]),.018,.99,profile.rock_palette["warm"])
		"quartz_cluster", "amber_geode", "ice_cluster", "seam_mineral", "glow_quartz":
			var shards := Node3D.new()
			shards.position = Vector3(width*.30,top-.18,.40)
			shards.scale = Vector3.ONE*.38
			holder.add_child(shards)
			_build_crystal(shards,layout.rng(id,915),false,3,profile)
			_choice_prongs(holder,object,front_top)

func _exit_chevrons(holder: Node3D, direction: Vector2, front_top: float, profile: GripBiomeProfile) -> void:
	# Two flat chevrons point where the bough throws: the deformation reads
	# before the first catch.
	var points := PackedVector3Array()
	var colors := PackedColorArray()
	var side := Vector2(-direction.y,direction.x)
	for step in range(2):
		var tip := direction*(.16+step*.15)+Vector2(0,front_top*.4)
		var back := tip-direction*.13
		points.append_array(PackedVector3Array([Vector3(tip.x,tip.y,.99),Vector3(back.x+side.x*.1,back.y+side.y*.1,.99),Vector3(back.x,back.y,.99)]))
		points.append_array(PackedVector3Array([Vector3(tip.x,tip.y,.99),Vector3(back.x,back.y,.99),Vector3(back.x-side.x*.1,back.y-side.y*.1,.99)]))
		colors.append(profile.vegetation_set["tip"])
		colors.append(profile.vegetation_set["tip"])
	var material := _vertex_material("grip_chevron")
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_flat_surface(holder,"Направление выхода",points,colors,material,false)

func _slide_track(holder: Node3D, direction: Vector2, top: float, height: float, stone: Color) -> void:
	# A polished groove from the top of the grip along its downslope: where
	# the hook will travel while it is held.
	var start := Vector2(0,top-.06)
	var path := PackedVector2Array([start])
	for step in range(1,4): path.append(start+direction*height*.28*step)
	_crack(holder,path,.03,.99,stone.lightened(.38))

func _choice_prongs(holder: Node3D, object: Dictionary, front_top: float) -> void:
	# A choice crystal shows two short spurs, one towards each verified exit.
	var exits := GripSpec.choice_exits(object)
	if exits.size()<2: return
	for exit_id in exits:
		if int(exit_id)>=layout.anchors.size(): continue
		var direction: Vector2 = (layout.anchors[int(exit_id)]["pos"]-object["pos"]).normalized()
		var start := Vector2(0,front_top*.3)
		_crack(holder,PackedVector2Array([start+direction*.12,start+direction*.42]),.035,1.0,Color("e6f4ff"),"choice_prong")

func _hardware(holder: Node3D, profile: GripBiomeProfile, width: float, height: float, front_top: float, wall: float) -> void:
	# Fixings of a permanent grip run from its face back into the socket, so
	# they read as set into the rock; the grip keeps its own material.
	var hardware: Dictionary = profile.attachment_hardware
	var metal: StandardMaterial3D = world.mat("grip_hw_%s" % profile.id,hardware["metal"],false)
	metal.metallic = .55
	metal.roughness = .38
	var accent: StandardMaterial3D = world.mat("grip_hw_accent_%s" % profile.id,hardware["accent"],false)
	accent.metallic = .7
	accent.roughness = .3
	var origin := holder.position
	var reach := absf(wall)+.8
	match str(hardware["style"]):
		"ring":
			var ring := MeshInstance3D.new()
			ring.name = "Кольцо крепления"
			var torus := TorusMesh.new()
			torus.inner_radius = .09
			torus.outer_radius = .14
			ring.mesh = torus
			ring.material_override = metal
			ring.position = Vector3(width*.36,front_top-height*.35,.8)
			ring.rotation.x = PI*.5
			holder.add_child(ring)
			var pin: MeshInstance3D = world.box("Металлическое крепление",origin,Vector3(.07,.07,reach),metal,holder)
			pin.name = "Металлическое крепление_%d" % holder.get_child_count()
			pin.position = Vector3(width*.36,front_top-height*.2,.8-reach*.5)
		"rivets":
			for x in [-.3,0.0,.3]:
				var rivet: MeshInstance3D = world.box("Металлическое крепление",origin,Vector3(.07,.07,reach),accent,holder)
				rivet.name = "Металлическое крепление_%d" % holder.get_child_count()
				rivet.position = Vector3(width*x,front_top-height*.42,.82-reach*.5)
		"dowel":
			var band: MeshInstance3D = world.box("Металлическое крепление",origin,Vector3(width*.8,.06,.06),metal,holder)
			band.name = "Металлическое крепление_%d" % holder.get_child_count()
			band.position = Vector3(0,front_top-height*.42,.8)
			for x in [-.32,.32]:
				var dowel: MeshInstance3D = world.box("Золотое крепление",origin,Vector3(.08,.08,reach),accent,holder)
				dowel.name = "Золотое крепление_%d" % holder.get_child_count()
				dowel.position = Vector3(width*x,front_top-height*.42,.82-reach*.5)
		"lashing":
			for x in [-.28,.28]:
				var lash: MeshInstance3D = world.box("Канатное крепление",origin,Vector3(.06,height*1.1,.06),accent,holder)
				lash.name = "Канатное крепление_%d" % holder.get_child_count()
				lash.position = Vector3(width*x,front_top-height*.3,.84)
				lash.rotation.z = .35*signf(x)
		_:
			for side in [-1,1]:
				var plate: MeshInstance3D = world.box("Металлическое крепление",origin,Vector3(.12,height*.5,.05),metal,holder)
				plate.name = "Металлическое крепление_%d" % holder.get_child_count()
				plate.position = Vector3(side*width*.34,front_top-height*.32,.76)
				plate.rotation.z = side*.12
				var bolt: MeshInstance3D = world.box("Золотое крепление",origin,Vector3(.06,.06,reach),accent,holder)
				bolt.name = "Золотое крепление_%d" % holder.get_child_count()
				bolt.position = Vector3(side*width*.34,front_top-height*.2,.80-reach*.5)

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

func _icicles(holder: Node3D, bottom: float, width: float, seed_value: int) -> void:
	var random := layout.rng(seed_value,916)
	var points := PackedVector3Array()
	var colors := PackedColorArray()
	for index in range(3):
		var x := (index-1)*width*.24+random.randf_range(-.05,.05)
		var length := random.randf_range(.18,.32)
		var r := .05
		var base := Vector3(x,bottom+.06,.30)
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
