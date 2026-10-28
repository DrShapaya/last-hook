@tool
extends VBoxContainer

# The level editor (docs/LEVEL_PIPELINE.md): pick a level, paint its masks
# over a preview of the baked level, place pins, add hazard zones, save, and
# rebuild the level in a background Godot process. Works as the «Уровни»
# main screen of the editor and, for checks, inside a plain scene.

const MaskCanvas := preload("res://addons/level_editor/mask_canvas.gd")
const PreviewRender := preload("res://addons/level_editor/level_preview_render.gd")
const LEVELS_ROOT := "res://levels"
const PIN_TYPES := ["stone","root","spring","ice","crystal"]
const PIN_NAMES := {"stone":"Камень","root":"Корень","spring":"Ветка","ice":"Лёд","crystal":"Кристалл"}
# Hazard type -> its kind (see LevelCatalog hazard definitions).
const ZONE_TYPES := {"wind_pocket":"field","sand_storm":"field","storm_cycle":"field","blizzard_gust":"field",
	"cactus":"contact","scorpion":"contact","icicle":"falling","sand_bridge":"collapse"}
const ZONE_NAMES := {"wind_pocket":"Ветровой карман","sand_storm":"Песчаная буря","storm_cycle":"Цикл бури","blizzard_gust":"Порыв метели",
	"cactus":"Кактус","scorpion":"Скорпион","icicle":"Сосулька","sand_bridge":"Песчаный мост"}
const QUALITY := "balanced"

# Godot binary used for background rebuilds; the plugin sets the editor's.
var godot_executable := ""

var levels: Array[String] = []
var level_picker := OptionButton.new()
var tool_buttons: Dictionary = {}
var pin_picker := OptionButton.new()
var zone_picker := OptionButton.new()
var size_slider := HSlider.new()
var hardness_slider := HSlider.new()
var opacity_slider := HSlider.new()
var objects_toggle := CheckBox.new()
var masks_toggle := CheckBox.new()
var notes := Label.new()
var save_button := Button.new()
var rebuild_button := Button.new()
var design_button := Button.new()
# Background steps still to run after the current one: [tool path, arguments].
var pending_steps: Array = []
var status := Label.new()
var coordinates := Label.new()
var layer_list := VBoxContainer.new()
var layer_group := ButtonGroup.new()
var canvas := MaskCanvas.new()
var render := PreviewRender.new()
var source: LevelSource
var level_directory := ""
var dirty := false
var rebuild_pid := -1

func _init() -> void:
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(render)
	var bar := HBoxContainer.new()
	add_child(bar)
	bar.add_child(_label("Уровень"))
	level_picker.item_selected.connect(func(index: int) -> void: open_level(levels[index]))
	bar.add_child(level_picker)
	bar.add_child(VSeparator.new())
	var group := ButtonGroup.new()
	for entry in [["brush","Кисть"],["eraser","Ластик"],["pin","Пин"]]:
		var button := Button.new()
		button.text = entry[1]
		button.toggle_mode = true
		button.button_group = group
		button.button_pressed = entry[0]=="brush"
		var tool_name: String = entry[0]
		button.pressed.connect(func() -> void: canvas.tool = tool_name)
		tool_buttons[tool_name] = button
		bar.add_child(button)
	for type in PIN_TYPES: pin_picker.add_item(PIN_NAMES[type])
	pin_picker.item_selected.connect(func(index: int) -> void: canvas.pin_type = PIN_TYPES[index])
	bar.add_child(pin_picker)
	bar.add_child(VSeparator.new())
	bar.add_child(_slider_row("Размер",size_slider,.3,6.0,1.5,func(value: float) -> void: canvas.brush_radius = value))
	bar.add_child(_slider_row("Жёсткость",hardness_slider,0.0,1.0,.6,func(value: float) -> void: canvas.brush_hardness = value))
	bar.add_child(_slider_row("Слои",opacity_slider,.1,1.0,.6,func(value: float) -> void: canvas.set_opacity(value)))
	objects_toggle.text = "Объекты"
	objects_toggle.button_pressed = true
	objects_toggle.toggled.connect(func(on: bool) -> void:
		canvas.show_objects = on
		canvas.overlay.queue_redraw())
	bar.add_child(objects_toggle)
	masks_toggle.text = "Строить по маскам"
	masks_toggle.tooltip_text = "Уровень собирается из масок этого редактора, а не старым генератором"
	masks_toggle.toggled.connect(func(on: bool) -> void:
		if source==null: return
		if on: source.brief["generator"] = "masks"
		else: source.brief.erase("generator")
		dirty = true
		_update_status())
	bar.add_child(masks_toggle)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bar.add_child(spacer)
	save_button.text = "Сохранить"
	save_button.pressed.connect(save_level)
	bar.add_child(save_button)
	rebuild_button.text = "Пересобрать уровень"
	rebuild_button.tooltip_text = "Сохраняет маски и пересобирает уровень в фоне, затем обновляет превью"
	rebuild_button.pressed.connect(rebuild_level)
	bar.add_child(rebuild_button)
	design_button.text = "Новый вариант"
	design_button.tooltip_text = "Автодизайнер придумывает уровень заново со следующим сидом и пересобирает его"
	design_button.pressed.connect(redesign_level)
	bar.add_child(design_button)

	var body := HSplitContainer.new()
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_child(body)
	var side := VBoxContainer.new()
	side.custom_minimum_size = Vector2(230,0)
	body.add_child(side)
	side.add_child(_label("Слои"))
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.add_child(layer_list)
	layer_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	side.add_child(scroll)
	side.add_child(_label("Новая зона опасности"))
	for type in ZONE_TYPES: zone_picker.add_item(ZONE_NAMES[type])
	side.add_child(zone_picker)
	var zone_buttons := HBoxContainer.new()
	var add_zone := Button.new()
	add_zone.text = "Добавить"
	add_zone.pressed.connect(func() -> void: add_zone_layer(ZONE_TYPES.keys()[zone_picker.selected]))
	zone_buttons.add_child(add_zone)
	var remove_zone := Button.new()
	remove_zone.text = "Удалить активную"
	remove_zone.pressed.connect(remove_active_zone)
	zone_buttons.add_child(remove_zone)
	side.add_child(zone_buttons)
	side.add_child(_label("Заметки сборки"))
	notes.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	notes.add_theme_font_size_override("font_size",11)
	notes.custom_minimum_size = Vector2(220,0)
	side.add_child(notes)
	var help := Label.new()
	help.text = "ЛКМ — рисовать или поставить пин\nПКМ — двигать вид; на пине — удалить\nКолесо — масштаб\nCtrl+Z / Ctrl+Y — отмена, повтор"
	help.add_theme_font_size_override("font_size",11)
	side.add_child(help)
	canvas.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	canvas.size_flags_vertical = Control.SIZE_EXPAND_FILL
	canvas.changed.connect(func() -> void:
		dirty = true
		_update_status())
	canvas.hovered.connect(func(world: Vector2) -> void:
		coordinates.text = "x %.1f · %d м" % [world.x,roundi(world.y*10)])
	body.add_child(canvas)

	var footer := HBoxContainer.new()
	add_child(footer)
	status.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	footer.add_child(status)
	footer.add_child(coordinates)

func _ready() -> void:
	scan_levels()
	if not levels.is_empty(): open_level(levels[0])

func _label(text: String) -> Label:
	var label := Label.new()
	label.text = text
	return label

func _slider_row(title: String, slider: HSlider, low: float, high: float, value: float, apply: Callable) -> Control:
	var row := HBoxContainer.new()
	row.add_child(_label(title))
	slider.min_value = low
	slider.max_value = high
	slider.step = .05
	slider.value = value
	slider.custom_minimum_size = Vector2(90,0)
	slider.value_changed.connect(apply)
	row.add_child(slider)
	return row

func scan_levels() -> void:
	levels.clear()
	level_picker.clear()
	if not DirAccess.dir_exists_absolute(LEVELS_ROOT): return
	var names := Array(DirAccess.get_directories_at(LEVELS_ROOT))
	names.sort()
	for name in names:
		var folder := LEVELS_ROOT.path_join(name)
		if LevelSource.exists(folder.path_join("source")):
			levels.append(folder)
			level_picker.add_item(name)

func open_level(folder: String) -> void:
	if dirty and source!=null: save_level()
	var level := LevelSource.open(folder.path_join("source"))
	if level==null:
		status.text = "Не удалось открыть %s" % folder
		return
	level_directory = folder
	source = level
	masks_toggle.set_pressed_no_signal(str(source.brief.get("generator",""))=="masks")
	_load_notes()
	level_picker.select(levels.find(folder))
	canvas.set_source(source)
	_load_layout()
	_refresh_preview()
	_rebuild_layer_list()
	canvas.fit.call_deferred()
	dirty = false
	_update_status()

func _load_layout() -> void:
	canvas.layout = {}
	var path := level_directory.path_join("layout.res")
	if ResourceLoader.exists(path):
		var bake := ResourceLoader.load(path,"",ResourceLoader.CACHE_MODE_IGNORE)
		if bake!=null: canvas.layout = bake.get("layout_data")
	canvas.overlay.queue_redraw()

func _refresh_preview() -> void:
	var sections := render.show_level(level_directory,QUALITY,source.top(),LevelSource.X_MIN,LevelSource.X_MAX)
	canvas.set_preview(render.get_texture() if sections>0 else null)

func _rebuild_layer_list() -> void:
	for child in layer_list.get_children(): child.queue_free()
	var names := LevelSource.LAYERS.keys()
	var zones := []
	for zone in source.brief.get("zones",[]): zones.append(str(zone["mask"]))
	for layer in names+zones:
		var row := HBoxContainer.new()
		var eye := CheckBox.new()
		eye.button_pressed = source.masks.has(layer) and layer not in ["silhouette","depth","difficulty"]
		if source.masks.has(layer): canvas.set_layer_visible(layer,eye.button_pressed)
		var layer_name: String = layer
		eye.toggled.connect(func(on: bool) -> void: canvas.set_layer_visible(layer_name,on))
		row.add_child(eye)
		var swatch := ColorRect.new()
		swatch.color = canvas.layer_color(layer)
		swatch.custom_minimum_size = Vector2(12,12)
		swatch.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(swatch)
		var pick := Button.new()
		pick.toggle_mode = true
		pick.button_group = layer_group
		pick.flat = true
		pick.alignment = HORIZONTAL_ALIGNMENT_LEFT
		pick.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		pick.text = LevelSource.LAYERS.get(layer,_zone_title(layer))
		if not source.masks.has(layer): pick.modulate = Color(1,1,1,.55)
		pick.button_pressed = layer==canvas.active_layer
		pick.pressed.connect(func() -> void:
			canvas.active_layer = layer_name
			eye.button_pressed = true
			if tool_buttons["pin"].button_pressed:
				tool_buttons["brush"].button_pressed = true
				canvas.tool = "brush"
			_update_status())
		row.add_child(pick)
		layer_list.add_child(row)

func _zone_title(layer: String) -> String:
	for zone in source.brief.get("zones",[]):
		if str(zone["mask"])==layer: return "%s · акт %d" % [ZONE_NAMES.get(str(zone.get("type","")),str(zone.get("type",""))),int(zone.get("act",0))+1]
	return layer

func add_zone_layer(type: String) -> void:
	if source==null: return
	var index := 0
	while source.masks.has("zone_%d" % index): index += 1
	var layer := "zone_%d" % index
	source.masks[layer] = source.new_mask()
	var zones: Array = source.brief.get("zones",[])
	zones.append({"mask":layer,"type":type,"kind":ZONE_TYPES[type],"act":0,"params":{}})
	source.brief["zones"] = zones
	canvas.active_layer = layer
	_rebuild_layer_list()
	dirty = true
	_update_status()

func remove_active_zone() -> void:
	var layer := canvas.active_layer
	if source==null or not layer.begins_with("zone_"): return
	source.brief["zones"] = (source.brief.get("zones",[]) as Array).filter(func(zone: Dictionary) -> bool: return str(zone["mask"])!=layer)
	canvas.remove_layer(layer)
	canvas.active_layer = "route"
	_rebuild_layer_list()
	dirty = true
	_update_status()

func save_level() -> void:
	if source==null: return
	var error := source.save()
	dirty = error!=OK
	status.text = "Сохранено" if error==OK else "Ошибка сохранения: %d" % error

# Saves, then runs the bake tool for this level in its own headless Godot,
# so the editor stays responsive; the preview reloads when it ends.
func rebuild_level() -> void:
	if source==null or rebuild_pid>0: return
	save_level()
	_run_steps([["res://tools/bake_levels.gd",[]]],"Пересборка уровня…")

# The automatic designer makes the level anew (next design variant), then
# the level is rebuilt; the editor reloads the new masks.
func redesign_level() -> void:
	if source==null or rebuild_pid>0: return
	var variant := int(source.brief.get("design_variant",0))+1
	_run_steps([["res://tools/design_levels.gd",["--variant=%d" % variant]],["res://tools/bake_levels.gd",[]]],"Автодизайн, вариант %d…" % variant)
	redesigning = true

var redesigning := false

func _run_steps(steps: Array, message: String) -> void:
	pending_steps = steps.duplicate()
	status.text = message
	_start_next_step()

func _start_next_step() -> void:
	var step: Array = pending_steps.pop_front()
	var executable := godot_executable if not godot_executable.is_empty() else OS.get_executable_path()
	var arguments := ["--headless","--path",ProjectSettings.globalize_path("res://"),"--script",step[0],"--",
		"--only=%d:%d" % [int(source.brief.get("location",0)),int(source.brief.get("route",0))]]
	arguments.append_array(step[1])
	rebuild_pid = OS.create_process(executable,arguments)
	rebuild_button.disabled = rebuild_pid>0
	design_button.disabled = rebuild_pid>0
	if rebuild_pid<=0:
		pending_steps.clear()
		status.text = "Не удалось запустить фоновую сборку"

func _process(_delta: float) -> void:
	if rebuild_pid>0 and not OS.is_process_running(rebuild_pid):
		rebuild_pid = -1
		if not pending_steps.is_empty():
			_start_next_step()
			return
		rebuild_button.disabled = false
		design_button.disabled = false
		_reload_scenes()
		if redesigning:
			# New masks on disk: open the level afresh.
			redesigning = false
			dirty = false
			open_level(level_directory)
		else:
			_load_layout()
			_refresh_preview()
			_load_notes()
		status.text = "Уровень пересобран"

# The bake tool's report for this level: what the masks could not get.
func _load_notes() -> void:
	var path := "user://bake_report_%s.txt" % level_directory.get_file()
	notes.text = FileAccess.get_file_as_string(path) if FileAccess.file_exists(path) and source!=null and str(source.brief.get("generator",""))=="masks" else "—"

# Baked scenes changed on disk: drop the cached copies before showing them.
func _reload_scenes() -> void:
	var folder := level_directory.path_join(QUALITY)
	if not DirAccess.dir_exists_absolute(folder): return
	for file in DirAccess.get_files_at(folder):
		var path := folder.path_join(file)
		if path.get_extension()=="scn": ResourceLoader.load(path,"",ResourceLoader.CACHE_MODE_REPLACE)

func _update_status() -> void:
	if source==null: return
	var name := LevelSource.LAYERS.get(canvas.active_layer,_zone_title(canvas.active_layer))
	status.text = "%s · %s · слой: %s%s" % [source.brief.get("id",""),source.brief.get("name",""),name," · есть несохранённые правки" if dirty else ""]
