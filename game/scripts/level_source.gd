@tool
class_name LevelSource
extends RefCounted

# The authored source of a level (docs/LEVEL_PIPELINE.md): a brief in
# level.json and painted masks, one 8-bit greyscale PNG per layer.
#
#   res://levels/<level id>_r<route>/source/level.json
#   res://levels/<level id>_r<route>/source/<mask>.png
#
# The folder carries a .gdignore: Godot neither imports the masks as
# textures nor ships them; tools and the editor read the files directly.
#
# Masks are in world units at PX_PER_UNIT, X from X_MIN to X_MAX; the top
# row of the image is the top of the level (summit + 6), the bottom row y=0.

const FORMAT := 1
const PX_PER_UNIT := 8
const X_MIN := -20.0
const X_MAX := 20.0
const SUMMIT_MARGIN := 6.0
# Layers and what they mean; see docs/LEVEL_PIPELINE.md.
const LAYERS := {
	"silhouette":"Силуэт горы",
	"depth":"Ближе — дальше",
	"solid":"Твёрдые выступы",
	"route":"Коридор маршрута",
	"branch":"Ответвления и тайники",
	"rest":"Места отдыха",
	"difficulty":"Сложность (светлее — проще)",
	"loot":"Карманы награды",
	"moss":"Мох",
	"snow":"Снег",
	"cracks":"Трещины",
	"dust":"Пыль",
	"decor":"Плотность оформления",
}

var directory := ""
var brief: Dictionary = {}
# name -> Image (FORMAT_L8); zone masks are named "zone_<n>".
var masks: Dictionary = {}

static func source_directory(level_location: int, level_route: int) -> String:
	return LevelBake.directory(level_location,level_route).path_join("source")

static func exists(path: String) -> bool:
	return FileAccess.file_exists(path.path_join("level.json"))

static func image_size(height: float) -> Vector2i:
	return Vector2i(roundi((X_MAX-X_MIN)*PX_PER_UNIT),ceili((height+SUMMIT_MARGIN)*PX_PER_UNIT))

func height() -> float:
	return float(brief.get("height",120.0))

func size() -> Vector2i:
	return image_size(height())

func top() -> float:
	return height()+SUMMIT_MARGIN

# World point -> pixel position (fractional; pixel centres at .5).
func to_pixel(point: Vector2) -> Vector2:
	return Vector2((point.x-X_MIN)*PX_PER_UNIT,(top()-point.y)*PX_PER_UNIT)

func to_world(pixel: Vector2) -> Vector2:
	return Vector2(pixel.x/PX_PER_UNIT+X_MIN,top()-pixel.y/PX_PER_UNIT)

# A blank layer of the level's size.
func new_mask() -> Image:
	var dimensions := size()
	return Image.create_empty(dimensions.x,dimensions.y,false,Image.FORMAT_L8)

# 0..1 at a world point, bilinear; 0 outside the image or for a missing layer.
func sample(layer: String, point: Vector2) -> float:
	var image: Image = masks.get(layer)
	if image==null: return 0.0
	var pixel := to_pixel(point)-Vector2(.5,.5)
	var base := Vector2i(floori(pixel.x),floori(pixel.y))
	var t := pixel-Vector2(base)
	var result := 0.0
	for corner in [Vector2i(0,0),Vector2i(1,0),Vector2i(0,1),Vector2i(1,1)]:
		var at: Vector2i = base+corner
		if at.x<0 or at.y<0 or at.x>=image.get_width() or at.y>=image.get_height(): continue
		var weight := (t.x if corner.x==1 else 1.0-t.x)*(t.y if corner.y==1 else 1.0-t.y)
		result += image.get_pixelv(at).r*weight
	return result

static func open(path: String) -> LevelSource:
	if not exists(path): return null
	var source := LevelSource.new()
	source.directory = path
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(path.path_join("level.json")))
	if not parsed is Dictionary: return null
	source.brief = parsed
	for file in DirAccess.get_files_at(path):
		if file.get_extension().to_lower()!="png": continue
		var image := Image.load_from_file(ProjectSettings.globalize_path(path.path_join(file)))
		if image==null: continue
		if image.get_format()!=Image.FORMAT_L8: image.convert(Image.FORMAT_L8)
		source.masks[file.get_basename()] = image
	return source

func save(path: String = "") -> Error:
	if not path.is_empty(): directory = path
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(directory))
	var ignore := FileAccess.open(directory.path_join(".gdignore"),FileAccess.WRITE)
	if ignore!=null: ignore.close()
	brief["format"] = FORMAT
	var file := FileAccess.open(directory.path_join("level.json"),FileAccess.WRITE)
	if file==null: return FileAccess.get_open_error()
	file.store_string(JSON.stringify(brief,"\t",false))
	file.close()
	# Layers removed since the last save go with their files.
	for existing in DirAccess.get_files_at(directory):
		if existing.get_extension().to_lower()=="png" and not masks.has(existing.get_basename()):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(directory.path_join(existing)))
	for layer in masks:
		var error := (masks[layer] as Image).save_png(ProjectSettings.globalize_path(directory.path_join("%s.png" % layer)))
		if error!=OK: return error
	return OK
