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

# Summit of each background, as a fraction of the source image. Measured on
# the art, so the flag stands on the rock at any card size or crop.
const SUMMITS := [Vector2(.5098,.1283),Vector2(.5371,.1022),Vector2(.5410,.1029)]

func _process(_delta: float) -> void:
	# The pennant waves; only a visible card redraws.
	if is_visible_in_tree(): queue_redraw()

func _draw() -> void:
	var w := size.x
	var h := size.y
	var location: int = route_location if route_location>=0 else world.location if is_instance_valid(world) else 0
	var background: Texture2D = get_card_background(location)
	if background == null:
		draw_rect(Rect2(0,0,w,h),Color("6d91ad"))
		return
	var region := background_region(background,w,h)
	draw_texture_rect_region(background,Rect2(0,0,w,h),region)
	var summit: Vector2 = SUMMITS[clampi(location,0,SUMMITS.size()-1)]*background.get_size()
	draw_flag(Vector2((summit.x-region.position.x)/region.size.x*w,(summit.y-region.position.y)/region.size.y*h),h)

# A summit flag: a pole planted in a small cairn and a hold-yellow pennant that
# ripples in the wind, shaded along its folds.
func draw_flag(base: Vector2, card_height: float) -> void:
	var pole := clampf(card_height*.12,24.0,56.0)
	var top := base-Vector2(0,pole)
	var t := Time.get_ticks_msec()*.001
	# Contact shadow and cairn ground the pole on the rock.
	draw_set_transform(base+Vector2(1,1),0,Vector2(1,.35))
	draw_circle(Vector2.ZERO,pole*.2,Color(0,0,0,.3))
	draw_set_transform(Vector2.ZERO)
	var stone := pole*.09
	draw_colored_polygon(PackedVector2Array([base+Vector2(-stone*1.9,1),base+Vector2(-stone*1.2,-stone*.9),base+Vector2(stone*.2,-stone*1.1),base+Vector2(stone*1.1,1)]),Color("5d6670"))
	draw_colored_polygon(PackedVector2Array([base+Vector2(-stone*.4,1),base+Vector2(stone*.6,-stone*1.4),base+Vector2(stone*1.8,-stone*.6),base+Vector2(stone*2.1,1)]),Color("838d96"))
	# Pole with a soft shadow, a lit edge and a brass finial.
	draw_line(base+Vector2(1.4,0),top+Vector2(1.4,1),Color(0,0,0,.28),2.6,true)
	draw_line(base,top,Color("2b3138"),2.6,true)
	draw_line(base+Vector2(-.7,0),top+Vector2(-.7,2),Color(1,1,1,.35),.9,true)
	draw_circle(top,2.6,MenuSurface.HOLD_LIP)
	draw_circle(top+Vector2(-.6,-.6),1.2,MenuSurface.COIN_LIGHT)
	var length := pole*.78
	var depth := pole*.44
	var steps := 12
	var upper := PackedVector2Array()
	var lower := PackedVector2Array()
	var upper_colors := PackedColorArray()
	var lower_colors := PackedColorArray()
	for index in range(steps+1):
		var u := float(index)/steps
		var phase := t*4.2-u*5.6
		# Fixed at the pole, free at the tip.
		var wave := sin(phase)*depth*.14*u
		var droop := u*u*depth*.12
		var taper := 1.0-.22*u
		upper.append(top+Vector2(u*length,3+wave+droop))
		lower.append(top+Vector2(u*length*.98,3+depth*taper+wave+droop))
		var fold := clampf(.5+.5*cos(phase),0,1)*.5*u
		upper_colors.append(MenuSurface.HOLD.lerp(MenuSurface.HOLD_LIP,fold))
		lower_colors.append(MenuSurface.HOLD.lerp(MenuSurface.HOLD_LIP,fold+.15))
	var points := upper.duplicate()
	var colors := upper_colors.duplicate()
	for index in range(steps,-1,-1):
		points.append(lower[index])
		colors.append(lower_colors[index])
	draw_polygon(points,colors)
	var outline := points.duplicate()
	outline.append(points[0])
	draw_polyline(outline,Color(MenuSurface.HOLD_LIP,.85),1.0,true)

func background_region(texture: Texture2D, width: float, height: float) -> Rect2:
	var source := texture.get_size()
	var target_ratio := width/maxf(height,1.0)
	var crop_height := source.x/target_ratio
	# Keep the upper skyline intact, so the summit and its flag stay in frame.
	return Rect2(0,0,source.x,minf(crop_height,source.y))
