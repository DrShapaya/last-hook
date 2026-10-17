class_name MenuSurface
extends Control

# Shared visual vocabulary for the expedition screens. All coordinates are
# authored in the same portrait / landscape canvas, then scaled by GameHud.
const PAPER := Color("f3eddb")
const GOLD := Color("efc779")
const TEAL := Color("96c6b6")
const MUTED := Color("9aada8")
const PANEL := Color("152c2d")
const EDGE := Color("334b45")
const LOOT_COLORS := [Color("dfaf6c"),Color("e6a170"),Color("9dc3a1"),Color("9dd3df"),Color("b5a1ce"),Color("e1dac0")]

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
	create_tween().tween_property(self,"modulate:a",1.0,.22).set_trans(Tween.TRANS_SINE)

func card(parent: Node, at: Vector2, dimensions: Vector2, color: Color = PANEL, border: Color = EDGE, radius: int = 20) -> Panel:
	var node := Panel.new()
	node.position = at
	node.size = dimensions
	node.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var box = hud.style(color,radius,border)
	box.shadow_color = Color(0,.02,.015,.18)
	box.shadow_size = 10
	box.shadow_offset = Vector2(0,5)
	node.add_theme_stylebox_override("panel",box)
	parent.add_child(node)
	return node

func text(parent: Node, value: String, at: Vector2, dimensions: Vector2, font_size: int = 16, color: Color = PAPER, bold: bool = false) -> Label:
	var node: Label = hud.label(parent,value,font_size,color)
	node.position = at
	node.size = dimensions
	node.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	if bold: node.add_theme_font_override("font",hud.heading_font)
	return node

func paragraph(parent: Node, value: String, at: Vector2, dimensions: Vector2, font_size: int = 15, color: Color = MUTED) -> Label:
	var node := text(parent,value,at,dimensions,font_size,color)
	node.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	node.size = dimensions
	return node

func eyebrow(parent: Node, value: String, at: Vector2, width: float = 440, color: Color = GOLD) -> Label:
	return text(parent,value,at,Vector2(width,20),11,color,true)

func symbol(parent: Node, kind: int, at: Vector2, dimensions: Vector2 = Vector2(28,28), color: Color = GOLD) -> UiSymbol:
	var node := UiSymbol.new()
	node.kind = kind
	node.tint = color
	node.tip_count = model.level(2)
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

func rule(parent: Node, at: Vector2, width: float) -> void:
	var line := ColorRect.new()
	line.color = Color("33483f")
	line.position = at
	line.size = Vector2(width,1)
	line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(line)

func stat(parent: Node, value: String, caption: String, at: Vector2, dimensions: Vector2, kind: int = -1) -> void:
	var tile := card(parent,at,dimensions,Color("102625"),Color("2b423a"),14)
	var inset := 16.0
	if kind>=0:
		symbol(tile,kind,Vector2(14,18),Vector2(24,24),TEAL)
		inset = 48
	text(tile,value,Vector2(inset,12),Vector2(dimensions.x-inset-10,30),23,PAPER,true)
	text(tile,caption,Vector2(inset,45),Vector2(dimensions.x-inset-10,20),11,MUTED)

func wallet(at: Vector2) -> void:
	var coins := card(self,at,Vector2(114,42),Color("1c302a"),Color("4a5038"),13)
	symbol(coins,12,Vector2(10,10),Vector2(22,22))
	text(coins,str(int(model.profile["gold"])),Vector2(39,10),Vector2(68,24),15,GOLD,true)
	var gems := card(self,at+Vector2(124,0),Vector2(84,42),Color("152e2b"),Color("34564b"),13)
	symbol(gems,13,Vector2(9,10),Vector2(22,22),TEAL)
	text(gems,str(int(model.profile["diamonds"])),Vector2(37,10),Vector2(42,24),15,TEAL,true)

func emblem(parent: Node, kind: int, at: Vector2, color: Color = GOLD) -> void:
	var tile := card(parent,at,Vector2(58,58),Color(color,.08),Color(color,.22),20)
	symbol(tile,kind,Vector2(12,12),Vector2(34,34),color)

func time_string(seconds: float) -> String:
	var total := int(seconds)
	return "%d:%02d" % [total/60,total%60]

func rounded_material(dimensions: Vector2, radius: float = 23) -> ShaderMaterial:
	var shader := Shader.new()
	shader.code = "shader_type canvas_item; uniform vec2 rect_size; uniform float radius; varying vec2 point; void vertex(){point=VERTEX;} void fragment(){vec2 q=abs(point-rect_size*0.5)-(rect_size*0.5-vec2(radius)); float d=length(max(q,vec2(0.0)))+min(max(q.x,q.y),0.0)-radius; COLOR.a*=1.0-smoothstep(-1.0,1.0,d);}"
	var material := ShaderMaterial.new()
	material.shader = shader
	material.set_shader_parameter("rect_size",dimensions)
	material.set_shader_parameter("radius",radius)
	return material
