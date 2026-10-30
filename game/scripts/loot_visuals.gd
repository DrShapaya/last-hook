class_name LootVisuals
extends RefCounted

# World models for finds. Every model is built from the item dictionary the
# loot system already stores ({"id","tier","kind","value"}) plus the find's
# "rare" flag, so pickup, the bag and run results stay untouched.

const TIER_COLORS := ItemCatalog.VISUAL_RARITY_COLORS
const TreasureModels := preload("res://scripts/treasure_models.gd")

static func kind_of(item: Dictionary) -> String:
	return TreasureModels.kind_of(item)

static func rarity_color(item: Dictionary) -> Color:
	return ItemCatalog.visual_color(item)

# The find's authored model (TreasureModels) idling in front of the face; it
# casts its own shadow on the rock and bobs and turns with its idle
# animation. Older mountains still stand it on a pedestal.
static func build(world: MountainWorld, find: Dictionary, holder: Node3D, quality: String, wall_local_z: float) -> Node3D:
	var item: Dictionary = find["item"]
	var rare := bool(find.get("rare",false))
	var kind := TreasureModels.kind_for(item)
	var shadows := quality!="battery"
	_pedestal(world,holder,wall_local_z,int(item.get("id",0)),shadows,kind,quality)
	var treasure := TreasureModels.instantiate(item,shadows)
	treasure.position = Vector3(0,0,MODEL_LIFT)
	holder.add_child(treasure)
	TreasureModels.play_idle(treasure,float(int(item.get("id",0))%11)/11.0)
	var glints := world.effects_quality=="full"
	if glints:
		_sparkle(world,holder,Vector3(.20,.20,.34),.30 if not rare else .42,float(int(item.get("id",0))%7)*.37)
	if rare and world.effects_quality!="off":
		_halo(world,holder,rarity_color(item).lightened(.3),.95 if glints else .7)
	return treasure

# The model stands this far in front of its holder, clear of the face.
const MODEL_LIFT := .12

# --- Price tag ----------------------------------------------------------------------

# A price tag hanging from the find on a short cord, in the HUD's language: a
# slate plate with chamfered corners, the rarity colour as its lower lip, a
# small coin and the value in the HUD font. It is a lit object of the scene,
# swinging with the find and casting its own shadow, not a label over it.
const TAG_FONT_SIZE := 64
const TAG_PIXEL := .0042
const TAG_HEIGHT := .28
const TAG_DROP := .09
const TAG_SLATE := Color("24323d")
const TAG_TEXT := Color("fff1c4")
static var _tag_font: Font

static func price_tag(world: MountainWorld, treasure: Node3D, item: Dictionary, shadows: bool) -> Node3D:
	if _tag_font==null: _tag_font = load("res://assets/fonts/RussoOne.ttf")
	# The cord hangs from the bottom of the model.
	var tag := treasure.get_node(TreasureModels.TAG) as Node3D
	var text := str(int(item.get("value",0)))
	var text_width := _tag_font.get_string_size(text,HORIZONTAL_ALIGNMENT_LEFT,-1,TAG_FONT_SIZE).x*TAG_PIXEL
	var coin := .15
	var width := text_width+coin+.15
	var top := -TAG_DROP
	var center := Vector3(0,top-TAG_HEIGHT*.5,0)
	var slate := world.mat("price_tag_slate",Color.WHITE,false)
	slate.roughness = .55
	slate.vertex_color_use_as_albedo = true
	var plate := MeshInstance3D.new()
	plate.name = "Табличка цены"
	plate.mesh = _tag_mesh(Vector2(width,TAG_HEIGHT),.045,.045,rarity_color(item))
	plate.material_override = slate
	plate.position = center
	plate.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if shadows else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	tag.add_child(plate)
	var cord := world.box("Шнурок ценника",Vector3.ZERO,Vector3(.012,TAG_DROP+.02,.012),world.mat("price_tag_cord",Color("5a3b1e")),tag)
	cord.position = Vector3(0,top*.5+.01,0)
	cord.cast_shadow = plate.cast_shadow
	var glyph := (load(TreasureModels.model_path("coin")) as PackedScene).instantiate() as Node3D
	glyph.name = "Монетка ценника"
	glyph.scale = Vector3.ONE*coin/.49
	glyph.position = center+Vector3(-width*.5+.06+coin*.5,.008,.035)
	tag.add_child(glyph)
	var label := Label3D.new()
	label.name = "Цена"
	label.text = text
	label.font = _tag_font
	label.font_size = TAG_FONT_SIZE
	label.pixel_size = TAG_PIXEL
	label.outline_size = 0
	label.modulate = TAG_TEXT
	label.shaded = false
	label.alpha_cut = Label3D.ALPHA_CUT_OPAQUE_PREPASS
	label.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	label.position = center+Vector3(-width*.5+.06+coin+.04,.016,.0235)
	tag.add_child(label)
	return tag

# A chamfered slab: slate front with a lighter top edge and the rarity lip
# along the bottom, darker sides.
static func _tag_mesh(size: Vector2, chamfer: float, depth: float, lip: Color) -> ArrayMesh:
	var half := size*.5
	var outline := [Vector2(-half.x+chamfer,-half.y),Vector2(half.x-chamfer,-half.y),Vector2(half.x,-half.y+chamfer),Vector2(half.x,half.y-chamfer),
		Vector2(half.x-chamfer,half.y),Vector2(-half.x+chamfer,half.y),Vector2(-half.x,half.y-chamfer),Vector2(-half.x,-half.y+chamfer)]
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	var front := depth*.5
	var face := func(points: Array, normal: Vector3, color: Color) -> void:
		for index in range(1,points.size()-1):
			# Godot winds front faces clockwise.
			for p: Vector3 in [points[0],points[index+1],points[index]]:
				surface.set_color(color)
				surface.set_normal(normal)
				surface.add_vertex(p)
	var front_points: Array = []
	for p: Vector2 in outline: front_points.append(Vector3(p.x,p.y,front))
	face.call(front_points,Vector3.BACK,TAG_SLATE)
	var back_points: Array = []
	for p: Vector2 in outline: back_points.append(Vector3(p.x,p.y,-front))
	back_points.reverse()
	face.call(back_points,Vector3.FORWARD,TAG_SLATE.darkened(.3))
	for index in range(outline.size()):
		var a: Vector2 = outline[index]
		var b: Vector2 = outline[(index+1)%outline.size()]
		var normal := Vector3(b.y-a.y,a.x-b.x,0).normalized()
		var tone := TAG_SLATE.darkened(.25-.2*clampf(normal.y,0,1))
		face.call([Vector3(a.x,a.y,-front),Vector3(b.x,b.y,-front),Vector3(b.x,b.y,front),Vector3(a.x,a.y,front)],normal,tone)
	# The lip: a coloured band raised a hair over the bottom of the face.
	var lip_y := -half.y+.034
	var band := [Vector3(-half.x+chamfer,-half.y+.004,front+.002),Vector3(half.x-chamfer,-half.y+.004,front+.002),Vector3(half.x-.012,lip_y,front+.002),Vector3(-half.x+.012,lip_y,front+.002)]
	face.call(band,Vector3.BACK,lip)
	var shine := [Vector3(-half.x+.012,half.y-.012,front+.001),Vector3(half.x-.012,half.y-.012,front+.001),Vector3(half.x-chamfer*.6,half.y-.004,front+.001),Vector3(-half.x+chamfer*.6,half.y-.004,front+.001)]
	face.call(shine,Vector3.BACK,TAG_SLATE.lightened(.16))
	return surface.commit()

const PEDESTALS := {"coin":[.34,.12,-.47],"amber":[.30,.11,-.40],"crown":[.44,.17,-.40],"chalice":[.44,.17,-.40],"idol":[.40,.14,-.42],"relic":[.40,.14,-.40]}

static func _pedestal(world: MountainWorld, holder: Node3D, wall_local_z: float, id: int, shadows: bool, kind: String, quality: String) -> void:
	if world.visuals==null: return
	var visuals: MountainVisuals = world.visuals
	# A find hangs in front of the face: no pedestal and no painted shade
	# under it, only its own real shadow.
	if visuals.finds_without_pedestal(): return
	var size: Array = PEDESTALS.get(kind,[.32,.11,-.42])
	var random := RandomNumberGenerator.new()
	random.seed = id*271+5
	var outline := PackedVector2Array()
	for corner in range(7):
		var angle := TAU*corner/7.0+random.randf_range(-.2,.2)
		outline.append(Vector2(cos(angle)*float(size[0]),sin(angle)*float(size[1])))
	var pedestal := Node3D.new()
	pedestal.name = "Каменный постамент" if kind in ["crown","chalice"] else "Каменная полка"
	pedestal.position = Vector3(0,float(size[2]),0)
	holder.add_child(pedestal)
	var stone := visuals.zone_color(float(holder.position.y)).lightened(.06)
	var mesh := visuals._outcrop(pedestal,outline,minf(-.1,wall_local_z),.0,.22,float(size[1])*.75,float(size[1])*.6,.7,stone,visuals.stone_material)
	visuals._skirt(pedestal,outline,-.01,minf(-.1,wall_local_z-.06),visuals.zone_color(float(holder.position.y)),.08,.16)
	mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if shadows else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	if quality!="battery":
		var tuft := Node3D.new()
		tuft.position = Vector3(float(size[0])*(.85 if id%2==0 else -.85),float(size[1])*.4,.05)
		tuft.scale = Vector3.ONE*.55
		pedestal.add_child(tuft)
		visuals._build_grass(tuft,random,false,.6)

static func _sparkle(world: MountainWorld, holder: Node3D, at: Vector3, size: float, phase: float) -> void:
	var quad := QuadMesh.new()
	quad.size = Vector2(size,size)
	var material := ShaderMaterial.new()
	material.shader = world.shader("loot_sparkle","shader_type spatial; render_mode unshaded, cull_disabled, blend_add, depth_draw_never, shadows_disabled; uniform float phase = 0.0; void fragment(){ vec2 p=abs(UV*2.0-1.0); float star=max(0.0,1.0-p.x*7.0-p.y*.9)+max(0.0,1.0-p.y*7.0-p.x*.9); float core=smoothstep(.35,0.0,length(p)); float pulse=.55+.45*sin(TIME*2.6+phase*6.28); ALBEDO=vec3(1.0,.93,.70); ALPHA=clamp(star*.9+core*.6,0.0,1.0)*pulse; }")
	material.set_shader_parameter("phase",phase)
	var sparkle := MeshInstance3D.new()
	sparkle.name = "Блеск"
	sparkle.mesh = quad
	sparkle.material_override = material
	sparkle.position = at
	sparkle.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	holder.add_child(sparkle)

static func _halo(world: MountainWorld, holder: Node3D, color: Color, size: float) -> void:
	var quad := QuadMesh.new()
	quad.size = Vector2(size,size)
	var material := ShaderMaterial.new()
	material.shader = world.shader("loot_halo","shader_type spatial; render_mode unshaded, cull_disabled, blend_add, depth_draw_never, shadows_disabled; uniform vec4 tint : source_color = vec4(1.0,.9,.6,1.0); void fragment(){ float d=length(UV*2.0-1.0); float ring=smoothstep(1.0,.55,d)*smoothstep(.15,.6,d); float pulse=.8+.2*sin(TIME*1.7); ALBEDO=tint.rgb; ALPHA=ring*.42*pulse; }")
	material.set_shader_parameter("tint",color)
	var halo := MeshInstance3D.new()
	halo.name = "Ореол редкости"
	halo.mesh = quad
	halo.material_override = material
	halo.position = Vector3(0,0,-.16)
	halo.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	holder.add_child(halo)
