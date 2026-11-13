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

	const THICK := 10.0
	const BADGE := 12.0

	func x_of(meters: float) -> float:
		return track_left()+(trail_end()-track_left())*clampf(meters/maxf(1,summit),0,1)

	func track_left() -> float:
		return 10.0

	# The track ends where it runs into the summit badge.
	func trail_end() -> float:
		return size.x-BADGE*2-6

	func peak() -> Vector2:
		return Vector2(size.x-BADGE-2,track_y())

	func _draw() -> void:
		var soft := Color("c9d2d8") if on_dark else MenuSurface.INK_SOFT
		var y := track_y()
		var marks: Array = []
		var zone_count := int(summit/maxf(1,zone))
		for index in range(1,zone_count): marks.append(index*zone/maxf(1,summit))
		PlayGauges.draw_track(self,track_left(),trail_end(),y,progress/maxf(1,summit),marks,THICK,on_dark)
		PlayGauges.draw_summit(self,peak(),BADGE,1.0 if progress>=summit-.5 else 0.0)
		var taken: Array[Rect2] = []
		if current>=0:
			var at := Vector2(x_of(current),y)
			PlayGauges.draw_head(self,at+Vector2(0,-THICK*.5+1),1.15)
			taken.append(tag("%d м" % roundi(current),at.x,strong,MenuSurface.HOLD,MenuSurface.INK,15,-18))
		# The record: a gold crown standing on the track where it was set.
		if record>0:
			var crown_at := x_of(record)
			if current<0 or absf(crown_at-x_of(current))>14: PlayGauges.draw_crown(self,Vector2(crown_at,y-THICK*.5+1),.95)
			var top_y := -18.0 if current>=0 else 0.0
			var rect := tag_rect("Рекорд %d м" % roundi(record),crown_at,font,13,top_y)
			var free := true
			for other in taken: free = free and not other.grow(4).intersects(rect)
			if free: tag("Рекорд %d м" % roundi(record),crown_at,font,Color(SLATE,.9) if not on_dark else Color(STONE,.92),STONE if not on_dark else MenuSurface.INK,13,top_y)
		var use := font if font!=null else ThemeDB.fallback_font
		if not caption.is_empty():
			draw_string(use,Vector2(track_left()-4,y+28),caption,HORIZONTAL_ALIGNMENT_LEFT,size.x*.6,13,soft)
		# Under the badge, clear of it.
		var summit_text := "%d м" % roundi(summit)
		draw_string(use,Vector2(size.x-2-text_width(summit_text,use,13),y+BADGE+16),summit_text,HORIZONTAL_ALIGNMENT_LEFT,-1,13,soft)

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

	func tag_rect(value: String, center: float, use: Font, font_size: int, top: float = 0.0) -> Rect2:
		var width := text_width(value,use,font_size)+16
		var left := clampf(center-width*.5,0,size.x-width)
		return Rect2(left,top,width,22)

	# A small chamfered tag above the path with a notch pointing at its spot.
	func tag(value: String, center: float, use: Font, face: Color, color: Color, font_size: int, top: float = 0.0) -> Rect2:
		var rect := tag_rect(value,center,use,font_size,top)
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
	const LABEL_WIDTH := 66.0
	const HEIGHT := 44.0
	const KNOB := Vector2(32,32)
	const GROOVE := 12.0
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
	# 0 at rest, 1 held: the knob grows a little and a ring of light opens
	# round it.
	var held := 0.0:
		set(amount):
			held = amount
			queue_redraw()
	var held_tween: Tween

	func _ready() -> void:
		add_to_group("menu_slider")
		mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		# Keys and a controller reach it; a touch never leaves it focused.
		focus_mode = Control.FOCUS_ALL

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

	func _hold(on: bool) -> void:
		if held_tween!=null and held_tween.is_valid(): held_tween.kill()
		held_tween = create_tween()
		held_tween.tween_property(self,"held",1.0 if on else 0.0,MenuSurface.PRESS if on else MenuSurface.RELEASE).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)

	# Left and right step the value (a tenth of the range at least for coarse
	# steps), held keys repeat.
	func _step_by(direction: int) -> void:
		var amount := maxf(step,(maximum-minimum)/20.0)
		amount = maxf(step,snappedf(amount,step))
		var next := clampf(value+direction*amount,minimum,maximum)
		if is_equal_approx(next,value): return
		value = next
		queue_redraw()
		changed.emit(value)
		committed.emit(value)

	func _gui_input(event: InputEvent) -> void:
		if has_focus() and (event is InputEventKey or event is InputEventJoypadButton or event is InputEventJoypadMotion):
			if event.is_action_pressed("ui_left",true): _step_by(-1)
			elif event.is_action_pressed("ui_right",true): _step_by(1)
			else: return
			accept_event()
			return
		var pressing: bool = (event is InputEventMouseButton and event.button_index==MOUSE_BUTTON_LEFT) or event is InputEventScreenTouch
		if pressing and event.pressed:
			armed = true
			press_at = event.position
			if has_focus(): release_focus()
			_hold(true)
			accept_event()
		elif pressing and armed:
			if not dragging: _set_from(event.position.x)
			armed = false
			dragging = false
			_hold(false)
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

	func _notification(what: int) -> void:
		if what in [NOTIFICATION_FOCUS_ENTER,NOTIFICATION_FOCUS_EXIT]: queue_redraw()
		# A press that became a page scroll lets go of the knob.
		if what==NOTIFICATION_MOUSE_EXIT and armed and not dragging:
			armed = false
			_hold(false)

	func _draw() -> void:
		var y := size.y*.5
		var left := track_left()
		var right := left+track_width()
		PlayGauges.draw_track(self,left,right,y,ratio(),[],GROOVE)
		var at := Vector2(left+track_width()*ratio(),y)
		var r := KNOB.x*.5+held*2.0
		# Focus (keys, controller): a dark ring round the knob.
		if has_focus(): draw_arc(at,r+5,0,TAU,40,MenuSurface.INK,2.0,true)
		if held>0.0: draw_circle(at,r+7*held,Color(MenuSurface.HOLD,.28*held),true,-1.0,true)
		# A raised slate puck: its shadow, the lip, the face, a lit top edge
		# and a hold-gold stud. It sinks a little while held.
		draw_circle(at+Vector2(0,3.0-held*1.5),r,Color(0,0,0,.22),true,-1.0,true)
		draw_circle(at,r,MenuSurface.SLATE_LIP,true,-1.0,true)
		draw_circle(at+Vector2(0,-1.5+held),r-1.5,MenuSurface.SLATE,true,-1.0,true)
		draw_arc(at+Vector2(0,-1.5+held),r-3.0,PI*1.12,PI*1.88,16,Color(MenuSurface.STONE,.28),1.6,true)
		draw_circle(at+Vector2(0,-1.5+held),4.0,MenuSurface.HOLD,true,-1.0,true)
		# The value on its own small plate.
		var use := font if font!=null else ThemeDB.fallback_font
		var shown: String = format.call(value) if format.is_valid() else str(roundi(value))
		var plate := Rect2(size.x-LABEL_WIDTH+8,y-15,LABEL_WIDTH-8,30)
		var box := StyleBoxFlat.new()
		box.bg_color = Color(MenuSurface.STONE_SHADE,.85)
		box.set_corner_radius_all(8)
		box.corner_detail = 1
		draw_style_box(box,plate)
		var width := use.get_string_size(shown,HORIZONTAL_ALIGNMENT_LEFT,-1,16).x
		draw_string(use,Vector2(plate.get_center().x-width*.5,y+6),shown,HORIZONTAL_ALIGNMENT_LEFT,-1,16,MenuSurface.INK)

# An on/off switch: a rounded groove, moss when on, and a round knob that
# slides across with a tick or a dash in it. It is a Button, so it takes taps,
# keys and a controller like every other action; `on` holds its state.
class Toggle extends Button:
	const SIZE := Vector2(76,44)
	const TRACK := Vector2(64,34)
	var on := false
	var knob := 0.0:
		set(amount):
			knob = amount
			queue_redraw()
	var knob_tween: Tween
	var held := false

	func _init() -> void:
		flat = true
		text = ""
		focus_mode = Control.FOCUS_ALL
		custom_minimum_size = SIZE
		size = SIZE
		mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		for state_name in ["normal","hover","pressed","disabled","focus","hover_pressed"]: add_theme_stylebox_override(state_name,StyleBoxEmpty.new())
		button_down.connect(func():
			held = true
			queue_redraw())
		button_up.connect(func():
			held = false
			queue_redraw())

	func set_on(value: bool, animate: bool = true, spring: bool = true) -> void:
		on = value
		set_meta("on",value)
		if knob_tween!=null and knob_tween.is_valid(): knob_tween.kill()
		if not animate or not is_inside_tree():
			knob = 1.0 if on else 0.0
			return
		knob_tween = create_tween()
		knob_tween.tween_property(self,"knob",1.0 if on else 0.0,MenuSurface.POP).set_trans(Tween.TRANS_BACK if spring else Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)

	func _draw() -> void:
		var y := size.y*.5
		var left := size.x-TRACK.x-2
		var r := TRACK.y*.5
		var off := Color("cfc6b0")
		var lit := MenuSurface.MOSS
		var face := off.lerp(lit,clampf(knob,0,1))
		PlayGauges.pill(self,left,left+TRACK.x,y+1.2,TRACK.y,Color(MenuSurface.STONE,.9))
		PlayGauges.pill(self,left,left+TRACK.x,y,TRACK.y,face)
		if has_focus(): draw_style_box(_ring(),Rect2(left-4,y-r-4,TRACK.x+8,TRACK.y+8))
		var knob_r := r-4.0+(1.0 if held else 0.0)
		var at := Vector2(lerpf(left+r,left+TRACK.x-r,knob),y)
		draw_circle(at+Vector2(0,2),knob_r,Color(0,0,0,.2),true,-1.0,true)
		draw_circle(at,knob_r,MenuSurface.STONE,true,-1.0,true)
		draw_arc(at,knob_r-1,PI*1.1,PI*1.9,16,Color(1,1,1,.7),1.6,true)
		# A tick when on, a dash when off: the state reads without colour.
		var ink := MenuSurface.MOSS if knob>.5 else MenuSurface.INK_FAINT
		if knob>.5:
			draw_polyline(PackedVector2Array([at+Vector2(-5,0),at+Vector2(-1.5,3.5),at+Vector2(5,-3.5)]),ink,2.4,true)
		else:
			draw_line(at+Vector2(-4.5,0),at+Vector2(4.5,0),ink,2.4,true)

	func _ring() -> StyleBoxFlat:
		var box := StyleBoxFlat.new()
		box.draw_center = false
		box.border_color = MenuSurface.INK
		box.set_border_width_all(2)
		box.set_corner_radius_all(int(TRACK.y*.5+4))
		box.anti_aliasing = true
		return box

var hud
var game
var model: GameModel
var landscape := false

# --- Motion ----------------------------------------------------------------------
# One set of timings for every screen: a press sinks in PRESS and comes back
# in RELEASE, screens and plates fade in FADE, things that travel (sheets,
# thumbs, pages) take SLIDE with a cubic ease-out, a small spring (a bump, a
# switch knob) takes POP, numbers count for COUNT. "Без вспышек"
# (reduce_effects) keeps the fades and drops the springs, rises and counts.
const PRESS := .08
const RELEASE := .16
const FADE := .18
const SLIDE := .24
const POP := .22
const COUNT := .6
const RISE := 14.0
const STAGGER := .035
# False for a screen built again in place (a resize, an ad that finished
# loading): it appears as it was, without playing its entrance twice.
var animated := true

func prepare(owner_hud, animate: bool = true) -> void:
	hud = owner_hud
	game = hud.game
	model = game.model
	landscape = hud.wide
	size = Vector2(1080,660) if landscape else Vector2(540,960)
	position = (hud.root.size-size)*.5
	mouse_filter = Control.MOUSE_FILTER_STOP
	animated = animate
	if not animate: return
	modulate.a = 0
	create_tween().tween_property(self,"modulate:a",1.0,FADE).set_trans(Tween.TRANS_SINE)

func lively() -> bool:
	return animated and not hud.effects_reduced()

# An entrance for a part of a screen: it fades in and rises into place after
# `delay`. It takes input from the first frame; only the look is late.
func reveal(node: Control, delay: float = 0.0, rise: float = RISE) -> void:
	if not lively(): return
	var rest := node.position.y
	node.modulate.a = 0.0
	node.position.y = rest+rise
	var tween := node.create_tween().set_parallel(true)
	tween.tween_property(node,"modulate:a",1.0,FADE).set_delay(delay).set_trans(Tween.TRANS_SINE)
	tween.tween_property(node,"position:y",rest,SLIDE).set_delay(delay).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)

# A number that counts up to its value. The label holds the final text unless
# the count really plays.
func count_up(node: Label, value: int, prefix: String = "+", delay: float = 0.0) -> void:
	node.text = prefix+str(value)
	if not lively() or value<=0: return
	node.text = prefix+"0"
	var tween := node.create_tween()
	tween.tween_method(func(shown: float): node.text = prefix+str(roundi(shown)),0.0,float(value),COUNT).set_delay(delay).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)

func slab(parent: Node, at: Vector2, dimensions: Vector2, face: Color = STONE, lip: Color = STONE_LIP, lip_size: int = 4) -> Panel:
	var node := Panel.new()
	node.position = at
	node.size = dimensions
	node.mouse_filter = Control.MOUSE_FILTER_IGNORE
	# Corners that do not fit tear the box: on some screen scales its edges
	# run off down the screen.
	var cut := mini(10,(int(minf(dimensions.x,dimensions.y))-lip_size)/2-2)
	node.add_theme_stylebox_override("panel",hud.slab_box(face,lip,lip_size,cut))
	parent.add_child(node)
	return node

# Kept for callers that think in terms of cards; every card is a stone slab.
func card(parent: Node, at: Vector2, dimensions: Vector2, face: Color = STONE, lip: Color = STONE_LIP, _radius: int = 10) -> Panel:
	return slab(parent,at,dimensions,face,lip)

func text(parent: Node, value: String, at: Vector2, dimensions: Vector2, font_size: int = 16, color: Color = INK, weight: String = "body") -> Label:
	var node: Label = hud.label(parent,value,font_size,color)
	node.position = at
	# Trimming first: otherwise the size below keeps the full text's width.
	node.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	node.size = dimensions
	if weight=="display": node.add_theme_font_override("font",hud.heading_font)
	elif weight=="strong": node.add_theme_font_override("font",hud.strong_font)
	return node

func title(parent: Node, value: String, at: Vector2, width: float, font_size: int = 34) -> Label:
	return fit_text(text(parent,value,at,Vector2(width,font_size*1.3),font_size,INK,"display"))

# The size a label's text is drawn at: the accessibility text scale applied.
func scaled(font_size: int) -> int:
	return roundi(font_size*hud.text_scale)

# A one-line label whose text would be cut (large text, a long name) is set a
# little smaller instead, down to `minimum` points; below that it is cut.
func fit_text(node: Label, minimum: int = 11) -> Label:
	var font := node.get_theme_font("font")
	var font_size := node.get_theme_font_size("font_size")
	var room := node.size.x-2
	while font_size>minimum and font.get_string_size(node.text,HORIZONTAL_ALIGNMENT_LEFT,-1,font_size).x>room: font_size -= 1
	node.add_theme_font_size_override("font_size",font_size)
	return node

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
	var node: Button = hud.button(parent,value,callback,tone=="primary",tone)
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
	# A climb lays its rope up to the height it reached.
	if current>0: line.animate_progress.call_deferred(current)
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
		button.begin_bulk_theme_override()
		button.add_theme_font_size_override("font_size",15)
		for state_name in ["normal","pressed","disabled"]: button.add_theme_stylebox_override(state_name,clear)
		button.add_theme_stylebox_override("hover",hover)
		button.end_bulk_theme_override()
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
		buttons[index].begin_bulk_theme_override()
		for color_name in ["font_color","font_hover_color","font_pressed_color","font_hover_pressed_color","font_focus_color"]:
			buttons[index].add_theme_color_override(color_name,ink if index==selected or color_name=="font_color" else INK)
		buttons[index].end_bulk_theme_override()

func _segment_pressed(buttons: Array[Button], thumb: Panel, index: int, callback: Callable, left: float, each: float) -> void:
	if not is_instance_valid(thumb) or int(thumb.get_meta("index",-1))==index: return
	# A disabled/locked segment may handle the tap itself and return false;
	# leave the selected thumb exactly where it was in that case.
	var result: Variant = callback.call(index)
	if result is bool and not result: return
	thumb.set_meta("index",index)
	thumb.visible = true
	# One glide at a time: a second tap takes the thumb on from where it is.
	var running: Variant = thumb.get_meta("glide") if thumb.has_meta("glide") else null
	if running is Tween and running.is_valid(): running.kill()
	var tween := thumb.create_tween()
	thumb.set_meta("glide",tween)
	tween.tween_property(thumb,"position:x",left+index*each,SLIDE).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
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
		tween.tween_property(badge,"rotation",0.0,POP).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	game.toast(message,1.8,"menu")

# `room` is the width kept for the number when it will change in place.
func coin_amount(parent: Node, value: int, at: Vector2, font_size: int = 17, color: Color = COIN, kind: int = 12, room: float = 0.0) -> Label:
	var icon := font_size+5
	symbol(parent,kind,at+Vector2(0,(font_size*1.35-icon)*.5),Vector2(icon,icon),color)
	# Measured at the size it is drawn: at large text the number was cut ("30"
	# for 300 on the wardrobe cards).
	var width: float = maxf(room,hud.heading_font.get_string_size(str(value),HORIZONTAL_ALIGNMENT_LEFT,-1,scaled(font_size)).x+4)
	return text(parent,str(value),at+Vector2(icon+5,0),Vector2(width,font_size*1.35),font_size,INK,"display")

# The wallet at the top of a screen. Its numbers are kept: refresh_wallet
# counts them to the profile's values after a purchase, so the header never
# has to be rebuilt (and never shows what the player had before).
const WALLET_KEYS := ["gold","diamonds"]
var wallet_labels := {}
var wallet_shown := {}
var wallet_tweens := {}

func wallet(at: Vector2) -> void:
	var coins := slab(self,at,Vector2(118,44))
	wallet_labels["gold"] = coin_amount(coins,int(model.profile["gold"]),Vector2(12,8),17,COIN,12,74)
	var gems := slab(self,at+Vector2(126,0),Vector2(82,44))
	wallet_labels["diamonds"] = coin_amount(gems,int(model.profile["diamonds"]),Vector2(10,8),17,CRYSTAL,13,40)
	for key in WALLET_KEYS: wallet_shown[key] = float(int(model.profile[key]))

func refresh_wallet() -> void:
	for key in WALLET_KEYS:
		var node: Label = wallet_labels.get(key)
		if not is_instance_valid(node): continue
		var target := float(int(model.profile[key]))
		var from := float(wallet_shown.get(key,target))
		var running: Tween = wallet_tweens.get(key)
		if running!=null and running.is_valid(): running.kill()
		wallet_shown[key] = target
		if is_equal_approx(from,target) or hud.effects_reduced() or not node.is_inside_tree():
			node.text = str(int(target))
			continue
		var tween := node.create_tween()
		wallet_tweens[key] = tween
		tween.tween_method(func(shown: float): node.text = str(roundi(shown)),from,target,COUNT).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
		hud.pulse(node.get_parent(),.05)

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
