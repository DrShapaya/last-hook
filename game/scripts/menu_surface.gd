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
# Colours the accessibility settings repaint; see apply_palette.
static var INK := Color("1f2b35")
static var INK_SOFT := Color("55636d")
static var INK_FAINT := Color("8b959b")
const SLATE := Color("24323d")
const SLATE_LIP := Color("121b22")
static var HOLD := Color("f6c32f")
const HOLD_LIP := Color("b88a12")
const ROPE := Color("b5712b")
static var COIN := Color("c98612")
const COIN_LIGHT := Color("ffd15c")
const CRYSTAL := Color("2f7fd6")
const CRYSTAL_LIGHT := Color("9fd6ff")
static var MOSS := Color("4a9a52")
static var DANGER := Color("cc4b37")
static var LOOT_COLORS: Array = [Color("e4b35e"),Color("f08f72"),Color("86c6a0"),Color("78d5d2"),Color("af9bdf"),Color("d7dcea")]
# Schemes for colour vision: red and green move to orange and blue, blue and
# yellow move to pink and teal.
const SCHEMES := {
	"normal":{"moss":Color("4a9a52"),"danger":Color("cc4b37"),"hold":Color("f6c32f"),"coin":Color("c98612"),
		"rarity":[Color("e0a83a"),Color("e8833a"),Color("e9bf4f"),Color("6fc6e8"),Color("a98fdc"),Color("f3d478")]},
	"red_green":{"moss":Color("2f7fd6"),"danger":Color("b8520a"),"hold":Color("f6c32f"),"coin":Color("c98612"),
		"rarity":[Color("e3b23c"),Color("d55e00"),Color("f0e442"),Color("56b4e9"),Color("cc79a7"),Color("f3f0e0")]},
	"blue_yellow":{"moss":Color("1f9d84"),"danger":Color("c43a5e"),"hold":Color("f58f7a"),"coin":Color("c4553f"),
		"rarity":[Color("e07a7a"),Color("d55e00"),Color("f2a2c0"),Color("35c0b0"),Color("b0409a"),Color("f3f0e0")]}
}

static func apply_palette(scheme: String, high_contrast: bool) -> void:
	var colors: Dictionary = SCHEMES.get(scheme,SCHEMES["normal"])
	MOSS = colors["moss"]
	DANGER = colors["danger"]
	HOLD = colors["hold"]
	COIN = colors["coin"]
	ItemCatalog.rarity_colors = colors["rarity"]
	INK = Color("0b1217") if high_contrast else Color("1f2b35")
	INK_SOFT = Color("2a333b") if high_contrast else Color("55636d")
	INK_FAINT = Color("46525b") if high_contrast else Color("8b959b")

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
		var ink := STONE if on_dark else MenuSurface.INK
		var soft := Color("c9d2d8") if on_dark else MenuSurface.INK_SOFT
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
		draw_circle(Vector2(left,y),2,MenuSurface.HOLD)
		# Summit flag at the end of the path.
		var peak := Vector2(size.x-16,y)
		draw_colored_polygon(PackedVector2Array([peak+Vector2(-9,4),peak+Vector2(0,-6),peak+Vector2(9,4)]),Color(ink,.85))
		draw_line(peak+Vector2(0,-4),peak+Vector2(0,-27),ink,2,true)
		draw_colored_polygon(PackedVector2Array([peak+Vector2(1,-27),peak+Vector2(15,-23),peak+Vector2(13,-19),peak+Vector2(1,-16)]),MenuSurface.HOLD)
		var taken: Array[Rect2] = []
		if current>=0:
			var at := Vector2(x_of(current),y)
			draw_circle(at,8,ink)
			draw_circle(at,5,MenuSurface.HOLD)
			taken.append(tag("%d м" % roundi(current),at.x,strong,MenuSurface.HOLD,MenuSurface.INK,15))
		if record>0:
			var at := x_of(record)
			# The record is a hold: a little faceted pebble on the path.
			draw_colored_polygon(PackedVector2Array([Vector2(at-6,y+1),Vector2(at-3,y-5),Vector2(at+4,y-5),Vector2(at+6,y+1),Vector2(at+2,y+5),Vector2(at-4,y+5)]),HOLD_LIP)
			draw_colored_polygon(PackedVector2Array([Vector2(at-5,y),Vector2(at-2,y-4),Vector2(at+3,y-4),Vector2(at+5,y),Vector2(at+1,y+3),Vector2(at-3,y+3)]),MenuSurface.HOLD)
			var rect := tag_rect("Рекорд %d м" % roundi(record),at,font,13)
			var free := true
			for other in taken: free = free and not other.grow(4).intersects(rect)
			if free: tag("Рекорд %d м" % roundi(record),at,font,Color(SLATE,.9) if not on_dark else Color(STONE,.92),STONE if not on_dark else MenuSurface.INK,13)
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

# A value on a rope: a recessed groove, the rope laid in it up to the value and
# a raised slate knob, like the switches. The value is written at the right
# end. It takes taps and drags itself; LobbyView keeps menu swipes off it.
class RopeSlider extends Control:
	signal changed(value: float)
	signal committed(value: float)
	const LABEL_WIDTH := 62.0
	const HEIGHT := 44.0
	const KNOB := Vector2(30,38)
	const GROOVE := 20.0
	const SLOP := 10.0
	var value := 0.0
	var minimum := 0.0
	var maximum := 100.0
	var step := 1.0
	var format: Callable
	var font: Font
	var dragging := false
	# A touch may still become a page scroll: the value moves only on a tap or
	# once the finger has clearly gone sideways.
	var armed := false
	var press_at := Vector2.ZERO

	func _ready() -> void:
		add_to_group("menu_slider")
		mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND

	func track_left() -> float:
		return KNOB.x*.5

	func track_width() -> float:
		return maxf(1.0,size.x-LABEL_WIDTH-KNOB.x)

	func ratio() -> float:
		return clampf((value-minimum)/maxf(.0001,maximum-minimum),0,1)

	func _set_from(x: float) -> void:
		var next := clampf(minimum+(x-track_left())/track_width()*(maximum-minimum),minimum,maximum)
		next = clampf(minimum+snappedf(next-minimum,step),minimum,maximum)
		if is_equal_approx(next,value): return
		value = next
		queue_redraw()
		changed.emit(value)

	func _gui_input(event: InputEvent) -> void:
		var pressing: bool = (event is InputEventMouseButton and event.button_index==MOUSE_BUTTON_LEFT) or event is InputEventScreenTouch
		if pressing and event.pressed:
			armed = true
			press_at = event.position
			accept_event()
		elif pressing and armed:
			if not dragging: _set_from(event.position.x)
			armed = false
			dragging = false
			queue_redraw()
			committed.emit(value)
			accept_event()
		elif armed and (event is InputEventMouseMotion or event is InputEventScreenDrag):
			var travel: Vector2 = event.position-press_at
			if not dragging and absf(travel.x)>=SLOP and absf(travel.x)>absf(travel.y):
				dragging = true
				queue_redraw()
			if dragging: _set_from(event.position.x)
			accept_event()

	func _plate(rect: Rect2, face: Color, lip: Color, lip_size: int) -> void:
		var box := StyleBoxFlat.new()
		box.bg_color = face
		box.border_color = lip
		box.border_width_bottom = lip_size
		box.set_corner_radius_all(6)
		box.corner_detail = 1
		draw_style_box(box,rect)

	func _draw() -> void:
		var y := size.y*.5
		var left := track_left()
		var at := left+track_width()*ratio()
		var groove := Rect2(left-KNOB.x*.5,y-GROOVE*.5,track_width()+KNOB.x,GROOVE)
		_plate(groove,STONE_SHADE,Color.TRANSPARENT,0)
		# The rope lies in the groove up to the knob, its strands twisted.
		if at>groove.position.x+4:
			var rope_y := y
			draw_line(Vector2(groove.position.x+4,rope_y),Vector2(at,rope_y),Color("7a4a1c"),10)
			draw_line(Vector2(groove.position.x+4,rope_y-1),Vector2(at,rope_y-1),ROPE,7)
			var twist := groove.position.x+6
			while twist<at-4:
				draw_line(Vector2(twist,rope_y+3),Vector2(twist+4,rope_y-4),Color("e0a15a",.85),1.6,true)
				twist += 6
		# A raised block, the same as a switch knob. It sinks while held.
		var lift := 0.0 if dragging else -1.0
		var knob := Rect2(at-KNOB.x*.5,y-KNOB.y*.5+lift,KNOB.x,KNOB.y)
		_plate(knob,SLATE,SLATE_LIP,2 if dragging else 4)
		draw_rect(Rect2(at-2,knob.position.y+9,4,KNOB.y-20),MenuSurface.HOLD)
		var use := font if font!=null else ThemeDB.fallback_font
		var shown: String = format.call(value) if format.is_valid() else str(roundi(value))
		var width := use.get_string_size(shown,HORIZONTAL_ALIGNMENT_LEFT,-1,16).x
		draw_string(use,Vector2(size.x-width,y+6),shown,HORIZONTAL_ALIGNMENT_LEFT,-1,16,MenuSurface.INK)

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
	buttons[0].set_meta("thumb",thumb)
	buttons[0].set_meta("left",at.x+inset)
	buttons[0].set_meta("each",each)
	return buttons

# Moves the thumb from outside, when a choice changed for another reason.
func pick_segment(buttons: Array[Button], index: int) -> void:
	var thumb: Panel = buttons[0].get_meta("thumb")
	if int(thumb.get_meta("index",-1))==index: return
	thumb.set_meta("index",index)
	thumb.visible = index>=0
	thumb.position.x = float(buttons[0].get_meta("left"))+maxi(index,0)*float(buttons[0].get_meta("each"))
	paint_segments(buttons,index)

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

func slider(parent: Node, at: Vector2, width: float, value: float, minimum: float, maximum: float, step: float, format: Callable, callback: Callable) -> RopeSlider:
	var node := RopeSlider.new()
	node.position = at
	node.size = Vector2(width,RopeSlider.HEIGHT)
	node.minimum = minimum
	node.maximum = maximum
	node.step = step
	node.value = value
	node.format = format
	node.font = hud.strong_font
	node.changed.connect(callback)
	parent.add_child(node)
	return node

# One settings line: the name and a hint on the left. Returns the holder of the
# control on the right.
func settings_row(parent: Node, y: float, width: float, title_text: String, hint: String) -> Control:
	var control_x := width*.44
	text(parent,title_text,Vector2(20,y+(2 if not hint.is_empty() else 11)),Vector2(control_x-24,22),15,INK,"strong")
	if not hint.is_empty(): paragraph(parent,hint,Vector2(20,y+24),Vector2(control_x-24,18),12)
	var holder := Control.new()
	holder.position = Vector2(control_x,y)
	holder.size = Vector2(width-control_x-20,44)
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(holder)
	return holder

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
