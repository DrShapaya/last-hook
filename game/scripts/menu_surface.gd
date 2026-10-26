class_name MenuSurface
extends Control

# Shared visual vocabulary for the expedition screens. Menus live in the same
# daylight as the climb: sky backdrop, faceted limestone slabs with a dark lip
# underneath (like the holds), slate for selected states and hold-yellow for
# the one primary action. All coordinates are authored in the same portrait /
# landscape canvas, then scaled by GameHud.
const SKY_TOP := Color("4f9fe8")
const SKY_LOW := Color("bfe0f8")
const RIDGE_FAR := Color("a9d0f2")
const RIDGE_NEAR := Color("8dbde8")
const STONE := Color("efebe1")
const STONE_SHADE := Color("dcd5c4")
const STONE_LIP := Color("b9af97")
const INK := Color("1f2b35")
const INK_SOFT := Color("55636d")
const INK_FAINT := Color("8b959b")
const SLATE := Color("24323d")
const SLATE_LIP := Color("121b22")
const HOLD := Color("f6c32f")
const HOLD_LIP := Color("b88a12")
const ROPE := Color("b5712b")
const COIN := Color("c98612")
const COIN_LIGHT := Color("ffd15c")
const CRYSTAL := Color("2f7fd6")
const CRYSTAL_LIGHT := Color("9fd6ff")
const MOSS := Color("4a9a52")
const DANGER := Color("cc4b37")
const LOOT_COLORS := [Color("e4b35e"),Color("f08f72"),Color("86c6a0"),Color("78d5d2"),Color("af9bdf"),Color("d7dcea")]

# The route as a rope: a dotted path from the start to the summit flag, the
# climbed part laid as twisted rope, act boundaries as notches, the personal
# record as a hold with its own tag and the current height as a knot.
class RouteLine extends Control:
	const HEIGHT := 58.0
	var summit := 1200.0
	var zone := 200.0
	var record := -1.0
	var current := -1.0
	var progress := 0.0
	var progress_tween: Tween
	var caption := ""
	var font: Font
	var strong: Font
	var on_dark := false

	func track_y() -> float:
		return 32.0

	func x_of(meters: float) -> float:
		return 6+(size.x-34)*clampf(meters/maxf(1,summit),0,1)

	func _draw() -> void:
		var ink := STONE if on_dark else INK
		var soft := Color("c9d2d8") if on_dark else INK_SOFT
		var y := track_y()
		var left := 6.0
		var right := size.x-28
		# Bed of the path: a recessed groove the rope lies in.
		draw_line(Vector2(left,y),Vector2(right,y),Color(SLATE_LIP if not on_dark else Color.BLACK,.22),9,true)
		draw_line(Vector2(left,y+1),Vector2(right,y+1),Color(STONE,.35 if not on_dark else .08),5,true)
		var x := left+6
		while x<right-4:
			draw_circle(Vector2(x,y),1.4,Color(soft,.6))
			x += 8
		var zone_count := int(summit/maxf(1,zone))
		for index in range(1,zone_count):
			var tick := x_of(index*zone)
			draw_line(Vector2(tick,y-6),Vector2(tick,y+6),Color(soft,.55),2,true)
		var rope_end := x_of(progress)
		if progress>0.0:
			draw_line(Vector2(left,y),Vector2(rope_end,y),Color("7a4a1c"),6,true)
			draw_line(Vector2(left,y-1),Vector2(rope_end,y-1),ROPE,4,true)
			# Strands: short diagonal twists make it read as rope, not a bar.
			var twist := left+2
			while twist<rope_end-3:
				draw_line(Vector2(twist,y+2),Vector2(twist+3,y-3),Color("e0a15a",.8),1.2,true)
				twist += 5
		draw_circle(Vector2(left,y),4.5,ink)
		draw_circle(Vector2(left,y),2,HOLD)
		# Summit flag at the end of the path.
		var peak := Vector2(size.x-16,y)
		draw_colored_polygon(PackedVector2Array([peak+Vector2(-9,4),peak+Vector2(0,-6),peak+Vector2(9,4)]),Color(ink,.85))
		draw_line(peak+Vector2(0,-4),peak+Vector2(0,-27),ink,2,true)
		draw_colored_polygon(PackedVector2Array([peak+Vector2(1,-27),peak+Vector2(15,-23),peak+Vector2(13,-19),peak+Vector2(1,-16)]),HOLD)
		var taken: Array[Rect2] = []
		if current>=0:
			var at := Vector2(x_of(current),y)
			draw_circle(at,8,ink)
			draw_circle(at,5,HOLD)
			taken.append(tag("%d м" % roundi(current),at.x,strong,HOLD,INK,15))
		if record>0:
			var at := x_of(record)
			# The record is a hold: a little faceted pebble on the path.
			draw_colored_polygon(PackedVector2Array([Vector2(at-6,y+1),Vector2(at-3,y-5),Vector2(at+4,y-5),Vector2(at+6,y+1),Vector2(at+2,y+5),Vector2(at-4,y+5)]),HOLD_LIP)
			draw_colored_polygon(PackedVector2Array([Vector2(at-5,y),Vector2(at-2,y-4),Vector2(at+3,y-4),Vector2(at+5,y),Vector2(at+1,y+3),Vector2(at-3,y+3)]),HOLD)
			var rect := tag_rect("Рекорд %d м" % roundi(record),at,font,13)
			var free := true
			for other in taken: free = free and not other.grow(4).intersects(rect)
			if free: tag("Рекорд %d м" % roundi(record),at,font,Color(SLATE,.9) if not on_dark else Color(STONE,.92),STONE if not on_dark else INK,13)
		var use := font if font!=null else ThemeDB.fallback_font
		if not caption.is_empty():
			draw_string(use,Vector2(left-2,y+24),caption,HORIZONTAL_ALIGNMENT_LEFT,size.x*.6,13,soft)
		var summit_text := "%d м" % roundi(summit)
		draw_string(use,Vector2(size.x-4-text_width(summit_text,use,13),y+24),summit_text,HORIZONTAL_ALIGNMENT_LEFT,-1,13,soft)

	func animate_progress(value: float) -> void:
		var target := clampf(value,0.0,summit)
		if progress_tween!=null and progress_tween.is_valid(): progress_tween.kill()
		if progress<0.0: progress = 0.0
		if is_zero_approx(progress-target):
			progress = target
			queue_redraw()
			return
		progress_tween = create_tween()
		progress_tween.tween_method(func(v: float):
			progress = v
			queue_redraw(),progress,target,.95).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)

	func text_width(value: String, use: Font, font_size: int) -> float:
		return (use if use!=null else ThemeDB.fallback_font).get_string_size(value,HORIZONTAL_ALIGNMENT_LEFT,-1,font_size).x

	func tag_rect(value: String, center: float, use: Font, font_size: int) -> Rect2:
		var width := text_width(value,use,font_size)+16
		var left := clampf(center-width*.5,0,size.x-width)
		return Rect2(left,0,width,22)

	# A small chamfered tag above the path with a notch pointing at its spot.
	func tag(value: String, center: float, use: Font, face: Color, color: Color, font_size: int) -> Rect2:
		var rect := tag_rect(value,center,use,font_size)
		var box := StyleBoxFlat.new()
		box.bg_color = face
		box.set_corner_radius_all(5)
		box.corner_detail = 1
		draw_style_box(box,rect)
		var tip := clampf(center,rect.position.x+6,rect.end.x-6)
		draw_colored_polygon(PackedVector2Array([Vector2(tip-5,rect.end.y-1),Vector2(tip+5,rect.end.y-1),Vector2(tip,rect.end.y+5)]),face)
		draw_string(use if use!=null else ThemeDB.fallback_font,Vector2(rect.position.x+8,rect.position.y+16),value,HORIZONTAL_ALIGNMENT_LEFT,-1,font_size,color)
		return rect

var hud
var game
var model: GameModel
var landscape := false

func prepare(owner_hud) -> void:
	hud = owner_hud
	game = hud.game
	model = game.model
	landscape = hud.wide
	size = Vector2(1080,660) if landscape else Vector2(540,960)
	position = (hud.root.size-size)*.5
	mouse_filter = Control.MOUSE_FILTER_STOP
	modulate.a = 0
	create_tween().tween_property(self,"modulate:a",1.0,.18).set_trans(Tween.TRANS_SINE)

func slab(parent: Node, at: Vector2, dimensions: Vector2, face: Color = STONE, lip: Color = STONE_LIP, lip_size: int = 4) -> Panel:
	var node := Panel.new()
	node.position = at
	node.size = dimensions
	node.mouse_filter = Control.MOUSE_FILTER_IGNORE
	node.add_theme_stylebox_override("panel",hud.slab_style(face,lip,lip_size))
	parent.add_child(node)
	return node

# Kept for callers that think in terms of cards; every card is a stone slab.
func card(parent: Node, at: Vector2, dimensions: Vector2, face: Color = STONE, lip: Color = STONE_LIP, _radius: int = 10) -> Panel:
	return slab(parent,at,dimensions,face,lip)

func text(parent: Node, value: String, at: Vector2, dimensions: Vector2, font_size: int = 16, color: Color = INK, weight: String = "body") -> Label:
	var node: Label = hud.label(parent,value,font_size,color)
	node.position = at
	node.size = dimensions
	node.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	if weight=="display": node.add_theme_font_override("font",hud.heading_font)
	elif weight=="strong": node.add_theme_font_override("font",hud.strong_font)
	return node

func title(parent: Node, value: String, at: Vector2, width: float, font_size: int = 34) -> Label:
	return text(parent,value,at,Vector2(width,font_size*1.3),font_size,INK,"display")

func paragraph(parent: Node, value: String, at: Vector2, dimensions: Vector2, font_size: int = 15, color: Color = INK_SOFT) -> Label:
	var node := text(parent,value,at,dimensions,font_size,color)
	node.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	node.size = dimensions
	# A paragraph is never cut: it grows down to fit all its lines.
	var lines := node.get_line_count()
	node.size.y = maxf(dimensions.y,lines*node.get_line_height()+maxi(0,lines-1)*node.get_theme_constant("line_spacing"))
	return node

func symbol(parent: Node, kind: int, at: Vector2, dimensions: Vector2 = Vector2(28,28), color: Color = INK) -> UiSymbol:
	var node := UiSymbol.new()
	node.kind = kind
	node.tint = color
	node.tip_count = model.hook_tips()
	node.hook_count = model.hook_count()
	node.position = at
	node.size = dimensions
	node.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(node)
	return node

func action(parent: Node, value: String, at: Vector2, dimensions: Vector2, callback: Callable, tone: String = "secondary") -> Button:
	var node: Button = hud.button(parent,value,callback,tone=="primary")
	hud.skin_button(node,tone)
	node.position = at
	node.custom_minimum_size = dimensions
	node.size = dimensions
	return node

func route(parent: Node, at: Vector2, width: float, current: float = -1.0, on_dark: bool = false, caption: String = "") -> RouteLine:
	var line := RouteLine.new()
	line.position = at
	line.size = Vector2(width,RouteLine.HEIGHT)
	line.caption = caption
	line.summit = game.summit_height*10
	line.zone = float(model.balance["zone_units"])*10
	# The record of the route on show and of the mode it is climbed in.
	var on_menu: bool = game.state=="menu"
	line.record = model.record(game.lobby_location if on_menu else game.selected_location,"summit" if on_menu else game.run_mode)
	line.current = current
	line.font = hud.body_font
	line.strong = hud.heading_font
	line.on_dark = on_dark
	line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(line)
	return line

# Segmented control: a recessed track with a raised slate thumb under the
# chosen option. A tap glides the thumb across and recolours the labels in
# place; callers rebuild nothing unless the choice changes the page.
func segmented(parent: Node, at: Vector2, width: float, options: Array, selected: int, callback: Callable, height: float = 46) -> Array[Button]:
	var buttons: Array[Button] = []
	slab(parent,at,Vector2(width,height),STONE_SHADE,Color.TRANSPARENT,0)
	var inset := 4.0
	var each := (width-inset*2)/options.size()
	var thumb := slab(parent,at+Vector2(inset+maxi(selected,0)*each,inset),Vector2(each,height-inset*2),SLATE,SLATE_LIP,3)
	thumb.visible = selected>=0
	thumb.set_meta("index",selected)
	var clear: StyleBoxFlat = hud.slab_style(Color(STONE,0),Color.TRANSPARENT,0,9)
	clear.content_margin_left = 6
	clear.content_margin_right = 6
	clear.content_margin_top = 4
	clear.content_margin_bottom = 4
	var hover := clear.duplicate() as StyleBoxFlat
	hover.bg_color = Color(STONE,.35)
	for index in range(options.size()):
		var button := action(parent,str(options[index]),at+Vector2(inset+index*each,inset),Vector2(each,height-inset*2),_segment_pressed.bind(buttons,thumb,index,callback,at.x+inset,each),"ghost")
		button.add_theme_font_size_override("font_size",15)
		for state_name in ["normal","pressed","disabled"]: button.add_theme_stylebox_override(state_name,clear)
		button.add_theme_stylebox_override("hover",hover)
		buttons.append(button)
	paint_segments(buttons,selected)
	return buttons

func paint_segments(buttons: Array[Button], selected: int) -> void:
	for index in range(buttons.size()):
		var ink := STONE if index==selected else INK_SOFT
		for color_name in ["font_color","font_hover_color","font_pressed_color","font_hover_pressed_color","font_focus_color"]:
			buttons[index].add_theme_color_override(color_name,ink if index==selected or color_name=="font_color" else INK)

func _segment_pressed(buttons: Array[Button], thumb: Panel, index: int, callback: Callable, left: float, each: float) -> void:
	if not is_instance_valid(thumb) or int(thumb.get_meta("index",-1))==index: return
	# A disabled/locked segment may handle the tap itself and return false;
	# leave the selected thumb exactly where it was in that case.
	var result: Variant = callback.call(index)
	if result is bool and not result: return
	thumb.set_meta("index",index)
	thumb.visible = true
	var tween := thumb.create_tween()
	tween.tween_property(thumb,"position:x",left+index*each,.24).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	paint_segments(buttons,index)

# A small hold-yellow "Скоро" plate for features that are not open yet.
func soon_tag(parent: Node, at: Vector2, width: float = 54.0) -> Panel:
	var badge := slab(parent,at,Vector2(width,18),HOLD,HOLD_LIP,2)
	text(badge,"Скоро",Vector2(0,0),Vector2(width,16),11,INK,"strong").horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	return badge

# A short wiggle of a "Скоро" plate and a note: the answer to a tap on
# something that is not open yet.
func wiggle_soon(badge: Control, message: String) -> void:
	if is_instance_valid(badge):
		badge.pivot_offset = badge.size*.5
		var tween := badge.create_tween()
		tween.tween_property(badge,"rotation",.12,.06)
		tween.tween_property(badge,"rotation",-.1,.09)
		tween.tween_property(badge,"rotation",0.0,.2).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	game.toast(message,1.8,"menu")

func coin_amount(parent: Node, value: int, at: Vector2, font_size: int = 17, color: Color = COIN, kind: int = 12) -> void:
	var icon := font_size+5
	symbol(parent,kind,at+Vector2(0,(font_size*1.35-icon)*.5),Vector2(icon,icon),color)
	var width: float = hud.heading_font.get_string_size(str(value),HORIZONTAL_ALIGNMENT_LEFT,-1,font_size).x+4
	text(parent,str(value),at+Vector2(icon+5,0),Vector2(width,font_size*1.35),font_size,INK,"display")

func wallet(at: Vector2) -> void:
	var coins := slab(self,at,Vector2(118,44))
	coin_amount(coins,int(model.profile["gold"]),Vector2(12,8),17,COIN,12)
	var gems := slab(self,at+Vector2(126,0),Vector2(82,44))
	coin_amount(gems,int(model.profile["diamonds"]),Vector2(10,8),17,CRYSTAL,13)

func time_string(seconds: float) -> String:
	var total := int(seconds)
	return "%d:%02d" % [total/60,total%60]

# Clips a drawn control to the same chamfered silhouette as the slabs. One
# shader serves every card; only its parameters differ, so nothing compiles
# while the menu is in use.
static var _rounded_shader: Shader

func rounded_material(dimensions: Vector2, cut: float = 14) -> ShaderMaterial:
	return chamfer_material(dimensions,cut)

static func chamfer_material(dimensions: Vector2, cut: float = 14) -> ShaderMaterial:
	if _rounded_shader==null:
		_rounded_shader = Shader.new()
		_rounded_shader.code = "shader_type canvas_item; uniform vec2 rect_size; uniform float cut; varying vec2 point; void vertex(){point=VERTEX;} void fragment(){vec2 q=abs(point-rect_size*0.5)-rect_size*0.5; float box=max(q.x,q.y); float corner=(q.x+q.y+cut)*0.70710678; float d=max(box,corner); COLOR.a*=1.0-smoothstep(-0.75,0.75,d);}"
	var material := ShaderMaterial.new()
	material.shader = _rounded_shader
	material.set_shader_parameter("rect_size",dimensions)
	material.set_shader_parameter("cut",cut)
	return material
