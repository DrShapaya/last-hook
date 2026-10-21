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

# Horizontal route topo: 0 m on the left, the summit flag on the right, zone
# ticks between, and markers for the personal record and the current height.
class RouteLine extends Control:
	var summit := 1200.0
	var zone := 200.0
	var record := -1.0
	var current := -1.0
	var font: Font
	var strong: Font
	var on_dark := false

	func x_of(meters: float) -> float:
		return 8+(size.x-30)*clampf(meters/maxf(1,summit),0,1)

	func _draw() -> void:
		var ink := STONE if on_dark else INK
		var soft := Color("c9d2d8") if on_dark else INK_SOFT
		var y := size.y-12
		var reached := maxf(current,0)
		# Unclimbed route is dotted, the climbed part is solid rope.
		var x := 8.0
		while x<size.x-22:
			draw_circle(Vector2(x,y),1.6,Color(soft,.55))
			x += 9
		var zone_count := int(summit/zone)
		for index in range(1,zone_count):
			var tick := x_of(index*zone)
			draw_line(Vector2(tick,y-5),Vector2(tick,y+5),Color(soft,.6),1.5,true)
		if reached>0:
			draw_line(Vector2(8,y),Vector2(x_of(reached),y),ROPE,4,true)
		draw_circle(Vector2(8,y),4,ink)
		var peak := Vector2(size.x-14,y)
		draw_line(peak+Vector2(0,4),peak+Vector2(0,-22),ink,2,true)
		draw_colored_polygon(PackedVector2Array([peak+Vector2(1,-22),peak+Vector2(14,-17),peak+Vector2(1,-12)]),HOLD)
		var labels: Array[Rect2] = []
		if current>=0:
			var at := Vector2(x_of(current),y)
			draw_circle(at,7,ink)
			draw_circle(at,4,HOLD)
			labels.append(label("%d м" % roundi(current),at.x,strong,ink,16))
		if record>0 and (current<0 or absf(x_of(record)-x_of(current))>36):
			var at := x_of(record)
			draw_colored_polygon(PackedVector2Array([Vector2(at-6,y-12),Vector2(at+6,y-12),Vector2(at,y-3)]),ink)
			var rect := label_rect("Рекорд %d м" % roundi(record),at,font,13)
			var free := true
			for other in labels: free = free and not other.grow(4).intersects(rect)
			if free: label("Рекорд %d м" % roundi(record),at,font,soft,13)
		var summit_text := "%d м" % roundi(summit)
		var summit_rect := label_rect(summit_text,size.x-8-text_width(summit_text,font,13)*.5,font,13)
		var summit_free := true
		for other in labels: summit_free = summit_free and not other.grow(4).intersects(summit_rect)
		if summit_free and (record<=0 or x_of(record)<size.x-130):
			draw_string(font,Vector2(size.x-32-text_width(summit_text,font,13),y-10),summit_text,HORIZONTAL_ALIGNMENT_LEFT,-1,13,soft)

	func text_width(value: String, use: Font, font_size: int) -> float:
		return (use if use!=null else ThemeDB.fallback_font).get_string_size(value,HORIZONTAL_ALIGNMENT_LEFT,-1,font_size).x

	func label_rect(value: String, center: float, use: Font, font_size: int) -> Rect2:
		var width := text_width(value,use,font_size)
		var left := clampf(center-width*.5,0,size.x-30-width)
		return Rect2(left,size.y-12-30,width,18)

	func label(value: String, center: float, use: Font, color: Color, font_size: int) -> Rect2:
		var rect := label_rect(value,center,use,font_size)
		draw_string(use if use!=null else ThemeDB.fallback_font,Vector2(rect.position.x,rect.position.y+14),value,HORIZONTAL_ALIGNMENT_LEFT,-1,font_size,color)
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

func route(parent: Node, at: Vector2, width: float, current: float = -1.0, on_dark: bool = false) -> RouteLine:
	var line := RouteLine.new()
	line.position = at
	line.size = Vector2(width,46)
	line.summit = game.summit_height*10
	line.zone = float(model.balance["zone_units"])*10
	line.record = float(model.profile["best"])
	line.current = current
	line.font = hud.body_font
	line.strong = hud.heading_font
	line.on_dark = on_dark
	line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(line)
	return line

# Segmented control: a recessed track, the chosen segment raised in slate.
func segmented(parent: Node, at: Vector2, width: float, options: Array, selected: int, callback: Callable, height: float = 46) -> Array[Button]:
	var buttons: Array[Button] = []
	slab(parent,at,Vector2(width,height),STONE_SHADE,Color.TRANSPARENT,0)
	var inset := 4.0
	var each := (width-inset*2)/options.size()
	for index in range(options.size()):
		var button := action(parent,str(options[index]),at+Vector2(inset+index*each,inset),Vector2(each,height-inset*2),callback.bind(index),"selected" if index==selected else "ghost")
		button.add_theme_font_size_override("font_size",15)
		for state_name in ["normal","hover","pressed","disabled"]:
			var styled := button.get_theme_stylebox(state_name).duplicate() as StyleBoxFlat
			styled.content_margin_left = 6
			styled.content_margin_right = 6
			button.add_theme_stylebox_override(state_name,styled)
		buttons.append(button)
	return buttons

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

# Clips a drawn control to the same chamfered silhouette as the slabs.
func rounded_material(dimensions: Vector2, cut: float = 14) -> ShaderMaterial:
	var shader := Shader.new()
	shader.code = "shader_type canvas_item; uniform vec2 rect_size; uniform float cut; varying vec2 point; void vertex(){point=VERTEX;} void fragment(){vec2 q=abs(point-rect_size*0.5)-rect_size*0.5; float box=max(q.x,q.y); float corner=(q.x+q.y+cut)*0.70710678; float d=max(box,corner); COLOR.a*=1.0-smoothstep(-0.75,0.75,d);}"
	var material := ShaderMaterial.new()
	material.shader = shader
	material.set_shader_parameter("rect_size",dimensions)
	material.set_shader_parameter("cut",cut)
	return material
