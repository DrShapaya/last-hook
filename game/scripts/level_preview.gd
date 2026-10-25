class_name LevelPreview
extends Control

# Authored level-card art. Each biome is a generated raster background so the
# menu does not rebuild a scene from placeholder polygons at runtime.
var world: MountainWorld
var route_location := -1

static var _cached_backgrounds: Array[Texture2D] = []

static func get_card_background(location: int) -> Texture2D:
	if _cached_backgrounds.is_empty():
		var paths := [
			"res://assets/art/level_cards/standard-mountain-bg.png",
			"res://assets/art/level_cards/desert-canyon-bg.png",
			"res://assets/art/level_cards/snowy-summit-bg.png"
		]
		for path in paths:
			if ResourceLoader.exists(path):
				_cached_backgrounds.append(load(path) as Texture2D)
			else:
				_cached_backgrounds.append(null)
	var idx := clampi(location, 0, _cached_backgrounds.size() - 1)
	return _cached_backgrounds[idx] if idx >= 0 and idx < _cached_backgrounds.size() else null

func _draw() -> void:
	var w := size.x
	var h := size.y
	var location: int = route_location if route_location>=0 else world.location if is_instance_valid(world) else 0
	var background: Texture2D = get_card_background(location)
	if background != null:
		draw_texture_rect_region(background,Rect2(0,0,w,h),background_region(background,w,h))
	else:
		draw_rect(Rect2(0,0,w,h),Color("6d91ad"))

	# The flag is a menu affordance that belongs to the route card, not to the
	# artwork. It remains a single restrained overlay for all three locations.
	# Each generated background has its own summit height. Anchor the pole to
	# that summit instead of using one shared Y coordinate for every biome.
	var flag_x: float = [0.52,0.52,0.53][clampi(location,0,2)]
	var flag_y: float = [0.23,0.18,0.18][clampi(location,0,2)]
	var flag_top := Vector2(w*flag_x,h*flag_y)
	draw_line(flag_top+Vector2(0,2),flag_top+Vector2(0,-20),MenuSurface.INK,2,true)
	draw_colored_polygon(PackedVector2Array([
		flag_top+Vector2(1,-20),flag_top+Vector2(17,-15),flag_top+Vector2(1,-10)
	]),MenuSurface.HOLD)

func background_region(texture: Texture2D, width: float, height: float) -> Rect2:
	var source := texture.get_size()
	var target_ratio := width/maxf(height,1.0)
	var crop_height := source.x/target_ratio
	# Keep the upper skyline intact. The previous centered crop removed the
	# summit and made the overlay flag appear detached from the mountain.
	var crop_y := 0.0
	return Rect2(0,crop_y,source.x,minf(crop_height,source.y))
