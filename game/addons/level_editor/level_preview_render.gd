@tool
extends SubViewport

# The whole level seen from the front, as in the game: the baked section
# scenes (they hold no scripts, so they render in the editor) under the
# game's sun and ambient light, through one orthographic camera covering the
# level. Rendered once per load; `texture()` is what the canvas shows.

const PIXELS_PER_UNIT := 16
const SUN_DIRECTION := Vector3(.30,-.50,-.81)

var camera := Camera3D.new()
var scenery := Node3D.new()
var top := 0.0

func _init() -> void:
	own_world_3d = true
	transparent_bg = true
	msaa_3d = Viewport.MSAA_2X
	render_target_update_mode = SubViewport.UPDATE_DISABLED
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.keep_aspect = Camera3D.KEEP_HEIGHT
	camera.current = true
	add_child(camera)
	var sun := DirectionalLight3D.new()
	sun.basis = Basis.looking_at(SUN_DIRECTION,Vector3.UP)
	sun.light_color = Color("fff0d2")
	sun.light_energy = .46
	sun.light_specular = .35
	add_child(sun)
	var environment := Environment.new()
	environment.background_mode = Environment.BG_CLEAR_COLOR
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color("b6c7d6")
	environment.ambient_light_energy = .62
	environment.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	var world_environment := WorldEnvironment.new()
	world_environment.environment = environment
	add_child(world_environment)
	add_child(scenery)

# Shows the baked sections of `directory` (a level folder) for `quality`.
# Returns how many sections were found.
func show_level(directory: String, quality: String, level_top: float, x_min: float, x_max: float) -> int:
	for child in scenery.get_children(): child.queue_free()
	top = level_top
	size = Vector2i(roundi((x_max-x_min)*PIXELS_PER_UNIT),roundi(top*PIXELS_PER_UNIT))
	camera.size = top
	camera.position = Vector3((x_min+x_max)*.5,top*.5,40)
	var count := 0
	var folder := directory.path_join(quality)
	if DirAccess.dir_exists_absolute(folder):
		for file in DirAccess.get_files_at(folder):
			var path := folder.path_join(file.trim_suffix(".remap"))
			if path.get_extension()!="scn": continue
			var scene := load(path) as PackedScene
			if scene==null: continue
			scenery.add_child(scene.instantiate())
			count += 1
	render_target_update_mode = SubViewport.UPDATE_ONCE
	return count
