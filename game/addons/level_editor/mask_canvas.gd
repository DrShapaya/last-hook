@tool
extends Control

# The painting surface of the level editor. Level space is mask pixels
# (LevelSource.PX_PER_UNIT per world unit, top row = top of the level); the
# view holds the preview, one tinted TextureRect per layer and an overlay for
# objects, pins, act lines and the brush, and is moved and scaled for pan and
# zoom.
#
# Mouse: wheel zooms round the pointer, middle or right drag pans, left
# paints with the active tool. Ctrl+Z / Ctrl+Y undo and redo strokes.

signal changed
signal hovered(world: Vector2)

const TINT_SHADER := preload("res://addons/level_editor/mask_tint.gdshader")
const MAX_UNDO := 40

var source: LevelSource
var tool := "brush"           # brush, eraser, pin
var active_layer := "route"
var brush_radius := 1.5        # world units
var brush_hardness := .6
var brush_strength := 1.0
var pin_type := "stone"
var layer_opacity := .6
# Objects of the current layout drawn over the masks: Dictionary from
# LevelBake.layout_data (anchors, finds, ledges, main_route), may be empty.
var layout: Dictionary = {}
var show_objects := true

var view := Control.new()
var preview := TextureRect.new()
var overlay := Overlay.new()
var layer_rects: Dictionary = {}
var textures: Dictionary = {}
var undo_stack: Array = []
var redo_stack: Array = []
var stroke_before: Image
var painting := false
var panning := false
var last_paint := Vector2.INF
var pointer := Vector2.INF

func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO,size),Color("1f2329"))
	if source!=null:
		var rect := Rect2(view.position,Vector2(source.size())*view.scale.x)
		draw_rect(rect,Color("5f8fbf"))
		draw_rect(rect.grow(1),Color(1,1,1,.25),false,1.0)

func _init() -> void:
	clip_contents = true
	focus_mode = Control.FOCUS_ALL
	mouse_filter = Control.MOUSE_FILTER_STOP
	view.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(view)
	preview.mouse_filter = Control.MOUSE_FILTER_IGNORE
	preview.stretch_mode = TextureRect.STRETCH_SCALE
	preview.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	preview.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	view.add_child(preview)
	overlay.canvas = self
	overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	view.add_child(overlay)

func set_source(level: LevelSource) -> void:
	source = level
	undo_stack.clear()
	redo_stack.clear()
	for rect in layer_rects.values(): rect.queue_free()
	layer_rects.clear()
	textures.clear()
	if source==null: return
	var dimensions := Vector2(source.size())
	view.size = dimensions
	preview.size = dimensions
	overlay.size = dimensions
	for layer in source.masks: _ensure_layer(layer)
	fit()

func set_preview(texture: Texture2D) -> void:
	preview.texture = texture

# The level fills the height of the canvas, centred.
func fit() -> void:
	if source==null or size.y<1: return
	var dimensions := Vector2(source.size())
	var scale_value := size.y/dimensions.y*.98
	view.scale = Vector2.ONE*scale_value
	view.position = (size-dimensions*scale_value)*.5
	queue_redraw()
	overlay.queue_redraw()

func layer_color(layer: String) -> Color:
	if layer.begins_with("zone_"): return Color("b04ad0")
	return {"silhouette":Color("c9c4b8"),"depth":Color("3b3a40"),"solid":Color("e0402f"),"route":Color("2f63f0"),
		"branch":Color("33d6e6"),"rest":Color("3dc858"),"difficulty":Color("f08a2c"),"loot":Color("f6c637"),
		"moss":Color("5d9e3a"),"snow":Color("ffffff"),"cracks":Color("1d1b1a"),"dust":Color("c9a26b"),"decor":Color("a5e05a")}.get(layer,Color.WHITE)

func set_layer_visible(layer: String, on: bool) -> void:
	_ensure_layer(layer)
	layer_rects[layer].visible = on

func layer_visible(layer: String) -> bool:
	return layer_rects.has(layer) and layer_rects[layer].visible

func set_opacity(value: float) -> void:
	layer_opacity = value
	for layer in layer_rects:
		(layer_rects[layer].material as ShaderMaterial).set_shader_parameter("opacity",value*(.55 if layer=="silhouette" else 1.0))

# Creates the layer's mask when missing; layers keep a fixed stacking order.
func _ensure_layer(layer: String) -> void:
	if source==null: return
	if not source.masks.has(layer): source.masks[layer] = source.new_mask()
	if layer_rects.has(layer): return
	var texture := ImageTexture.create_from_image(source.masks[layer])
	textures[layer] = texture
	var rect := TextureRect.new()
	rect.texture = texture
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rect.stretch_mode = TextureRect.STRETCH_SCALE
	rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	rect.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	rect.size = Vector2(source.size())
	var material := ShaderMaterial.new()
	material.shader = TINT_SHADER
	material.set_shader_parameter("tint",layer_color(layer))
	material.set_shader_parameter("opacity",layer_opacity*(.55 if layer=="silhouette" else 1.0))
	rect.material = material
	view.add_child(rect)
	layer_rects[layer] = rect
	# Order: preview, then layers by name order of LevelSource.LAYERS, zones,
	# then the overlay on top.
	var order := LevelSource.LAYERS.keys()
	var children := layer_rects.keys()
	children.sort_custom(func(a: String, b: String) -> bool:
		var ia := order.find(a) if order.has(a) else 100+a.length()
		var ib := order.find(b) if order.has(b) else 100+b.length()
		return ia<ib if ia!=ib else a<b)
	for index in range(children.size()): view.move_child(layer_rects[children[index]],index+1)
	view.move_child(overlay,-1)

func remove_layer(layer: String) -> void:
	if layer_rects.has(layer):
		layer_rects[layer].queue_free()
		layer_rects.erase(layer)
	textures.erase(layer)
	if source!=null: source.masks.erase(layer)

func refresh_layer(layer: String) -> void:
	if textures.has(layer): (textures[layer] as ImageTexture).update(source.masks[layer])

func to_level(local: Vector2) -> Vector2:
	return (local-view.position)/view.scale.x

func to_world(local: Vector2) -> Vector2:
	return source.to_world(to_level(local)) if source!=null else Vector2.ZERO

func _gui_input(event: InputEvent) -> void:
	if source==null: return
	if event is InputEventMouseButton:
		var button := event as InputEventMouseButton
		if button.pressed and button.button_index in [MOUSE_BUTTON_WHEEL_UP,MOUSE_BUTTON_WHEEL_DOWN]:
			var factor := 1.15 if button.button_index==MOUSE_BUTTON_WHEEL_UP else 1.0/1.15
			var anchor := to_level(button.position)
			view.scale = Vector2.ONE*clampf(view.scale.x*factor,.2,12.0)
			view.position = button.position-anchor*view.scale.x
			queue_redraw()
			overlay.queue_redraw()
			accept_event()
		elif button.button_index in [MOUSE_BUTTON_MIDDLE,MOUSE_BUTTON_RIGHT]:
			if button.button_index==MOUSE_BUTTON_RIGHT and tool=="pin" and button.pressed:
				_remove_pin_near(to_world(button.position))
			else:
				panning = button.pressed
			accept_event()
		elif button.button_index==MOUSE_BUTTON_LEFT:
			grab_focus()
			if button.pressed: _begin_stroke(button.position)
			else: _end_stroke()
			accept_event()
	elif event is InputEventMouseMotion:
		var motion := event as InputEventMouseMotion
		pointer = motion.position
		hovered.emit(to_world(motion.position))
		if panning:
			view.position += motion.relative
			queue_redraw()
		elif painting: _paint_to(motion.position)
		overlay.queue_redraw()
		accept_event()
	elif event is InputEventKey and event.pressed:
		var key := event as InputEventKey
		if key.ctrl_pressed and key.keycode==KEY_Z: undo()
		elif key.ctrl_pressed and key.keycode==KEY_Y: redo()

func _notification(what: int) -> void:
	if what==NOTIFICATION_MOUSE_EXIT:
		pointer = Vector2.INF
		overlay.queue_redraw()
	elif what==NOTIFICATION_RESIZED and source!=null and view.scale.x<=0.0001:
		fit()

# --- Strokes ----------------------------------------------------------------------

func _begin_stroke(local: Vector2) -> void:
	if tool=="pin":
		var world := to_world(local)
		var pins: Array = source.brief.get("pins",[])
		undo_stack.append({"kind":"pins","pins":pins.duplicate(true)})
		redo_stack.clear()
		pins.append({"pos":[snappedf(world.x,.01),snappedf(world.y,.01)],"type":pin_type,"lifetime":"permanent" if pin_type=="crystal" else "disposable"})
		source.brief["pins"] = pins
		overlay.queue_redraw()
		changed.emit()
		return
	_ensure_layer(active_layer)
	if not layer_visible(active_layer): set_layer_visible(active_layer,true)
	painting = true
	stroke_before = (source.masks[active_layer] as Image).duplicate()
	last_paint = Vector2.INF
	_paint_to(local)

func _end_stroke() -> void:
	if not painting: return
	painting = false
	undo_stack.append({"kind":"layer","layer":active_layer,"image":stroke_before})
	if undo_stack.size()>MAX_UNDO: undo_stack.pop_front()
	redo_stack.clear()
	stroke_before = null
	changed.emit()

# Stamps along the drag so fast strokes stay continuous.
func _paint_to(local: Vector2) -> void:
	var at := to_level(local)
	var radius := brush_radius*LevelSource.PX_PER_UNIT
	if last_paint.is_finite():
		var distance := last_paint.distance_to(at)
		var steps := maxi(1,ceili(distance/maxf(1.0,radius*.3)))
		for step in range(1,steps+1): _stamp(last_paint.lerp(at,float(step)/steps),radius)
	else:
		_stamp(at,radius)
	last_paint = at
	refresh_layer(active_layer)

func _stamp(center: Vector2, radius: float) -> void:
	var image: Image = source.masks[active_layer]
	var soft := maxf(1.0,radius*(1.0-brush_hardness))
	var low := Vector2i((center-Vector2.ONE*radius).floor()).max(Vector2i.ZERO)
	var high := Vector2i((center+Vector2.ONE*radius).ceil()).min(image.get_size()-Vector2i.ONE)
	for y in range(low.y,high.y+1):
		for x in range(low.x,high.x+1):
			var distance := center.distance_to(Vector2(x+.5,y+.5))
			if distance>radius: continue
			var amount := clampf((radius-distance)/soft,0,1)*brush_strength
			var value := image.get_pixel(x,y).r
			var result := maxf(value,amount) if tool=="brush" else minf(value,1.0-amount)
			if result!=value: image.set_pixel(x,y,Color(result,result,result))

func undo() -> void:
	_swap(undo_stack,redo_stack)

func redo() -> void:
	_swap(redo_stack,undo_stack)

func _swap(from: Array, to: Array) -> void:
	if from.is_empty() or source==null: return
	var entry: Dictionary = from.pop_back()
	if entry["kind"]=="pins":
		to.append({"kind":"pins","pins":(source.brief.get("pins",[]) as Array).duplicate(true)})
		source.brief["pins"] = entry["pins"]
	else:
		var layer: String = entry["layer"]
		to.append({"kind":"layer","layer":layer,"image":(source.masks[layer] as Image).duplicate()})
		source.masks[layer] = entry["image"]
		(textures[layer] as ImageTexture).set_image(source.masks[layer])
	overlay.queue_redraw()
	changed.emit()

func _remove_pin_near(world: Vector2) -> void:
	var pins: Array = source.brief.get("pins",[])
	var best := -1
	var best_distance := .8
	for index in range(pins.size()):
		var distance := Vector2(pins[index]["pos"][0],pins[index]["pos"][1]).distance_to(world)
		if distance<best_distance:
			best = index
			best_distance = distance
	if best<0: return
	undo_stack.append({"kind":"pins","pins":pins.duplicate(true)})
	pins.remove_at(best)
	overlay.queue_redraw()
	changed.emit()

# Sections, act borders, layout objects, pins and the brush outline, drawn in
# level space above the masks.
class Overlay extends Control:
	const PIN_COLORS := {"stone":Color("e8e2d2"),"root":Color("c98a4b"),"spring":Color("7fd36a"),"ice":Color("9fe3ff"),"crystal":Color("c78cff")}
	var canvas
	func _draw() -> void:
		var source: LevelSource = canvas.source
		if source==null: return
		var unit := float(LevelSource.PX_PER_UNIT)
		var width := float(source.size().x)
		var line := 1.0/maxf(.2,canvas.view.scale.x)
		# 24-unit streaming sections and act borders.
		var y := 0.0
		while y<=source.top():
			var row := source.to_pixel(Vector2(0,y)).y
			draw_line(Vector2(0,row),Vector2(width,row),Color(1,1,1,.18),line)
			y += 24.0
		for act in source.brief.get("acts",[]):
			var row := source.to_pixel(Vector2(0,float(act.get("until",0)))).y
			draw_dashed_line(Vector2(0,row),Vector2(width,row),Color("ffd36b"),line*2,6*line)
			draw_string(ThemeDB.fallback_font,Vector2(4,row-4*line),str(act.get("id","")),HORIZONTAL_ALIGNMENT_LEFT,-1,maxi(8,roundi(12*line)),Color("ffd36b"))
		if canvas.show_objects and not canvas.layout.is_empty():
			var data: Dictionary = canvas.layout
			var main := {}
			for id in data.get("main_route",[]): main[id] = true
			for ledge in data.get("ledges",[]):
				var a := source.to_pixel(Vector2(float(ledge["left"]),float(ledge["top"])))
				var b := source.to_pixel(Vector2(float(ledge["right"]),float(ledge["top"])))
				draw_line(a,b,Color("6b4a2a"),3*line)
			var anchors: Array = data.get("anchors",[])
			for index in range(anchors.size()):
				var anchor: Dictionary = anchors[index]
				var at := source.to_pixel(anchor["pos"])
				var kind: int = int(anchor.get("kind",0))
				var color: Color = PIN_COLORS.values()[clampi(kind,0,4)]
				draw_circle(at,(.42 if main.has(index) else .3)*unit,Color(color,.9))
				draw_arc(at,(.42 if main.has(index) else .3)*unit,0,TAU,16,Color(0,0,0,.6),line)
			for find in data.get("finds",[]):
				var coin: bool = str(find.get("item",{}).get("family",""))=="coin"
				draw_circle(source.to_pixel(find["pos"]),(.12 if coin else .22)*unit,Color("ffd34a"))
		# Pins stay at least 7 screen pixels across at any zoom.
		var pin_radius := maxf(.55*unit,7.0*line)
		for pin in source.brief.get("pins",[]):
			var at := source.to_pixel(Vector2(pin["pos"][0],pin["pos"][1]))
			var color: Color = PIN_COLORS.get(str(pin.get("type","stone")),Color.WHITE)
			draw_line(at,at+Vector2(0,pin_radius*2.2),Color.BLACK,2*line)
			draw_circle(at,pin_radius,Color(color,.95))
			draw_arc(at,pin_radius,0,TAU,20,Color.BLACK,2*line)
		if canvas.pointer.is_finite() and canvas.tool!="pin":
			var at: Vector2 = canvas.to_level(canvas.pointer)
			draw_arc(at,canvas.brush_radius*unit,0,TAU,40,Color(1,1,1,.9),line)
			draw_arc(at,canvas.brush_radius*unit*canvas.brush_hardness,0,TAU,40,Color(1,1,1,.4),line)
