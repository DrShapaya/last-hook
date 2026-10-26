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
	draw_flag(Vector2((summit.x-region.position.x)/region.size.x*w,(summit.y-region.position.y)/region.size.y*h),h,location)

# A summit flag of each expedition, planted straight into the peak: a slim
# pole with a finial and a cloth that ripples in the wind. The cloth is a grid
# shaded along its folds, and its emblem is laid out in cloth coordinates, so
# the picture bends with the folds instead of sliding over them.
#   0 standard mountain  red swallowtail, white snowy peak
#   1 desert canyon      long tapering pennant, gold sun
#   2 snowy summit       blue banner, white stripes and a star
const FLAG_STYLES := [
	{"shape":"swallowtail","main":Color("d4452f"),"dark":Color("8e2a22"),"light":Color("f27a4a"),"mark":Color("fbf3e6"),"pole":Color("3a2c22"),"finial":Color("e8b844"),"length":.86,"depth":.5},
	{"shape":"pennant","main":Color("c9542b"),"dark":Color("7c2a1e"),"light":Color("f09a45"),"mark":Color("ffd25a"),"pole":Color("4d2a1c"),"finial":Color("f2c25a"),"length":1.05,"depth":.48},
	{"shape":"banner","main":Color("3a6fc0"),"dark":Color("1f4382"),"light":Color("6b9fe0"),"mark":Color("f4fbff"),"pole":Color("2b3a4c"),"finial":Color("cfe4f5"),"length":.8,"depth":.5},
]

func draw_flag(base: Vector2, card_height: float, location: int = 0) -> void:
	var style: Dictionary = FLAG_STYLES[clampi(location,0,FLAG_STYLES.size()-1)]
	var pole := clampf(card_height*.13,26.0,60.0)
	# The foot goes a little into the peak: nothing stands out under it.
	var foot := base+Vector2(0,pole*.06)
	var top := base-Vector2(0,pole)
	var t := Time.get_ticks_msec()*.001+float(location)*1.7
	var length := pole*float(style["length"])
	var depth := pole*float(style["depth"])*.62
	# The pole: shadow, wood and a lit edge, then the finial.
	draw_line(foot+Vector2(1.3,0),top+Vector2(1.3,1),Color(0,0,0,.25),2.4,true)
	draw_line(foot,top,style["pole"],2.2,true)
	draw_line(foot+Vector2(-.6,0),top+Vector2(-.6,1.5),Color(1,1,1,.3),.8,true)
	draw_circle(top+Vector2(0,-1.5),2.4,style["finial"])
	draw_circle(top+Vector2(-.7,-2.2),1.0,Color(1,1,1,.8))
	var origin := top+Vector2(1.0,2.0)
	var shape: String = style["shape"]
	# Cloth point at (u along the flight, v across, both 0..1).
	var at := func(u: float, v: float) -> Vector2:
		var phase := t*4.4-u*5.8
		var wave := sin(phase)*depth*.16*u
		var droop := u*u*depth*.16
		var across := depth
		var middle := depth*.5
		if shape=="pennant":
			across = depth*(1.0-u*.9)
			middle = depth*.5+u*depth*.05
		elif shape=="banner":
			across = depth*(1.0-.06*u)
		return origin+Vector2(u*length*(1.0-.03*sin(phase)*u),middle+(v-.5)*across+wave+droop)
	var shade := func(u: float) -> float:
		return .5+.5*cos(t*4.4-u*5.8+.9)
	var columns := 14
	var rows := 4
	for column in range(columns):
		for row in range(rows):
			var u0 := float(column)/columns
			var u1 := float(column+1)/columns
			var v0 := float(row)/rows
			var v1 := float(row+1)/rows
			# The swallowtail splits into two tails past NOTCH: each half of the
			# rows narrows towards its own edge, opening the notch smoothly.
			var upper_half := row<rows/2
			var cell := PackedVector2Array([at.call(u0,_tail(v0,u0,upper_half,shape)),at.call(u1,_tail(v0,u1,upper_half,shape)),at.call(u1,_tail(v1,u1,upper_half,shape)),at.call(u0,_tail(v1,u0,upper_half,shape))])
			var colors := PackedColorArray()
			for corner in [[u0,v0],[u1,v0],[u1,v1],[u0,v1]]:
				var lit: float = shade.call(corner[0])
				var tone: Color = (style["dark"] as Color).lerp(style["main"],.55+.45*lit)
				tone = tone.lerp(style["light"],maxf(0.0,lit-.7)*.9*float(corner[0]))
				colors.append(tone.darkened(.12*float(corner[1])))
			draw_polygon(cell,colors)
	# The emblem, in cloth coordinates.
	var mark: Color = style["mark"]
	match location:
		0:
			draw_colored_polygon(_cloth_poly(at,[Vector2(.16,.78),Vector2(.34,.24),Vector2(.44,.48),Vector2(.52,.36),Vector2(.68,.78)]),Color(mark,.95))
			draw_colored_polygon(_cloth_poly(at,[Vector2(.27,.45),Vector2(.34,.24),Vector2(.41,.45),Vector2(.37,.40),Vector2(.34,.47),Vector2(.31,.41)]),Color("cfdbe6"))
		1:
			var sun := Vector2(.3,.5)
			var disc: Array = []
			for step in range(16):
				var angle := TAU*step/16.0
				disc.append(sun+Vector2(cos(angle)*.1,sin(angle)*.24))
			draw_colored_polygon(_cloth_poly(at,disc),mark)
			for ray in range(8):
				var angle := TAU*ray/8.0+.2
				var inner := sun+Vector2(cos(angle)*.13,sin(angle)*.31)
				var outer := sun+Vector2(cos(angle)*.2,sin(angle)*.47)
				draw_line(at.call(inner.x,inner.y),at.call(outer.x,outer.y),Color(mark,.9),1.4,true)
		2:
			for band in [[.22,.32],[.68,.78]]:
				draw_colored_polygon(_cloth_poly(at,[Vector2(0,band[0]),Vector2(1,band[0]),Vector2(1,band[1]),Vector2(0,band[1])],12),Color(mark,.9))
			var star: Array = []
			for step in range(10):
				var angle := -PI*.5+TAU*step/10.0
				var radius := (.13 if step%2==0 else .055)
				star.append(Vector2(.42,.5)+Vector2(cos(angle)*radius*.62,sin(angle)*radius*1.5))
			draw_colored_polygon(_cloth_poly(at,star),mark)
	# An antialiased outline smooths the silhouette; the hem on the pole side
	# is a little heavier.
	var outline := PackedVector2Array()
	for step in range(columns+1): outline.append(at.call(float(step)/columns,0.0))
	if shape=="swallowtail":
		for v in [0.0,.25,.5]: outline.append(at.call(NOTCH+(1.0-NOTCH)*(1.0-v*2.0) if v<.5 else NOTCH,v))
	else:
		for v in [.25,.5,.75]: outline.append(at.call(1.0,v))
	for step in range(columns,-1,-1): outline.append(at.call(float(step)/columns,1.0))
	outline.append(outline[0])
	draw_polyline(outline,Color(style["dark"],.9),1.0,true)
	draw_line(at.call(0.0,0.0),at.call(0.0,1.0),style["dark"],1.6,true)

const NOTCH := .74

# The cloth row coordinate `v` at `u` on a swallowtail: past NOTCH the upper
# half squeezes up to the top edge and the lower half down to the bottom one.
func _tail(v: float, u: float, upper_half: bool, shape: String) -> float:
	if shape!="swallowtail" or u<=NOTCH: return v
	var open := (u-NOTCH)/(1.0-NOTCH)*.5
	return v*(1.0-open*2.0) if upper_half else 1.0-(1.0-v)*(1.0-open*2.0)

# A polygon given in cloth coordinates, mapped onto the waving cloth; long
# straight edges get extra points so they bend with it.
func _cloth_poly(at: Callable, points: Array, subdivide: int = 1) -> PackedVector2Array:
	var result := PackedVector2Array()
	for index in range(points.size()):
		var a: Vector2 = points[index]
		var b: Vector2 = points[(index+1)%points.size()]
		for step in range(subdivide):
			var p := a.lerp(b,float(step)/subdivide)
			result.append(at.call(p.x,p.y))
	return result

func background_region(texture: Texture2D, width: float, height: float) -> Rect2:
	var source := texture.get_size()
	var target_ratio := width/maxf(height,1.0)
	var crop_height := source.x/target_ratio
	# Keep the upper skyline intact, so the summit and its flag stay in frame.
	return Rect2(0,0,source.x,minf(crop_height,source.y))
