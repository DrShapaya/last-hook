extends RefCounted

# Finds on the face and in the bag.
#   coin      an authored 3D model (assets/models/treasures, built by
#             tools/build_treasure_models.gd) turning slowly; the bag draws
#             it from a turntable atlas of the same model
#   the rest  painted treasures (assets/sprites/treasures, cut from
#             references/treasures by tools/slice_sprites.py): a lantern,
#             compasses, rings, scrolls, chests, figurines, idols, tablets and
#             winter keepsakes, picked by the item's kind and the expedition
#             it comes from, and kept for the item by its id. The bag draws
#             the very same picture.
# Shared animations (one library for both):
#   idle_spin   the coin turns round its upright axis and bobs
#   idle_float  a painted treasure bobs and rocks a little
#   collect     the pickup: a hop, a spin and a shrink to nothing
# Model space: y up, z towards the camera, centred on the origin.

const DIR := "res://assets/models/treasures"
const SPRITES := "res://assets/sprites"
const KINDS := ["coin","amber","crystal","star","crown","chalice","idol","relic","material"]
const PORTRAIT_FRAMES := 24
const PORTRAIT_CELL := 128
# Seconds per idle cycle; the coin's atlas covers one cycle.
const CYCLE := 3.2
# Node layout of an instance: the animations move these.
const PIVOT := "Pivot"
const SPIN := "Pivot/Spin"
const TAG := "Pivot/Tag"
# A painted treasure's larger side on the face, in metres.
const SPRITE_SIZE := .58
# Painted treasures by kind, as sprite paths under SPRITES: every kind has
# pictures in each expedition's own sheet (THEMES), so a find always belongs
# to its place.
const POOLS := {
	"amber":["treasures/treasure_a_3","treasures/treasure_a_8","treasures/treasure_b_1","treasures/treasure_b_2","treasures/treasure_b_6","treasures/treasure_desert_8","treasures/treasure_winter_7","treasures/treasure_winter_5"],
	"crystal":["treasures/treasure_a_2","treasures/treasure_a_5","treasures/treasure_a_6","treasures/treasure_b_5","treasures/treasure_b_7","treasures/treasure_b_9","treasures/treasure_desert_9","treasures/treasure_winter_6","treasures/treasure_winter_1"],
	"star":["treasures/treasure_a_1","treasures/treasure_a_7","treasures/treasure_b_10","treasures/treasure_desert_6","treasures/treasure_desert_2","treasures/treasure_winter_3"],
	"crown":["treasures/treasure_a_9","treasures/treasure_a_10","treasures/treasure_desert_10","treasures/treasure_winter_4"],
	"chalice":["treasures/treasure_b_4","treasures/treasure_desert_1","treasures/treasure_desert_4","treasures/treasure_winter_8"],
	"idol":["treasures/treasure_b_8","treasures/treasure_desert_7","treasures/treasure_desert_3","treasures/treasure_winter_9"],
	"relic":["treasures/treasure_a_4","treasures/treasure_b_3","treasures/treasure_desert_5","treasures/treasure_winter_2"],
}
# Regional materials: a natural keepsake each, the same on every expedition;
# the core is a crystal of the expedition's own kind.
const MATERIALS := {"fiber":"treasures/treasure_winter_7","silk":"treasures/treasure_a_8","sinew":"treasures/treasure_winter_2"}
const CORES := {"green_peak":"crystals/crystal_blue_3","stone_spires":"crystals/crystal_amber_1","sky_city":"crystals/crystal_ice_1"}
# The sheets an expedition's finds come from.
const THEMES := {"green_peak":["treasure_a","treasure_b"],"stone_spires":["treasure_desert"],"sky_city":["treasure_winter"]}

const SPRITE_SHADER := "shader_type spatial; render_mode cull_disabled; uniform sampler2D albedo_tex : source_color, filter_linear_mipmap, repeat_disable; void fragment(){ vec4 c = texture(albedo_tex, UV); ALBEDO = c.rgb; ALPHA = c.a; ALPHA_SCISSOR_THRESHOLD = .5; ROUGHNESS = .55; NORMAL = FRONT_FACING ? NORMAL : -NORMAL; }"

# The model kind of an item; items without one fall back to their tier.
static func kind_of(item: Dictionary) -> String:
	var kind := str(item.get("kind",""))
	if kind.is_empty():
		kind = ["coin","amber","relic","crystal","idol","star"][clampi(int(item.get("tier",0)),0,5)]
	return kind

static func kind_for(item: Dictionary) -> String:
	var kind := kind_of(item)
	return kind if kind in KINDS else "relic"

static func model_path(kind: String) -> String:
	return DIR.path_join("treasure_%s.glb" % kind)

static func animations_path() -> String:
	return DIR.path_join("treasure_animations.tres")

static func portrait_path(key: String) -> String:
	return DIR.path_join("portrait_%s.png" % key)

static func idle_animation(kind: String) -> String:
	return "idle_spin" if kind=="coin" else "idle_float"

# The painted treasure an item shows: from its kind's pool, the expedition's
# own sheet when it has one there, the same one for the same item.
static func sprite_for(item: Dictionary) -> String:
	# Finds of the current generator carry their set's picture (ItemCatalog.dress).
	if not str(item.get("sprite","")).is_empty():
		var own := SPRITES.path_join(str(item["sprite"])+".png")
		if ResourceLoader.exists(own): return own
	var kind := kind_for(item)
	if kind=="material":
		var set_id := str(item.get("set_id",""))
		if set_id=="core": return SPRITES.path_join(str(CORES.get(str(item.get("location_id","")),CORES["green_peak"]))+".png")
		return SPRITES.path_join(str(MATERIALS.get(set_id,MATERIALS["fiber"]))+".png")
	var pool: Array = POOLS.get(kind,POOLS["relic"])
	var themed: Array = []
	for sheet: String in THEMES.get(str(item.get("location_id","")),[]):
		for path: String in pool:
			if path.get_file().begins_with(sheet+"_"): themed.append(path)
	var choices := themed if not themed.is_empty() else pool
	var key := str(item.get("item_id","")) if not str(item.get("item_id","")).is_empty() else str(item.get("id",0))
	return SPRITES.path_join(str(choices[posmod(hash(key+kind),choices.size())])+".png")

static var _textures := {}
static var _materials := {}

static func _texture(path: String) -> Texture2D:
	if not _textures.has(path): _textures[path] = load(path)
	return _textures[path]

static func _sprite_material(path: String) -> ShaderMaterial:
	if not _materials.has(path):
		if not _materials.has("shader"):
			var shader := Shader.new()
			shader.code = SPRITE_SHADER
			_materials["shader"] = shader
		var material := ShaderMaterial.new()
		material.shader = _materials["shader"]
		material.set_shader_parameter("albedo_tex",_texture(path))
		_materials[path] = material
	return _materials[path]

# Root (with the AnimationPlayer) > Pivot (bob, tag) > Spin (turn) > model.
static func instantiate(item: Dictionary, shadows: bool) -> Node3D:
	var kind := kind_for(item)
	var root := Node3D.new()
	root.name = "Сокровище"
	var pivot := Node3D.new()
	pivot.name = PIVOT
	root.add_child(pivot)
	var spin := Node3D.new()
	spin.name = "Spin"
	pivot.add_child(spin)
	# The price tag hangs here (LootVisuals.price_tag); the idle swings it.
	var tag := Node3D.new()
	tag.name = "Tag"
	pivot.add_child(tag)
	var model: Node3D
	if kind=="coin":
		model = (load(model_path(kind)) as PackedScene).instantiate() as Node3D
	else:
		var path := sprite_for(item)
		var texture := _texture(path)
		var aspect := texture.get_width()/float(texture.get_height())
		var quad := QuadMesh.new()
		quad.size = Vector2(SPRITE_SIZE,SPRITE_SIZE/aspect) if aspect>1.0 else Vector2(SPRITE_SIZE*aspect,SPRITE_SIZE)
		var sprite := MeshInstance3D.new()
		sprite.name = "Рисунок сокровища"
		sprite.mesh = quad
		# Idle bob/rock and texture filtering need a little culling margin;
		# otherwise a treasure can disappear one frame at the edge of a view.
		sprite.custom_aabb = AABB(Vector3(-quad.size.x*.5-.08,-quad.size.y*.5-.08,-.10),Vector3(quad.size.x+.16,quad.size.y+.16,.20))
		sprite.material_override = _sprite_material(path)
		model = Node3D.new()
		model.add_child(sprite)
		root.set_meta("sprite",path)
	model.name = "Модель сокровища"
	spin.add_child(model)
	var bottom := 0.0
	for mesh: MeshInstance3D in model.find_children("*","MeshInstance3D",true,false):
		bottom = minf(bottom,mesh.get_aabb().position.y)
		mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if shadows else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	tag.position = Vector3(0,bottom+.01,0)
	var player := AnimationPlayer.new()
	player.name = "Анимация"
	player.add_animation_library("",load(animations_path()) as AnimationLibrary)
	root.add_child(player)
	root.set_meta("kind",kind)
	return root

static func play_idle(root: Node3D, phase: float) -> void:
	var player := root.get_node("Анимация") as AnimationPlayer
	player.play(idle_animation(str(root.get_meta("kind",""))))
	player.seek(fposmod(phase,1.0)*CYCLE,true)

# --- Bag icons ----------------------------------------------------------------------

# The picture the bag draws for an item and the part of it to draw now: the
# coin's turntable frame, or the whole painted treasure.
static func icon_texture(item: Dictionary) -> Texture2D:
	if kind_for(item)=="coin": return _texture(portrait_path("coin"))
	return _texture(sprite_for(item))

static func icon_region(item: Dictionary, time: float) -> Rect2:
	if kind_for(item)=="coin":
		var frame := int(floor(fposmod(time/CYCLE,1.0)*PORTRAIT_FRAMES))%PORTRAIT_FRAMES
		return Rect2(frame*PORTRAIT_CELL,0,PORTRAIT_CELL,PORTRAIT_CELL)
	return Rect2(Vector2.ZERO,icon_texture(item).get_size())
