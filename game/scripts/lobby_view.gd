class_name LobbyView
extends Control

var hud: GameHud
var game
var model: GameModel

class UpgradeMeter extends Control:
	var filled := 1
	var unlocked := 1
	var total := 6
	func _draw() -> void:
		var gap := 5.0
		var width := (size.x-gap*(total-1))/total
		for index in range(total):
			var owned := index<filled
			var available := index<unlocked
			var box := StyleBoxFlat.new()
			box.set_corner_radius_all(3)
			box.bg_color = Color("f7c857") if owned else Color("363528") if available else Color("192832")
			box.border_color = Color("ffe49a") if owned else Color("9e7d39") if available else Color("34444b")
			box.set_border_width_all(1)
			if owned:
				box.shadow_color = Color(1,.70,.18,.16)
				box.shadow_size = 3
			var rect := Rect2(index*(width+gap),1,width,size.y-2)
			draw_style_box(box,rect)
			if owned:
				draw_line(rect.position+Vector2(3,2),rect.position+Vector2(width-3,2),Color("fff0ba"),1,true)

class Backdrop extends Control:
	func _draw() -> void:
		for band in range(64):
			draw_rect(Rect2(0,size.y*band/64,size.x,size.y/64+1),Color("152f3b").lerp(Color("091821"),float(band)/63))
		for line in range(11):
			var points := PackedVector2Array()
			for index in range(31):
				points.append(Vector2(index*size.x/30,size.y*.48+line*43+sin(index*.25+line*.33)*32))
			draw_polyline(points,Color(.40,.65,.63,.045),1,true)
		draw_circle(Vector2(size.x*.87,85),180,Color(.63,.78,.65,.025))

func setup(owner_hud: GameHud) -> void:
	hud = owner_hud
	game = hud.game
	model = game.model
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	size = Vector2(1080,660) if hud.wide else Vector2(540,960)
	position = (hud.root.size-size)*.5
	build()

func card(at: Vector2, dimensions: Vector2) -> Panel:
	var node := Panel.new()
	node.position = at
	node.size = dimensions
	var box := hud.style(Color("17303b"),18,Color("34505a"))
	box.shadow_color = Color(0,.02,.03,.27)
	box.shadow_size = 5
	box.shadow_offset = Vector2(0,3)
	node.add_theme_stylebox_override("panel",box)
	add_child(node)
	return node

func text(parent: Node, value: String, at: Vector2, dimensions: Vector2, font_size: int, color: Color = GameHud.WHITE) -> Label:
	var node := hud.label(parent,value,font_size,color)
	node.position = at
	node.size = dimensions
	node.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	return node

func icon(parent: Node, kind: int, at: Vector2, dimensions: Vector2, color: Color = GameHud.GOLD) -> UiSymbol:
	var symbol := UiSymbol.new()
	symbol.kind = kind
	if kind==2: symbol.tip_count = model.level(2)
	symbol.tint = color
	symbol.position = at
	symbol.size = dimensions
	symbol.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(symbol)
	return symbol

func chip(parent: Node, at: Vector2, dimensions: Vector2, color: Color) -> Panel:
	var panel := Panel.new()
	panel.position = at
	panel.size = dimensions
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_theme_stylebox_override("panel",hud.style(Color(color,.10),10,Color(color,.2)))
	parent.add_child(panel)
	return panel

func skin_button(node: Button, gold: bool = false, selected: bool = false) -> void:
	for state in ["normal","hover","pressed","disabled"]:
		var color := Color("f3c76c") if gold else Color("223e48") if selected else Color("132a35")
		var edge := Color("ffe5a5") if gold else Color("ad9864") if selected else Color("36515c")
		if state=="hover": color = color.lightened(.08)
		if state=="pressed": color = color.darkened(.12)
		if state=="disabled":
			color = Color("152b35")
			edge = Color("29414b")
		var box := hud.style(color,12,edge)
		box.shadow_color = Color(.02,.08,.10,.3)
		box.shadow_size = 3
		box.shadow_offset = Vector2(0,2)
		box.content_margin_left = 12
		box.content_margin_right = 12
		box.content_margin_top = 3
		box.content_margin_bottom = 3
		node.add_theme_stylebox_override(state,box)
	node.add_theme_color_override("font_color",GameHud.INK if gold else GameHud.WHITE)
	node.add_theme_color_override("font_hover_color",GameHud.INK if gold else GameHud.WHITE)
	node.add_theme_color_override("font_pressed_color",GameHud.INK if gold else GameHud.WHITE)
	node.add_theme_color_override("font_disabled_color",Color("6c8892"))

func rounded_material(dimensions: Vector2) -> ShaderMaterial:
	var shader := Shader.new()
	shader.code = "shader_type canvas_item; uniform vec2 rect_size; varying vec2 point; void vertex(){point=VERTEX;} void fragment(){vec2 q=abs(point-rect_size*0.5)-(rect_size*0.5-vec2(14.0)); float d=length(max(q,vec2(0.0)))+min(max(q.x,q.y),0.0)-14.0; COLOR.a*=1.0-smoothstep(-1.0,1.0,d);}"
	var material := ShaderMaterial.new()
	material.shader = shader
	material.set_shader_parameter("rect_size",dimensions)
	return material

func build() -> void:
	chip(self,Vector2(24,22),Vector2(38,38),GameHud.GOLD)
	icon(self,6,Vector2(29,27),Vector2(28,28))
	text(self,"LAST HOOK",Vector2(74,18),Vector2(235,32),25)
	text(self,"ВЫШЕ С КАЖДЫМ БРОСКОМ",Vector2(75,52),Vector2(235,16),9,Color("93aaa9"))
	var gold := card(Vector2(316,24),Vector2(112,36))
	icon(gold,12,Vector2(9,8),Vector2(20,20))
	text(gold,str(int(model.profile["gold"])),Vector2(37,8),Vector2(68,22),14,GameHud.GOLD)
	var diamonds := card(Vector2(438,24),Vector2(78,36))
	icon(diamonds,13,Vector2(9,8),Vector2(20,20),Color("9bdde0"))
	text(diamonds,str(int(model.profile["diamonds"])),Vector2(37,8),Vector2(36,22),14,Color("b7e9e4"))
	build_level_card()
	var active: bool = not model.profile["active"].is_empty()
	for index in range(2):
		var mode := hud.button(self,"Вершина" if index==0 else "Бесконечно",func(): game.lobby_endless=index==1; hud.show_menu())
		mode.position = Vector2(24+index*251,312)
		mode.custom_minimum_size = Vector2(0,36)
		mode.size = Vector2(241,36)
		mode.add_theme_font_size_override("font_size",13)
		mode.disabled = active or (index==1 and not model.profile["summit_cleared"])
		skin_button(mode,false,game.lobby_endless==(index==1))
		mode.size = Vector2(241,36)
		icon(mode,7 if index==0 else 8,Vector2(16,7),Vector2(22,22),GameHud.GOLD if game.lobby_endless==(index==1) else Color("77979e"))
	var definition: Dictionary = model.balance["locations"][game.lobby_location]
	var owned: bool = model.profile["locations"].has(game.lobby_location)
	var action_text := "Продолжить восхождение" if active else "Начать восхождение" if owned else "После первой вершины" if not model.profile["summit_cleared"] else "Открыть · %d" % int(definition["price"])
	var action := hud.button(self,action_text,game.lobby_action,true)
	action.position = Vector2(24,360)
	action.size = Vector2(492,58)
	action.disabled = not active and not owned and not model.profile["summit_cleared"]
	action.add_theme_font_size_override("font_size",18)
	skin_button(action,true)
	icon(action,9,Vector2(22,17),Vector2(24,24),GameHud.INK)
	text(self,"Твоё оснащение",Vector2(24,438),Vector2(250,28),20)
	var gate := text(self,"После попытки" if active else model.next_goal(),Vector2(275,443),Vector2(241,22),11,Color("91adb3"))
	gate.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	var order := [GameModel.THROW,0,1,2,3,4,5]
	for index in range(order.size()):
		build_upgrade(order[index],Vector2(24+(index%2)*251,476+(index/2)*110),active)
	var tip := card(Vector2(275,806),Vector2(241,102))
	text(tip,"ОДИН ШАНС НА ЗАЦЕП",Vector2(14,11),Vector2(213,19),11,GameHud.GOLD)
	var explanation := text(tip,"Большинство опор исчезнет.\nЗолотые крепления — навсегда.\nСила — скорость. Канат — длина.",Vector2(14,36),Vector2(213,58),12,Color("b7cdcf"))
	explanation.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	text(self,"Первый — раскачка · второй — канат и отпускание" if OS.has_feature("mobile") else "A / D — раскачка · W / S — канат · пробел — отпустить",Vector2(24,932),Vector2(492,20),11,Color("76939d")).horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	if hud.wide:
		# Main expedition controls on the left, equipment on the right.
		for node in get_children():
			if node.position.y==24 and node.position.x>=316:
				node.position.x += 552
			elif node.position.y in [438.0,443.0] and node is Label:
				node.position += Vector2(528,-356)
			elif node.position.y>=476 and node.position.y<=806:
				if node==tip:
					node.position = Vector2(24,438)
					node.size = Vector2(492,142)
					explanation.size = Vector2(456,85)
					explanation.add_theme_font_size_override("font_size",16)
				else:
					node.position += Vector2(528,-356)
			elif node.position.y==932:
				node.position.y = 622
				node.size.x = 1032

func build_level_card() -> void:
	var definition: Dictionary = model.balance["locations"][game.lobby_location]
	var frame := card(Vector2(24,82),Vector2(492,218))
	frame.clip_contents = true
	var preview := LevelPreview.new()
	preview.world = game.world
	preview.position = Vector2(4,4)
	preview.size = Vector2(484,210)
	preview.material = rounded_material(preview.size)
	preview.mouse_filter = Control.MOUSE_FILTER_IGNORE
	frame.add_child(preview)
	var shade := TextureRect.new()
	var gradient := Gradient.new()
	gradient.colors = PackedColorArray([Color(0,0,0,.02),Color(.035,.09,.12,.98)])
	gradient.offsets = PackedFloat32Array([.24,1])
	var texture := GradientTexture2D.new()
	texture.gradient = gradient
	texture.fill_from = Vector2(0,0)
	texture.fill_to = Vector2(0,1)
	shade.texture = texture
	shade.position = Vector2(4,4)
	shade.size = Vector2(484,210)
	shade.material = rounded_material(shade.size)
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	frame.add_child(shade)
	text(frame,"ЭКСПЕДИЦИЯ  %02d" % (game.lobby_location+1),Vector2(20,15),Vector2(330,22),11,Color("f5d89c"))
	text(frame,"%d м" % (int(definition["height_units"])*10),Vector2(350,15),Vector2(120,22),12,GameHud.WHITE).horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	text(frame,str(definition["name"]),Vector2(20,140),Vector2(450,36),27)
	var owned: bool = model.profile["locations"].has(game.lobby_location)
	text(frame,"Рекорд · %d м" % int(model.profile["best"]) if owned else "Новая высота ждёт",Vector2(21,182),Vector2(440,22),12,Color("b3ccc9"))
	for direction in [-1,1]:
		var arrow := hud.button(frame,"",game.cycle_location.bind(direction))
		arrow.position = Vector2(14 if direction<0 else 438,68)
		arrow.custom_minimum_size = Vector2(40,44)
		arrow.size = Vector2(40,44)
		arrow.disabled = not model.profile["active"].is_empty()
		skin_button(arrow)
		arrow.size = Vector2(40,44)
		icon(arrow,10 if direction<0 else 11,Vector2(8,10),Vector2(24,24),Color("d4e5df"))

func build_upgrade(kind: int, at: Vector2, active: bool) -> void:
	var frame := card(at,Vector2(241,102))
	frame.tooltip_text = model.upgrade_text(kind)+( "\nДалее: "+model.upgrade_text(kind,model.level(kind)+1) if model.level(kind)<model.max_level(kind) else "\nМаксимальное улучшение")
	if game.preview: frame.tooltip_text = ""
	var accent: Color = [Color("eaca83"),Color("f4bc7c"),Color("a5d3cc"),Color("b8cc9c"),Color("a0c4e2"),Color("c4b4dd"),Color("f3ce83")][kind]
	chip(frame,Vector2(12,10),Vector2(34,34),accent)
	icon(frame,kind,Vector2(16,14),Vector2(26,26),accent)
	text(frame,GameModel.UPGRADE_NAMES[kind],Vector2(56,9),Vector2(172,20),13)
	var effect := ""
	match kind:
		0: effect = "%d м каната" % int(model.value("rope_lengths",0)*10)
		1: effect = "+%d%% к импульсу" % roundi((model.value("impulse_factors",1)-1)*100)
		2: effect = "%d шт. · %s" % [model.level(2),["точный","широкий","макс. зацеп"][model.level(2)-1]]
		3: effect = "%d ячейки" % model.level(3)
		4: effect = "Касание" if model.level(4)==1 else "%d м притяжения" % int(model.value("magnet_radii",4)*10)
		5: effect = "%d%% сохранится" % int(model.value("recovery_percents",5))
		6: effect = "%d м/с" % roundi(model.value("throw_speeds",GameModel.THROW)*10)
	text(frame,effect,Vector2(56,30),Vector2(172,20),14,accent)
	var meter := UpgradeMeter.new()
	meter.filled = model.level(kind)
	meter.total = model.max_level(kind)
	meter.unlocked = 3 if kind==2 else model.unlocked_upgrade_level()
	meter.position = Vector2(14,53)
	meter.size = Vector2(213,9)
	meter.mouse_filter = Control.MOUSE_FILTER_IGNORE
	frame.add_child(meter)
	var locked := kind!=2 and model.level(kind)+1>model.unlocked_upgrade_level()
	var can_buy: bool = not active and model.upgrade_available(kind) and int(model.profile["gold"])>=model.cost(kind)
	var action_text := "Максимум" if model.level(kind)>=model.max_level(kind) else "Откроется в зоне %d" % (model.level(kind)+1) if locked else "Улучшить · %d" % model.cost(kind)
	var purchase := hud.button(frame,action_text,hud._buy_upgrade.bind(kind),can_buy)
	purchase.position = Vector2(14,69)
	purchase.custom_minimum_size = Vector2(213,25)
	purchase.size = Vector2(213,25)
	purchase.add_theme_font_size_override("font_size",12)
	skin_button(purchase,can_buy)
	purchase.size = Vector2(213,27)
	purchase.disabled = not can_buy
