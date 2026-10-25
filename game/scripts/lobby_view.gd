class_name LobbyView
extends MenuSurface

class UpgradeMeter extends Control:
	var filled := 1
	var unlocked := 1
	var total := 6
	func _draw() -> void:
		var width := (size.x-4*(total-1))/total
		for index in range(total):
			var color := HOLD if index<filled else STONE_LIP if index<unlocked else STONE_SHADE
			var left := index*(width+4)
			# Slanted ticks read as steps up a slope rather than a loading bar.
			draw_colored_polygon(PackedVector2Array([Vector2(left+3,0),Vector2(left+width,0),Vector2(left+width-3,size.y),Vector2(left,size.y)]),color)

# Painterly mountain panorama with atmospheric valley mist, layered ridges,
# soft drifting clouds and a warm sun aura. Veiled over paused runs. In the
# menu and on the result screen a calmer layer takes over, coloured for the
# shown route.
class Backdrop extends Control:
	# One palette per route: fresh alpine blue, warm canyon apricot, icy
	# summit lilac. Sky top/low, far/near ridge, sun glow; then motes (rgb +
	# strength) and how much they fall: pollen, dust, snow.
	const PALETTES := [
		[Color("4f9fe8"),Color("d4ebf8"),Color("9fc6e6"),Color("4d7598"),Color("fff3d0")],
		[Color("e39466"),Color("fbe3c6"),Color("e2ad86"),Color("9a5a43"),Color("fff0c4")],
		[Color("7290d8"),Color("e6edf9"),Color("bccbe8"),Color("5e6f9c"),Color("ffffff")],
	]
	const MOTES := [Color(1,.97,.8,.14),Color(1,.9,.7,.18),Color(1,1,1,.4)]
	const FALLS := [.25,.05,1.0]
	var veil := false:
		set(value):
			veil = value
			_update_veil()
	var art := false:
		set(value):
			art = value
			_update_layers()
	var rect: ColorRect
	var mat: ShaderMaterial
	var art_rect: ColorRect
	var art_mat: ShaderMaterial
	var shown_from := -1
	var shown_to := -1
	var fade: Tween

	func _init() -> void:
		mouse_filter = MOUSE_FILTER_IGNORE
		mat = ShaderMaterial.new()
		mat.shader = preload("res://shaders/lobby_backdrop.gdshader")
		rect = ColorRect.new()
		rect.mouse_filter = MOUSE_FILTER_IGNORE
		rect.material = mat
		rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		add_child(rect)
		art_mat = ShaderMaterial.new()
		art_mat.shader = preload("res://shaders/menu_route_backdrop.gdshader")
		art_rect = ColorRect.new()
		art_rect.mouse_filter = MOUSE_FILTER_IGNORE
		art_rect.material = art_mat
		art_rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		art_rect.visible = false
		add_child(art_rect)
		show_route(0)

	func _notification(what: int) -> void:
		if what == NOTIFICATION_RESIZED:
			_update_aspect()

	func _process(_delta: float) -> void:
		if not visible: return
		var now := float(Time.get_ticks_msec()) / 1000.0
		if is_instance_valid(art_rect) and art_rect.visible:
			art_mat.set_shader_parameter("time", now)
		elif is_instance_valid(mat) and not veil:
			mat.set_shader_parameter("time", now)

	func _update_aspect() -> void:
		if is_instance_valid(mat) and size.y > 0:
			mat.set_shader_parameter("aspect", size.x / maxf(1.0, size.y))
			art_mat.set_shader_parameter("aspect", size.x / maxf(1.0, size.y))

	func _update_veil() -> void:
		if is_instance_valid(mat):
			mat.set_shader_parameter("veil", veil)
		_update_layers()

	# Only one full-screen layer draws at a time: the route sky in the menu,
	# the panorama (or its veil) elsewhere.
	func _update_layers() -> void:
		if not is_instance_valid(art_rect): return
		art_rect.visible = art and not veil
		rect.visible = not art_rect.visible

	func _side(side: String, location: int) -> void:
		var index := clampi(location,0,PALETTES.size()-1)
		var palette: Array = PALETTES[index]
		for slot in range(5):
			art_mat.set_shader_parameter(["sky_top_","sky_low_","far_","near_","glow_"][slot]+side,palette[slot])
		var mote: Color = MOTES[index]
		art_mat.set_shader_parameter("mote_"+side,Vector4(mote.r,mote.g,mote.b,mote.a))
		art_mat.set_shader_parameter("fall_"+side,FALLS[index])

	# Shows the blend between two routes: 0 is all `from`, 1 all `to`.
	func show_routes(from: int, to: int, amount: float) -> void:
		if from!=shown_from:
			_side("a",from)
			shown_from = from
		if to!=shown_to:
			_side("b",to)
			shown_to = to
		art_mat.set_shader_parameter("blend",clampf(amount,0,1))

	func show_route(location: int) -> void:
		if fade!=null and fade.is_valid(): fade.kill()
		show_routes(location,location,0.0)

	# A gentle cross-fade for switches that have no swipe to follow.
	func fade_to(location: int) -> void:
		if shown_from==location and shown_to==location: return
		if fade!=null and fade.is_valid(): fade.kill()
		var start := shown_from if float(art_mat.get_shader_parameter("blend"))<.5 else shown_to
		show_routes(start,location,0.0)
		fade = create_tween()
		fade.tween_method(func(value: float): show_routes(start,location,value),0.0,1.0,.5).set_trans(Tween.TRANS_SINE)
		fade.tween_callback(show_route.bind(location))

	func _draw() -> void:
		pass

# Horizontal swipes follow the finger like a pager. Over the route card only
# the card strip moves and the neighbouring route slides in beside it; anywhere
# else the whole section slides and the neighbouring section is built next to
# it. Distances are in design pixels, so the feel is the same on every screen.
const SWIPE_COMMIT := .2
const SWIPE_FLICK_DISTANCE := 36.0
const SWIPE_FLICK_SPEED := 500.0
const SWIPE_RATIO := 1.6
# Past this sideways drift a press is a swipe attempt and can no longer
# activate the button it started on.
const SWIPE_SLOP := 24.0
const SWIPE_RUBBER := .3
const SWIPE_RUBBER_LIMIT := 64.0
const SWIPE_COOLDOWN_MSEC := 80
const PAGE_GAP := 24.0
# Set while building the expedition body. A neighbouring section built as a
# drag preview must not overwrite the live references.
const PAGE_REFS := ["start_button","scenic_frame","card_rect","card_clip","card_left","card_step","card_scroll","route_cards","card_arrows","location_nodes","location_anchor","acts_anchor","route_line","route_panel","card_park"]

var swipe_pointer := -2
var swipe_from := Vector2.ZERO
var swipe_msec := 0
var swipe_dragging := false
var swipe_kind := ""
var body_nodes: Array[Control] = []
var header_nodes: Array[Control] = []
# The current section body, neighbours built for a drag and sections that are
# sliding out after a switch.
var page: Control
var preview_pages := {}
var outgoing_pages: Array = []
var page_cache := {}
var prebuild_queue: Array = []
var prebuild_at := 0
var page_tween: Tween
# Route cards sit in a clipped strip; card_scroll is the strip position in
# pixels, so a drag, a button and a keyboard step all move the same value.
var card_rect := Rect2()
var card_clip: Control
var card_left := 0.0
var card_step := 0.0
var card_scroll := 0.0
var card_tween: Tween
var route_cards := {}
var card_arrows: Array = []
var scenic_frame: Panel
# Only the start action and its requirement depend on the shown route. They
# are replaced in place, so the route line and modes never blink.
var location_nodes: Array = []
var location_anchor := Rect2()
var acts_anchor := Rect2()
var route_line: RouteLine
var route_panel: Panel
var card_park: Control
var start_button: Button
var tab_buttons: Array[Button] = []
var navigation_bar: Control
var nav_pill: Panel
var nav_marker: ColorRect
var nav_symbols: Array = []
var soon_badge: Panel
var supplies_badge: Panel
# The profile's mini icon: the launch splash flies the big icon into it.
var profile_mark: TextureRect
var endless_badge: Panel
# True while the menu is driven by keys or a controller (see apply_focus).
var keyboard_focus := false

func setup(owner_hud: GameHud) -> void:
	prepare(owner_hud)
	var bounds := _calculate_layout_bounds()
	landscape = bounds.landscape
	size = bounds.size
	position = bounds.position
	scale = Vector2.ONE*float(bounds.scale)
	_build_screen()

func _calculate_layout_bounds() -> Dictionary:
	var target_landscape: bool = hud.wide
	# The native banner is the top edge of the menu: the header starts right
	# under it, as if the screen ended there.
	var banner: float = hud.screen_to_design(game.ads.menu_banner_height())
	var top_boundary: float = maxf(hud.safe_inset_top(), banner)
	var bottom_boundary: float = hud.root.size.y - hud.safe_inset_bottom()
	var target_size: Vector2
	var target_position: Vector2
	var target_scale := 1.0
	if target_landscape:
		target_size = Vector2(1080, 660)
		# The landscape canvas is fixed; when the banner leaves less than its
		# height, the whole menu scales down to fit under it.
		target_scale = minf(1.0, (bottom_boundary - top_boundary) / target_size.y)
		var shown := target_size * target_scale
		var centered: float = (hud.root.size.y - shown.y) * 0.5
		target_position = Vector2((hud.root.size.x - shown.x) * 0.5, clampf(centered, top_boundary, maxf(top_boundary, bottom_boundary - shown.y)))
	else:
		target_size = Vector2(540, maxf(700.0, bottom_boundary - top_boundary))
		target_position = Vector2((hud.root.size.x - target_size.x) * 0.5, top_boundary)
	return {"landscape": target_landscape, "size": target_size, "position": target_position, "scale": target_scale}

func _kill(tween: Tween) -> void:
	if tween!=null and tween.is_valid(): tween.kill()

func _free(node: Node) -> void:
	if not is_instance_valid(node): return
	if node.get_parent()!=null: node.get_parent().remove_child(node)
	node.queue_free()

func _clear_page_refs() -> void:
	route_line = null
	route_panel = null
	start_button = null
	scenic_frame = null
	card_rect = Rect2()
	card_clip = null
	card_park = null
	route_cards = {}
	card_arrows = []
	location_nodes = []

func _reset_build_state() -> void:
	swipe_pointer = -2
	swipe_dragging = false
	swipe_kind = ""
	_kill(page_tween)
	_kill(card_tween)
	_drop_cache()
	for child in get_children():
		remove_child(child)
		child.queue_free()
	body_nodes.clear()
	header_nodes.clear()
	tab_buttons.clear()
	preview_pages.clear()
	outgoing_pages.clear()
	page = null
	navigation_bar = null
	_clear_page_refs()

func _build_screen() -> void:
	_reset_build_state()
	build_header()
	for child in get_children():
		if child is Control: header_nodes.append(child)
	hud.menu_slide = 0
	hud.backdrop.show_route(game.lobby_location)
	page = build_page(hud.menu_tab)
	_collect_body()
	build_navigation()
	apply_focus()
	_schedule_prebuild()

# Builds one section body inside its own holder, so the whole section can
# slide as a single page.
func build_page(tab: String) -> Control:
	var holder := Control.new()
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	holder.size = size
	holder.set_meta("tab",tab)
	add_child(holder)
	var first := get_child_count()
	match tab:
		"equipment": build_equipment()
		"settings": build_settings()
		_: build_expedition()
	for node in get_children().slice(first):
		remove_child(node)
		holder.add_child(node)
	return holder

func _capture_refs() -> Dictionary:
	var refs := {}
	for name in PAGE_REFS: refs[name] = get(name)
	return refs

func _restore_refs(refs: Dictionary) -> void:
	for name in PAGE_REFS:
		if refs.has(name): set(name,refs[name])

# Builds a section that is not shown yet. Its own references travel with it
# (meta "refs"), so it can later become the live page without a rebuild.
func build_preview_page(tab: String) -> Control:
	var saved := _capture_refs()
	_clear_page_refs()
	var holder := build_page(tab)
	holder.set_meta("refs",_capture_refs())
	_restore_refs(saved)
	holder.process_mode = Node.PROCESS_MODE_DISABLED
	return holder

# --- Page cache ------------------------------------------------------------------
# Built sections stay alive off the tree, and the neighbours of the shown one
# are built while the menu is idle. A switch or a swipe then slides a ready
# page in instead of building it mid-gesture. Any change of the menu's state
# (a purchase, a choice that reshapes a page) drops the cache.

func _park(node: Control) -> void:
	if not is_instance_valid(node): return
	var tab := str(node.get_meta("tab",""))
	if tab.is_empty() or (page_cache.has(tab) and page_cache[tab]!=node):
		_free(node)
		return
	if node.get_parent()!=null: node.get_parent().remove_child(node)
	node.position.x = 0.0
	node.modulate.a = 1.0
	page_cache[tab] = node

func _drop_cache() -> void:
	for tab in page_cache.keys(): _free(page_cache[tab])
	page_cache.clear()
	prebuild_queue.clear()

# A ready page for a section, attached below the section bar and inert.
func _take(tab: String) -> Control:
	var node: Control
	if page_cache.has(tab) and is_instance_valid(page_cache[tab]):
		node = page_cache[tab]
		page_cache.erase(tab)
		add_child(node)
	else:
		node = build_preview_page(tab)
	node.process_mode = Node.PROCESS_MODE_DISABLED
	if is_instance_valid(navigation_bar): move_child(node,navigation_bar.get_index())
	return node

func _adopt(node: Control) -> void:
	page = node
	_restore_refs(node.get_meta("refs",{}))
	node.process_mode = Node.PROCESS_MODE_INHERIT
	node.modulate.a = 1.0

func _schedule_prebuild() -> void:
	prebuild_queue.clear()
	prebuild_queue.append("cards")
	var index: int = GameHud.MENU_TABS.find(hud.menu_tab)
	for side in [1,-1]:
		if index+side>=0 and index+side<GameHud.MENU_TABS.size(): prebuild_queue.append(GameHud.MENU_TABS[index+side])
	prebuild_at = Time.get_ticks_msec()+350

# One neighbour per idle moment: never during a touch or a slide.
func _process(_delta: float) -> void:
	if prebuild_queue.is_empty() or swipe_pointer!=-2 or Time.get_ticks_msec()<prebuild_at: return
	if (page_tween!=null and page_tween.is_running()) or (card_tween!=null and card_tween.is_running()): return
	var tab: String = prebuild_queue.pop_front()
	prebuild_at = Time.get_ticks_msec()+120
	if tab=="cards":
		if park_neighbour_card(): prebuild_queue.push_front("cards")
		return
	if tab==hud.menu_tab or page_cache.has(tab): return
	_park(build_preview_page(tab))

func _collect_body() -> void:
	body_nodes.clear()
	if not is_instance_valid(page): return
	for node in page.get_children():
		if node is Control: body_nodes.append(node)

func page_step() -> float:
	return maxf(size.x,hud.root.size.x)+PAGE_GAP

static func slide_duration(distance: float, span: float) -> float:
	return clampf(.16+.2*absf(distance)/maxf(1.0,span),.16,.34)

static func rubber(offset: float) -> float:
	return signf(offset)*minf(absf(offset)*SWIPE_RUBBER,SWIPE_RUBBER_LIMIT)

func update_layout() -> void:
	var bounds := _calculate_layout_bounds()
	var changed: bool = (landscape != bounds.landscape) or (not size.is_equal_approx(bounds.size)) or (not position.is_equal_approx(bounds.position)) or not is_equal_approx(scale.x,float(bounds.scale))
	landscape = bounds.landscape
	size = bounds.size
	position = bounds.position
	scale = Vector2.ONE*float(bounds.scale)
	if changed:
		_build_screen()
	else:
		layout_navigation()

func update_banner_inset(_pixels: float = 0.0) -> void:
	update_layout()

func refresh_screen() -> void:
	# Keep the header, wallet and backdrop alive. Only the section body and the
	# navigation selection are replaced, so values at the top never blink.
	var direction: int = hud.menu_slide
	hud.menu_slide = 0
	_kill(card_tween)
	_kill(page_tween)
	# A switch continues from wherever the current page is: under the finger
	# after a drag, or mid-way through the previous slide.
	var carried: float = page.position.x if is_instance_valid(page) else 0.0
	var old := page
	if is_instance_valid(old): old.set_meta("refs",_capture_refs())
	for node in outgoing_pages: _park(node)
	outgoing_pages.clear()
	var incoming: Control = preview_pages.get(direction) if direction!=0 else null
	for side in preview_pages.keys():
		if preview_pages[side]!=incoming: _park(preview_pages[side])
	preview_pages.clear()
	_clear_page_refs()
	if direction!=0:
		if incoming!=null and str(incoming.get_meta("tab",""))!=hud.menu_tab:
			_park(incoming)
			incoming = null
		if incoming==null: incoming = _take(hud.menu_tab)
		_adopt(incoming)
	else:
		# The menu's state changed: every kept page may be out of date.
		_drop_cache()
		page = build_page(hud.menu_tab)
		if is_instance_valid(navigation_bar): move_child(page,navigation_bar.get_index())
	_collect_body()
	if is_instance_valid(navigation_bar): paint_navigation()
	else: build_navigation()
	hud.backdrop.fade_to(game.lobby_location)
	if is_instance_valid(old):
		if direction!=0:
			old.process_mode = Node.PROCESS_MODE_DISABLED
			outgoing_pages.append(old)
			old.position.x = carried
			page.position.x = carried+direction*page_step()
			slide_pages()
		else:
			_free(old)
	apply_focus()
	_schedule_prebuild()

func apply_focus() -> void:
	var focus: String = hud.menu_focus
	hud.menu_focus = ""
	# Focus outlines are for keyboard and controller play only. After a tap or
	# a swipe a focused button kept its dark outline until the next switch.
	if not keyboard_focus:
		if is_instance_valid(get_viewport()): get_viewport().gui_release_focus()
		return
	var target: Button = start_button if focus=="start" and is_instance_valid(start_button) and not start_button.disabled else null
	if focus!="" and target==null:
		var index: int = GameHud.MENU_TABS.find(hud.menu_tab)
		if index>=0 and index<tab_buttons.size(): target = tab_buttons[index]
	if target!=null:
		target.focus_mode = Control.FOCUS_ALL
		target.grab_focus()
		target.call_deferred("grab_focus")

# --- Section pager ---------------------------------------------------------------

func drag_section(offset: float) -> void:
	if not is_instance_valid(page): return
	var side := 1 if offset<0 else -1
	var index: int = GameHud.MENU_TABS.find(hud.menu_tab)+side
	if index<0 or index>=GameHud.MENU_TABS.size():
		offset = rubber(offset)
	elif not preview_pages.has(side):
		# Below the section bar, which never slides.
		preview_pages[side] = _take(GameHud.MENU_TABS[index])
	page.position.x = offset
	for key in preview_pages.keys():
		preview_pages[key].position.x = offset+int(key)*page_step()

# Moves every page so the current one lands at rest, then drops the others.
func slide_pages() -> void:
	_kill(page_tween)
	if not is_instance_valid(page): return
	var shift := -page.position.x
	if is_zero_approx(shift):
		_finish_pages()
		return
	var duration := slide_duration(shift,page_step())
	page_tween = create_tween().set_parallel(true)
	var moving: Array = [page]+outgoing_pages+preview_pages.values()
	for node in moving:
		if is_instance_valid(node):
			page_tween.tween_property(node,"position:x",node.position.x+shift,duration).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	# The section leaving fades a little: the new one clearly takes over.
	for node in outgoing_pages:
		if is_instance_valid(node): page_tween.tween_property(node,"modulate:a",.35,duration)
	page_tween.chain().tween_callback(_finish_pages)

func _finish_pages() -> void:
	for node in outgoing_pages: _park(node)
	outgoing_pages.clear()
	for side in preview_pages.keys(): _park(preview_pages[side])
	preview_pages.clear()
	if is_instance_valid(page): page.position.x = 0.0

func settle_pages() -> void:
	_kill(page_tween)
	_finish_pages()

# --- Route card strip ------------------------------------------------------------

func routes_swipeable() -> bool:
	return hud.menu_tab=="expedition" and model.profile["active"].is_empty() and is_instance_valid(card_clip)

func build_card_carousel(at: Vector2, dimensions: Vector2) -> void:
	card_rect = Rect2(at,dimensions)
	var clip := Control.new()
	clip.clip_contents = true
	clip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if landscape:
		clip.position = at
		clip.size = dimensions
	else:
		# In portrait the strip spans the whole screen width, so the next route
		# enters from beyond the screen edge like a page.
		clip.position = Vector2(-position.x,at.y)
		clip.size = Vector2(hud.root.size.x,dimensions.y)
	add_child(clip)
	card_clip = clip
	card_left = at.x-clip.position.x
	card_step = dimensions.x+maxf(PAGE_GAP,clip.size.x-dimensions.x)
	card_scroll = game.lobby_location*card_step
	route_cards = {}
	# Neighbouring routes are built ahead of time into this hidden holder.
	card_park = Control.new()
	card_park.visible = false
	card_park.mouse_filter = Control.MOUSE_FILTER_IGNORE
	clip.add_child(card_park)
	scenic_frame = ensure_card(game.lobby_location)
	# Arrows belong to the window, not to a card: they stay put while routes
	# slide underneath.
	card_arrows = []
	for direction in [-1,1]:
		var arrow := action(clip,"",Vector2(card_left+14 if direction<0 else card_left+dimensions.x-62,(dimensions.y-5)*.40),Vector2(48,52),game.cycle_location.bind(direction))
		arrow.tooltip_text = "Предыдущий маршрут" if direction<0 else "Следующий маршрут"
		symbol(arrow,10 if direction<0 else 11,Vector2(12,12),Vector2(24,24),INK)
		card_arrows.append(arrow)
	update_card_arrows()

func update_card_arrows() -> void:
	var total: int = model.balance["locations"].size()
	var active: bool = not model.profile["active"].is_empty()
	for index in range(card_arrows.size()):
		var arrow: Button = card_arrows[index]
		if not is_instance_valid(arrow): continue
		var next: int = game.lobby_location+(-1 if index==0 else 1)
		var at_end := next<0 or next>=total
		arrow.disabled = active or at_end
		arrow.visible = not active
		arrow.modulate.a = .45 if at_end else 1.0

func ensure_card(location: int) -> Panel:
	if route_cards.has(location) and is_instance_valid(route_cards[location]): return route_cards[location]
	var card: Panel = card_park.get_node_or_null("Route%d" % location) if is_instance_valid(card_park) else null
	if card!=null:
		card_park.remove_child(card)
		card_clip.add_child(card)
	else:
		card = route_card(card_clip,location,card_rect.size)
		card.name = "Route%d" % location
	# Under the fixed arrows.
	card_clip.move_child(card,0)
	route_cards[location] = card
	place_cards()
	return card

# Builds one missing neighbour card into the hidden holder. Returns false
# once both neighbours are ready.
func park_neighbour_card() -> bool:
	if not routes_swipeable() or not is_instance_valid(card_park): return false
	var total: int = model.balance["locations"].size()
	for location in [game.lobby_location+1,game.lobby_location-1]:
		if location<0 or location>=total or route_cards.has(location) or card_park.has_node("Route%d" % location): continue
		var card := route_card(card_park,location,card_rect.size)
		card.name = "Route%d" % location
		return true
	return false

# Cards leaving the centre sink back a little and dim, so the strip reads
# as a carousel with depth rather than flat panels.
func place_cards() -> void:
	for location in route_cards.keys():
		var card: Control = route_cards[location]
		if not is_instance_valid(card): continue
		card.position = Vector2(card_left+int(location)*card_step-card_scroll,0)
		var away := clampf(absf(card.position.x-card_left)/maxf(1.0,card_step),0,1)
		card.pivot_offset = card.size*.5
		card.scale = Vector2.ONE*(1.0-.08*away)
		card.modulate = Color.WHITE.lerp(Color(.78,.82,.88),away)

func set_card_scroll(value: float) -> void:
	card_scroll = value
	if card_step<=0 or not is_instance_valid(card_clip): return
	var total: int = model.balance["locations"].size()
	for location in [floori(value/card_step),ceili(value/card_step)]:
		if location>=0 and location<total: ensure_card(location)
	place_cards()
	# The backdrop blends between the two routes as far as the strip has moved.
	var at := clampf(value/card_step,0,total-1)
	hud.backdrop.show_routes(floori(at),mini(floori(at)+1,total-1),at-floori(at))

func drag_cards(offset: float) -> void:
	if not is_instance_valid(card_clip): return
	var next: int = game.lobby_location+(1 if offset<0 else -1)
	if next<0 or next>=model.balance["locations"].size(): offset = rubber(offset)
	set_card_scroll(game.lobby_location*card_step-offset)

func slide_cards() -> void:
	_kill(card_tween)
	var target: float = game.lobby_location*card_step
	if is_equal_approx(card_scroll,target):
		_prune_cards()
		return
	card_tween = create_tween()
	card_tween.tween_method(set_card_scroll,card_scroll,target,slide_duration(target-card_scroll,card_step)).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	card_tween.tween_callback(_prune_cards)

func _prune_cards() -> void:
	if not is_instance_valid(card_clip): return
	card_scroll = game.lobby_location*card_step
	hud.backdrop.show_route(game.lobby_location)
	for location in route_cards.keys():
		if int(location)!=game.lobby_location:
			var card: Control = route_cards[location]
			route_cards.erase(location)
			if is_instance_valid(card) and is_instance_valid(card_park):
				card_clip.remove_child(card)
				card.position = Vector2.ZERO
				card.scale = Vector2.ONE
				card.modulate = Color.WHITE
				card_park.add_child(card)
			else: _free(card)
	place_cards()

func settle_cards() -> void:
	_kill(card_tween)
	_prune_cards()

# Called after game.lobby_location changed: slides to the route from wherever
# the strip is and swaps only the route-dependent actions.
func show_location() -> bool:
	if hud.menu_tab!="expedition" or not is_instance_valid(card_clip) or not is_instance_valid(page): return false
	settle_pages()
	scenic_frame = ensure_card(game.lobby_location)
	card_clip.move_child(scenic_frame,0)
	update_card_arrows()
	update_route_line()
	build_location_actions(page)
	slide_cards()
	if hud.menu_focus=="start": apply_focus()
	if not prebuild_queue.has("cards"): prebuild_queue.push_front("cards")
	prebuild_at = Time.get_ticks_msec()+400
	return true

func settle_slides() -> void:
	settle_cards()
	settle_pages()

func bounce(direction: int, on_card: bool = false) -> void:
	# Feedback at the first/last section or route: a short elastic nudge.
	settle_slides()
	if on_card and is_instance_valid(card_clip):
		var rest := card_scroll
		card_tween = create_tween()
		card_tween.tween_method(set_card_scroll,rest,rest+18*direction,.08).set_trans(Tween.TRANS_SINE)
		card_tween.tween_method(set_card_scroll,rest+18*direction,rest,.22).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		card_tween.tween_callback(_prune_cards)
		return
	if not is_instance_valid(page): return
	page_tween = create_tween()
	page_tween.tween_property(page,"position:x",-18.0*direction,.08).set_trans(Tween.TRANS_SINE)
	page_tween.tween_property(page,"position:x",0.0,.22).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

# --- Gestures --------------------------------------------------------------------

func local_point(screen: Vector2) -> Vector2:
	return get_global_transform().affine_inverse()*screen

func drag(offset: float) -> void:
	if swipe_kind=="card": drag_cards(offset)
	else: drag_section(offset)

func spring_back() -> void:
	if swipe_kind=="card": slide_cards()
	else: slide_pages()

func _input(event: InputEvent) -> void:
	if not is_inside_tree() or hud.layout_mode!="menu" or game.state!="menu" or game.ads.fullscreen: return
	if event is InputEventKey or event is InputEventJoypadButton:
		if event.is_pressed(): keyboard_focus = true
		_navigation_input(event)
		return
	var pointer := -2
	var position_value := Vector2.ZERO
	var pressed_value := false
	var released := false
	if event is InputEventScreenTouch:
		if event.canceled:
			if event.index==swipe_pointer:
				if swipe_dragging: spring_back()
				swipe_pointer = -2
				swipe_dragging = false
			return
		pointer = event.index
		position_value = event.position
		pressed_value = event.pressed
		released = not event.pressed
	elif event is InputEventScreenDrag:
		pointer = event.index
		position_value = event.position
	elif event is InputEventMouseButton and event.button_index==MOUSE_BUTTON_LEFT and event.device!=InputEvent.DEVICE_ID_EMULATION:
		pointer = -1
		position_value = event.position
		pressed_value = event.pressed
		released = not event.pressed
	elif event is InputEventMouseMotion and event.device!=InputEvent.DEVICE_ID_EMULATION:
		pointer = -1
		position_value = event.position
	else:
		return
	var at := local_point(position_value)
	if pressed_value:
		keyboard_focus = false
		if swipe_pointer==-2:
			settle_slides()
			swipe_pointer = pointer
			swipe_from = at
			swipe_msec = Time.get_ticks_msec()
			swipe_dragging = false
			swipe_kind = ""
		return
	if pointer!=swipe_pointer: return
	var travel := at-swipe_from
	if not released:
		if not swipe_dragging and absf(travel.x)>SWIPE_SLOP and absf(travel.x)>absf(travel.y)*SWIPE_RATIO:
			get_viewport().set_input_as_handled()
			swipe_dragging = true
			swipe_kind = "card" if routes_swipeable() and card_rect.has_point(swipe_from) else "section"
		if swipe_dragging: drag(travel.x)
		return
	swipe_pointer = -2
	if not swipe_dragging: return
	swipe_dragging = false
	# The release belongs to the gesture, never to the button under it.
	get_viewport().set_input_as_handled()
	var seconds := maxf(.001,(Time.get_ticks_msec()-swipe_msec)*.001)
	var speed := absf(travel.x)/seconds
	var span := card_step if swipe_kind=="card" else page_step()
	var horizontal := absf(travel.x)>absf(travel.y)*SWIPE_RATIO
	var far := absf(travel.x)>=span*SWIPE_COMMIT or (absf(travel.x)>=SWIPE_FLICK_DISTANCE and speed>=SWIPE_FLICK_SPEED)
	var committed := false
	if horizontal and far and Time.get_ticks_msec()-hud.last_swipe_msec>=SWIPE_COOLDOWN_MSEC:
		hud.last_swipe_msec = Time.get_ticks_msec()
		# Finger moving left reveals what is to the right.
		committed = swipe(-1 if travel.x>0 else 1,swipe_kind=="card")
	if not committed: spring_back()

func swipe(direction: int, on_card: bool, focus: String = "tab") -> bool:
	if on_card and routes_swipeable():
		hud.menu_focus = "start"
		if game.cycle_location(direction): return true
		hud.menu_focus = ""
		return false
	return hud.step_menu(direction,focus)

func _navigation_input(event: InputEvent) -> void:
	if not event.is_pressed() or event.is_echo(): return
	var direction := 0
	var routes := false
	if event is InputEventKey and event.keycode in [KEY_Q,KEY_PAGEUP]: direction = -1
	elif event is InputEventKey and event.keycode in [KEY_E,KEY_PAGEDOWN]: direction = 1
	elif event is InputEventJoypadButton and event.button_index==JOY_BUTTON_LEFT_SHOULDER: direction = -1
	elif event is InputEventJoypadButton and event.button_index==JOY_BUTTON_RIGHT_SHOULDER: direction = 1
	elif event.is_action_pressed("ui_left") or event.is_action_pressed("ui_right"):
		direction = -1 if event.is_action_pressed("ui_left") else 1
		# Arrows pick routes on the expedition screen and sections elsewhere.
		routes = routes_swipeable()
	elif event.is_action_pressed("ui_accept") and hud.menu_tab=="expedition" and is_instance_valid(start_button) and not start_button.disabled:
		# Keyboard start never buys a locked route; that stays a deliberate tap.
		if not model.profile["active"].is_empty() or model.profile["locations"].has(game.lobby_location):
			get_viewport().set_input_as_handled()
			game.lobby_action()
		return
	if direction==0: return
	get_viewport().set_input_as_handled()
	if not swipe(direction,routes): bounce(direction,routes)

func build_header() -> void:
	# Tight to the top edge: right under the banner or the screen cut-out.
	var top := 12.0
	# The character section is not built yet. Its entry is a real raised
	# button (portrait, name, arrow) that says so and answers a tap with a note.
	var character := action(self,"",Vector2(20,top),Vector2(236,52),_character_soon,"secondary")
	character.tooltip_text = "Персонаж: скоро"
	var mark := TextureRect.new()
	mark.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	mark.texture = preload("res://assets/icon.png")
	mark.position = Vector2(6,5)
	mark.size = Vector2(38,38)
	mark.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	mark.material = rounded_material(mark.size,9)
	mark.mouse_filter = Control.MOUSE_FILTER_IGNORE
	character.add_child(mark)
	profile_mark = mark
	text(character,"Персонаж",Vector2(52,4),Vector2(120,24),18,INK,"display")
	soon_badge = soon_tag(character,Vector2(53,27))
	symbol(character,11,Vector2(200,12),Vector2(24,24),INK_SOFT)
	wallet(Vector2(size.x-236,top+3))

func _character_soon() -> void:
	wiggle_soon(soon_badge,"Раздел «Персонаж» скоро откроется")

# The section bar is built once per screen and kept: a slate pill glides
# under the chosen section and the hold-yellow marker follows it. Keeping the
# buttons alive means a tap that starts during a switch still lands.
func build_navigation() -> void:
	var width := 484.0 if not landscape else 540.0
	var at := Vector2((size.x-width)*.5,size.y-82)
	var bar := slab(self,at,Vector2(width,66))
	navigation_bar = bar
	var entries := [["equipment","Снаряжение",20],["expedition","Восхождение",7],["settings","Настройки",15]]
	var each := (width-16)/3
	var current := maxi(0,GameHud.MENU_TABS.find(hud.menu_tab))
	nav_pill = slab(bar,Vector2(8+current*each,7),Vector2(each-(0 if current==2 else 4),50),SLATE,SLATE_LIP,4)
	var clear: StyleBoxFlat = hud.slab_style(Color(STONE,0),Color.TRANSPARENT,0,9)
	clear.content_margin_left = 40
	clear.content_margin_right = 6
	clear.content_margin_top = 4
	clear.content_margin_bottom = 4
	nav_symbols = []
	for index in range(3):
		var entry: Array = entries[index]
		var tab := action(bar,str(entry[1]),Vector2(8+index*each,7),Vector2(each-(0 if index==2 else 4),50),slide_to_tab.bind(str(entry[0])),"ghost")
		tab_buttons.append(tab)
		tab.add_theme_font_size_override("font_size",14)
		tab.alignment = HORIZONTAL_ALIGNMENT_LEFT
		tab.add_theme_constant_override("h_separation",0)
		for state_name in ["normal","hover","pressed","disabled"]: tab.add_theme_stylebox_override(state_name,clear)
		# The pill and the yellow marker already show the chosen section; a
		# focus outline on top of them read as a stray black frame.
		tab.add_theme_stylebox_override("focus",StyleBoxEmpty.new())
		nav_symbols.append(symbol(tab,int(entry[2]),Vector2(10,12),Vector2(24,24),INK_SOFT))
	layout_navigation()
	nav_marker = ColorRect.new()
	nav_marker.color = HOLD
	nav_marker.mouse_filter = Control.MOUSE_FILTER_IGNORE
	nav_marker.size = Vector2(each-28,4)
	var previous := maxi(0,GameHud.MENU_TABS.find(hud.menu_previous_tab))
	nav_marker.position = Vector2(8+previous*each+12,58)
	bar.add_child(nav_marker)
	paint_navigation()

func paint_navigation() -> void:
	if not is_instance_valid(navigation_bar): return
	var width := navigation_bar.size.x
	var each := (width-16)/3
	var current := maxi(0,GameHud.MENU_TABS.find(hud.menu_tab))
	for index in range(tab_buttons.size()):
		var selected := index==current
		var ink := STONE if selected else INK_SOFT
		for color_name in ["font_color","font_hover_color","font_pressed_color","font_hover_pressed_color","font_focus_color"]:
			tab_buttons[index].add_theme_color_override(color_name,ink if selected or color_name=="font_color" else INK)
		if index<nav_symbols.size() and is_instance_valid(nav_symbols[index]):
			nav_symbols[index].tint = ink
			nav_symbols[index].queue_redraw()
	var tween := navigation_bar.create_tween().set_parallel(true)
	tween.tween_property(nav_pill,"position:x",8+current*each,.26).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tween.tween_property(nav_pill,"size:x",each-(0 if current==2 else 4),.26).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tween.tween_property(nav_marker,"position:x",8+current*each+12,.26).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	hud.menu_previous_tab = hud.menu_tab

# A tapped section slides in from its side, like a swipe.
func slide_to_tab(tab: String) -> void:
	hud.menu_slide = signi(GameHud.MENU_TABS.find(tab)-GameHud.MENU_TABS.find(hud.menu_tab))
	hud.select_menu(tab)

func layout_navigation() -> void:
	if not is_instance_valid(navigation_bar): return
	var width := 484.0 if not landscape else 540.0
	var at := Vector2((size.x-width)*.5,size.y-82)
	navigation_bar.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	navigation_bar.position = at
	navigation_bar.size = Vector2(width,66)
	navigation_bar.clip_contents = true
	var each := (width-16)/3
	for index in range(mini(3,tab_buttons.size())):
		var tab := tab_buttons[index]
		if not is_instance_valid(tab): continue
		tab.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
		tab.position = Vector2(8+index*each,7)
		tab.custom_minimum_size = Vector2(each-(0 if index==2 else 4),50)
		tab.size = tab.custom_minimum_size

func route_card(parent: Node, location: int, dimensions: Vector2) -> Panel:
	var definition: Dictionary = model.balance["locations"][location]
	var owned: bool = model.profile["locations"].has(location)
	var frame := slab(parent,Vector2.ZERO,dimensions,STONE_SHADE,STONE_LIP,5)
	var inner := dimensions-Vector2(0,5)
	var preview := LevelPreview.new()
	preview.world = game.world
	preview.route_location = location
	preview.size = inner
	preview.material = rounded_material(inner,10)
	preview.mouse_filter = Control.MOUSE_FILTER_IGNORE
	frame.add_child(preview)
	var shade := TextureRect.new()
	var gradient := Gradient.new()
	gradient.colors = PackedColorArray([Color("1f2b3500"),Color("1f2b35d8")])
	gradient.offsets = PackedFloat32Array([.5,1])
	var texture := GradientTexture2D.new()
	texture.gradient = gradient
	texture.fill_to = Vector2(0,1)
	shade.texture = texture
	shade.size = inner
	shade.material = rounded_material(inner,10)
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	frame.add_child(shade)
	var tag := slab(frame,Vector2(inner.x-104,16),Vector2(88,34),Color(SLATE,.88),SLATE_LIP,3)
	text(tag,"%d м" % (int(definition["height_units"])*10),Vector2(0,4),Vector2(88,24),16,STONE,"display").horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	if not owned:
		# A locked route stays visible but is clearly veiled.
		var veil := ColorRect.new()
		veil.color = Color(SLATE,.32)
		veil.size = inner
		veil.material = rounded_material(inner,10)
		veil.mouse_filter = Control.MOUSE_FILTER_IGNORE
		frame.add_child(veil)
		var lock := slab(frame,Vector2(16,16),Vector2(118,34),Color(SLATE,.88),SLATE_LIP,3)
		symbol(lock,14,Vector2(8,5),Vector2(24,24),STONE)
		text(lock,"Закрыто",Vector2(36,6),Vector2(78,22),14,STONE,"strong")
	else:
		var acts: Array = LevelCatalog.level(location).get("acts",[])
		var route_tag := slab(frame,Vector2(16,16),Vector2(82,34),Color(SLATE,.88),SLATE_LIP,3)
		text(route_tag,"%d акта" % int(acts.size()),Vector2(0,6),Vector2(82,22),14,STONE,"strong").horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	text(frame,str(definition["name"]),Vector2(22,inner.y-94),Vector2(inner.x-44,48),36,STONE,"display")
	var total: int = model.balance["locations"].size()
	# Act names wrap to a second line before the route pager.
	var pager_left := inner.x-22-(total-1)*18-6
	paragraph(frame," · ".join(LevelCatalog.act_names(location)),Vector2(23,inner.y-46),Vector2(pager_left-10-23,40),15,Color("e3e8ea"))
	for index in range(total):
		var center := Vector2(inner.x-22-(total-1-index)*18,inner.y-34)
		var points := PackedVector2Array([center+Vector2(0,-6),center+Vector2(6,0),center+Vector2(0,6),center+Vector2(-6,0)])
		var marker := Polygon2D.new()
		marker.polygon = points
		marker.color = HOLD if index==location else Color(STONE,.45)
		frame.add_child(marker)
	return frame

func build_expedition() -> void:
	var active: bool = not model.profile["active"].is_empty()
	# Actions sit in the thumb zone above the section bar: mode, start and
	# one secondary action. Info (card, route, acts) flows from the top.
	const ACTIONS := 44.0+10.0+64.0+10.0+52.0
	const ROUTE := 32.0+ROUTE_PANEL
	var card_y := 90.0 if landscape else 78.0
	var card_w := 620.0 if landscape else 484.0
	# Route art is framed 4:3; the lip adds 5 below the picture.
	var card_h := roundf(card_w*.75)+5.0
	var floor_y := size.y-82.0-16.0
	if not landscape and card_y+card_h+ROUTE+ACTIONS>floor_y:
		# Short screens keep the 4:3 frame and narrow the card instead.
		card_h = maxf(200.0,floor_y-ACTIONS-ROUTE-card_y)
		card_w = (card_h-5.0)/.75
	var card_x := 28.0 if landscape else (size.x-card_w)*.5
	build_card_carousel(Vector2(card_x,card_y),Vector2(card_w,card_h))
	var x := 680.0 if landscape else 28.0
	var width := 372.0 if landscape else 484.0
	var panel_y := card_y+card_h+16.0
	var bottom := floor_y
	if landscape:
		title(self,"Попытка ждёт" if active else "Пора наверх",Vector2(x,card_y),width,32)
		paragraph(self,"Продолжишь с того же зацепа." if active else "Брось крюк, раскачайся и лови следующую опору.",Vector2(x,card_y+46),Vector2(width,44),15)
		panel_y = card_y+104.0
		bottom = card_y+card_h-5.0
	var mode_y := bottom-ACTIONS
	# One stone panel under the card: the route bar, and on taller screens the
	# acts of the shown route. What height is left becomes two equal gaps.
	var panel_h := ROUTE_PANEL
	acts_anchor = Rect2()
	if not landscape:
		var card_bottom := card_y+card_h
		var spare := mode_y-card_bottom-32.0-ROUTE_PANEL
		if spare>=ACTS_HEIGHT:
			var acts_h := minf(spare,ACTS_HEIGHT_MAX)
			acts_anchor = Rect2(16,ROUTE_PANEL,width-32,acts_h-10)
			panel_h += acts_h
			spare -= acts_h
		panel_y = card_bottom+16.0+maxf(0.0,spare)*.5
	route_panel = slab(self,Vector2(x,panel_y),Vector2(width,panel_h))
	var wins := int(model.profile["wins"])
	route_line = route(route_panel,Vector2(16,8),width-32,-1.0,false,"Вершин покорено: %d" % wins if wins>0 else "Вершина ещё не покорена")
	update_route_line()
	# The endless mode is not open yet: its button answers with a "Скоро" note.
	game.lobby_endless = false
	var endless := action(self,"∞",Vector2(x+width-104,mode_y),Vector2(104,44),_endless_soon,"secondary")
	endless.tooltip_text = "Бесконечный режим: скоро"
	endless.add_theme_font_size_override("font_size",22)
	endless.add_theme_color_override("font_color",INK_FAINT)
	endless.alignment = HORIZONTAL_ALIGNMENT_LEFT
	endless_badge = soon_tag(endless,Vector2(42,13),54)
	location_anchor = Rect2(x,mode_y,width,0)
	build_location_actions(self)
	if active:
		var finish := action(self,"Завершить забег",Vector2(x,mode_y+128),Vector2(width,52),game.finish_saved_run)
		finish.tooltip_text = "Завершить сохранённую попытку и оформить награду за текущий прогресс."
	else:
		var practice := action(self,"Тренировка: 16 зацепов",Vector2(x,mode_y+128),Vector2(width,52),game.start_practice)
		practice.tooltip_text = "Короткий маршрут с базовым снаряжением. Кошелёк не меняется."

# Route panel: the bar with its caption; acts rows extend it downwards.
const ROUTE_PANEL := 84.0
const ACTS_HEIGHT := 140.0
const ACTS_HEIGHT_MAX := 210.0

# The route bar keeps its node across route switches; only its summit
# changes, so it never blinks.
func update_route_line() -> void:
	if not is_instance_valid(route_line): return
	route_line.summit = float(model.balance["locations"][game.lobby_location]["height_units"])*10
	route_line.record = model.record(game.lobby_location,"summit")
	route_line.queue_redraw()

# The three acts of the shown route in climbing order with their heights.
# An act is ticked once the route's record passes its upper edge, so a climb
# that reached the second act ticks only the first; a conquered route ticks
# them all.
func build_acts() -> Control:
	var rows := Control.new()
	rows.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rows.position = acts_anchor.position
	rows.size = acts_anchor.size
	route_panel.add_child(rows)
	var spans: Array = LevelCatalog.act_spans(game.lobby_location)
	var names: Array = LevelCatalog.act_names(game.lobby_location)
	var cleared: bool = model.profile["cleared_locations"].has(game.lobby_location)
	var record := model.record(game.lobby_location,"summit")
	var row_h := acts_anchor.size.y/maxf(1,spans.size())
	rule_line(rows,Vector2(0,0),acts_anchor.size.x)
	for index in range(spans.size()):
		var span: Dictionary = spans[index]
		var row_y := index*row_h
		var passed: bool = cleared or record>=float(span["y_end"])*10.0-.5
		var badge := slab(rows,Vector2(0,row_y+(row_h-30)*.5),Vector2(30,30),MOSS if passed else SLATE,SLATE_LIP,3)
		text(badge,"✓" if passed else str(index+1),Vector2(0,3),Vector2(30,22),15,STONE,"display").horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		text(rows,str(names[index]),Vector2(42,row_y+(row_h-22)*.5),Vector2(acts_anchor.size.x-160,22),16,INK,"strong")
		var heights := text(rows,"%d–%d м" % [int(span["y_start"])*10,int(span["y_end"])*10],Vector2(acts_anchor.size.x-110,row_y+(row_h-20)*.5),Vector2(110,20),13,INK_SOFT)
		heights.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		if index<spans.size()-1: rule_line(rows,Vector2(42,row_y+row_h-1),acts_anchor.size.x-42)
	return rows

func rule_line(parent: Node, at: Vector2, width: float) -> void:
	var line := ColorRect.new()
	line.color = Color(STONE_LIP,.5)
	line.position = at
	line.size = Vector2(width,1)
	line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(line)

# The start action and the acts panel: the only parts of the body that
# change with the shown route.
func build_location_actions(parent: Node) -> void:
	for node in location_nodes: _free(node)
	location_nodes = []
	var active: bool = not model.profile["active"].is_empty()
	var owned: bool = model.profile["locations"].has(game.lobby_location)
	var x := location_anchor.position.x
	var mode_y := location_anchor.position.y
	var width := location_anchor.size.x
	if acts_anchor.size.y>0 and is_instance_valid(route_panel): location_nodes.append(build_acts())
	# The three prepared routes of the shown expedition.
	var picker := Control.new()
	picker.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(picker)
	location_nodes.append(picker)
	var routes := LevelCatalog.routes(game.lobby_location)
	var names: Array = []
	for index in range(routes.size()): names.append("Маршрут %d" % (index+1))
	var shown_location: int = game.lobby_location
	var route_buttons := segmented(picker,Vector2(x,mode_y),width-114,names,model.route_choice(shown_location),func(index: int): _choose_route(shown_location,index),44)
	for index in range(route_buttons.size()):
		route_buttons[index].disabled = active or not owned
		route_buttons[index].add_theme_font_size_override("font_size",14)
		route_buttons[index].tooltip_text = "%s — %s" % [routes[index]["name"],routes[index]["hint"]]
	update_route_caption()
	# A locked route says on the button itself what it still needs; the
	# button opens it as soon as all of it is there.
	var ready: bool = model.location_ready(game.lobby_location)
	var unlock: Dictionary = model.location_unlock(game.lobby_location)
	var cost_parts: Array = []
	if unlock.has("gold"): cost_parts.append("%d золота" % int(unlock["gold"]))
	if unlock.has("diamonds"): cost_parts.append("%d алм." % int(unlock["diamonds"]))
	var action_text := "Продолжить восхождение" if active else "Начать восхождение" if owned else "Открыть за "+" + ".join(cost_parts) if ready else "Нужно: "+model.location_requirement(game.lobby_location)
	var start := action(parent,action_text,Vector2(x,mode_y+54),Vector2(width,64),game.lobby_action,"primary")
	start_button = start
	start.add_theme_font_size_override("font_size",21 if action_text.length()<26 else 15)
	start.disabled = not active and not owned and not ready
	start.add_theme_color_override("font_disabled_color",INK_SOFT)
	start.tooltip_text = "Нужно: "+model.location_requirement(game.lobby_location) if not owned else ""
	location_nodes.append(start)
	if landscape and owned and not active and acts_anchor.size.y<=0:
		location_nodes.append(paragraph(parent,"Тренировка идёт с базовым снаряжением и не трогает кошелёк.",Vector2(x,mode_y-60),Vector2(width,40),13))

func _choose_route(location: int, index: int) -> void:
	model.set_route_choice(location,index)
	game.request_profile_save()
	update_route_caption()
	game.toast("%s · %s" % [LevelCatalog.route(location,index)["name"],LevelCatalog.route(location,index)["hint"]],2.2,"menu")

# The route bar's caption names the chosen route of the shown expedition.
func update_route_caption() -> void:
	if not is_instance_valid(route_line): return
	var chosen := LevelCatalog.route(game.lobby_location,model.route_choice(game.lobby_location))
	route_line.caption = str(chosen.get("name",""))
	route_line.queue_redraw()

func _endless_soon() -> void:
	wiggle_soon(endless_badge,"Бесконечный режим скоро откроется")

func build_equipment() -> void:
	var active: bool = not model.profile["active"].is_empty()
	title(self,"Снаряжение",Vector2(28,80),300,32)
	# "Сборы" (run profiles, items, stock) is not open yet: its tab answers a
	# tap with a "Скоро" note and the upgrades stay on screen.
	hud.equipment_view = "upgrades"
	var switch: Array[Button] = []
	switch.append_array(segmented(self,Vector2(size.x-28-260,82),260,["Улучшения","Сборы"],0,func(index: int):
		if index==1:
			paint_segments(switch,0)
			_supplies_soon(switch),40))
	switch[1].tooltip_text = "Сборы: скоро"
	switch[1].add_theme_color_override("font_color",INK_FAINT)
	supplies_badge = soon_tag(switch[1].get_parent(),switch[1].position+Vector2(switch[1].size.x-50,-12),46)
	paragraph(self,"Заверши попытку, чтобы улучшать снаряжение." if active else "Уровни 3–5 открываются актами, вершиной или контрактами.",Vector2(29,126),Vector2(size.x-56,22),13)
	var order := [GameModel.THROW,0,1,2,3,4,5,GameModel.SLOWMO]
	var columns := 2 if landscape else 1
	var row_width := 504.0 if landscape else 484.0
	var row_height := 84.0 if landscape else (70.0 if size.y < 950.0 else 80.0)
	var row_gap := 8.0 if (landscape or size.y >= 950.0) else 4.0
	var base_y := 160.0 if (landscape or size.y >= 950.0) else 148.0
	var per_column := 4 if landscape else order.size()
	for index in range(order.size()):
		var column := index/per_column
		var row := index%per_column
		build_upgrade(order[index],Vector2(28+column*(row_width+16),base_y+row*(row_height+row_gap)),Vector2(row_width,row_height),active)

func _supplies_soon(switch: Array[Button]) -> void:
	# The thumb slid over on the tap; it returns to "Улучшения".
	for node in switch[0].get_parent().get_children():
		if node is Panel and node.has_meta("index"):
			node.set_meta("index",0)
			node.create_tween().tween_property(node,"position:x",switch[0].position.x,.22).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	wiggle_soon(supplies_badge,"Раздел «Сборы» скоро откроется")

func effect_text(kind: int, at_level: int) -> String:
	var i := clampi(at_level-1,0,model.max_level(kind)-1)
	var balance: Dictionary = model.balance
	match kind:
		GameModel.ROPE: return "%d%% дальности" % roundi(float(balance["rope_lengths"][i])/float(balance["rope_lengths"][0])*100.0)
		GameModel.IMPULSE: return "+%d%%" % roundi((float(balance["impulse_factors"][i])-1)*100)
		GameModel.HOOKS: return GameModel.HOOK_NAMES[i]
		GameModel.BAG:
			var slots := int(balance["capacities"][i])
			return "%d %s" % [slots,"слот" if slots==1 else "слота" if slots<5 else "слотов"]+(" +1" if int(balance["special_slots"][i])>0 else "")
		GameModel.MAGNET:
			if i==0: return "касание"
			if float(balance["magnet_radii"][i])<=0: return "монеты %d м" % roundi(float(balance["magnet_coin_radii"][i])*10)
			return "%d / %d м" % [roundi(float(balance["magnet_coin_radii"][i])*10),roundi(float(balance["magnet_radii"][i])*10)]
		GameModel.RECOVERY: return "%d%%" % int(balance["recovery_percents"][i])
		GameModel.SLOWMO: return seconds_text(float(balance["slowmo_seconds"][i]))
	return "%d%% скорости" % roundi(float(balance["throw_speeds"][i])/float(balance["throw_speeds"][0])*100.0)

func build_upgrade(kind: int, at: Vector2, dimensions: Vector2, active: bool) -> void:
	var frame := slab(self,at,dimensions)
	var level := model.level(kind)
	var maximum := level>=model.max_level(kind)
	var locked := not maximum and not model.upgrade_available(kind)
	var can_buy := not active and not locked and not maximum and int(model.profile["gold"])>=model.cost(kind)
	var affordable := int(model.profile["gold"])>=model.cost(kind)
	var short_names := ["Длина каната","Импульс","Крюки","Рюкзак","Магнит","Защита добычи","Сила броска","Замедление"]
	var middle := (dimensions.y-4)*.5
	symbol(frame,19 if kind==GameModel.SLOWMO else kind,Vector2(16,middle-20),Vector2(40,40),INK)
	text(frame,short_names[kind],Vector2(70,middle-35),Vector2(dimensions.x-240,22),16,INK,"strong")
	# Where the next level matters: an act or situation of the expeditions.
	var use := text(frame,model.upgrade_use(kind,level if maximum else level+1),Vector2(70,middle-15),Vector2(dimensions.x-240,18),12,INK_SOFT)
	use.name = "Use"
	var current := text(frame,effect_text(kind,level),Vector2(70,middle+1),Vector2(dimensions.x-240,22),17,INK,"display")
	if not maximum:
		var shown := current.get_theme_font("font").get_string_size(current.text,HORIZONTAL_ALIGNMENT_LEFT,-1,17).x
		text(frame,"→ "+effect_text(kind,level+1),Vector2(70+shown+8,middle+3),Vector2(maxf(40,dimensions.x-250-shown),20),14,INK_SOFT)
	var meter := UpgradeMeter.new()
	meter.filled = level
	meter.total = model.max_level(kind)
	meter.unlocked = model.max_level(kind) if kind==GameModel.HOOKS else mini(model.max_level(kind),model.unlocked_upgrade_level())
	meter.position = Vector2(70,middle+28)
	meter.size = Vector2(minf(150,dimensions.x-240),6)
	meter.mouse_filter = Control.MOUSE_FILTER_IGNORE
	frame.add_child(meter)
	# Level reads next to the meter; the last step says so in hold yellow.
	var level_label := text(frame,"Макс. ур. %d" % level if maximum else "Ур. %d/%d" % [level,model.max_level(kind)],Vector2(70+meter.size.x+8,middle+20),Vector2(90,20),12,COIN if maximum else INK_SOFT,"strong")
	level_label.name = "Level"
	var value := "Максимум" if maximum else "После попытки" if active else model.gate_text(level+1) if locked else "Улучшить"
	var button_size := Vector2(150,dimensions.y-24)
	var purchase := action(frame,value,Vector2(dimensions.x-button_size.x-12,middle-button_size.y*.5),button_size,hud._buy_upgrade.bind(kind),"buy" if can_buy else "secondary")
	purchase.add_theme_font_size_override("font_size",15 if value.length()<16 else 12)
	purchase.disabled = not can_buy
	if value=="Улучшить":
		# Price sits under the verb inside the hold, so cost and action are one target.
		for state_name in ["normal","hover","pressed","disabled"]:
			var styled := purchase.get_theme_stylebox(state_name).duplicate() as StyleBoxFlat
			styled.content_margin_bottom += 22
			purchase.add_theme_stylebox_override(state_name,styled)
		var price := Control.new()
		price.mouse_filter = Control.MOUSE_FILTER_IGNORE
		price.position = Vector2(0,button_size.y-34)
		purchase.add_child(price)
		var amount := str(model.cost(kind))
		var width: float = hud.heading_font.get_string_size(amount,HORIZONTAL_ALIGNMENT_LEFT,-1,16).x+24
		var left := (button_size.x-width)*.5
		symbol(price,12,Vector2(left,2),Vector2(19,19),INK if can_buy else COIN if affordable else INK_FAINT)
		text(price,amount,Vector2(left+24,0),Vector2(width,22),16,INK if can_buy or affordable else DANGER,"display")
	frame.tooltip_text = model.upgrade_text(kind)+("\nДалее: "+model.upgrade_text(kind,level+1)+"\nПолезно: "+model.upgrade_use(kind,level+1) if not maximum else "\nМаксимальный уровень")
	frame.mouse_filter = Control.MOUSE_FILTER_PASS
	if hud.upgrade_flash==kind:
		hud.upgrade_flash = -1
		celebrate_upgrade(frame,dimensions,level,maximum)

# --- Preparation: run profiles, active items, stock and progress ----------------------

func build_supplies(active: bool) -> void:
	var column_width := 504.0 if landscape else 484.0
	paragraph(self,"Выбери стиль и предметы до старта." if not active else "Попытка идёт: сбор изменится после её завершения.",Vector2(29,130),Vector2(size.x-56,20),13)
	var left := Vector2(28,162)
	var right := Vector2(28+column_width+16,162) if landscape else Vector2(28,left.y+304)
	# A preparation is a readable play style. It still drives the existing
	# rope/impulse/throw mechanics, but the player chooses one coherent intent.
	var profiles := slab(self,left,Vector2(column_width,292))
	text(profiles,"Стиль восхождения",Vector2(20,12),Vector2(300,24),17,INK,"display")
	var row_y := 40.0
	var owned: Array = []
	for index in range(model.level(GameModel.HOOKS)): owned.append(GameModel.HOOK_NAMES[index].replace("2 ","2×"))
	text(profiles,"Крюки",Vector2(20,row_y+11),Vector2(110,22),14,INK_SOFT,"strong")
	var hooks := segmented(profiles,Vector2(120,row_y),column_width-140,owned,model.hook_config()-1,func(index: int): _choose("hook",str(index+1)),40)
	for index in range(hooks.size()):
		var hook_count := int(model.balance["hook_counts"][index])
		var hook_tips := int(model.balance["hook_tips"][index])
		var tips_word := "наконечник" if hook_tips==1 else "наконечника" if hook_tips<5 else "наконечников"
		hooks[index].tooltip_text = "%d крюк%s · %d %s" % [hook_count,"а" if hook_count==2 else "",hook_tips,tips_word]
	for button in hooks:
		button.disabled = active
		button.add_theme_font_size_override("font_size",12 if owned.size()>2 else 14)
	row_y += 48
	text(profiles,"Профиль",Vector2(20,row_y+11),Vector2(110,22),14,INK_SOFT,"strong")
	var prep_keys := model.prep_profile_keys()
	var prep_names: Array[String] = []
	for profile_id in prep_keys: prep_names.append(model.prep_profile_name(profile_id))
	if model.prep_profiles_unlocked():
		var prep_buttons := segmented(profiles,Vector2(120,row_y),column_width-140,prep_names,prep_keys.find(model.prep_profile()),func(index: int): _choose_prep(prep_keys[index]),40)
		for index in range(prep_buttons.size()): prep_buttons[index].tooltip_text = model.prep_profile_hint(prep_keys[index])
	else:
		text(profiles,"Откроется после 3-го уровня каната, импульса и броска",Vector2(120,row_y+11),Vector2(column_width-140,22),12,INK_FAINT)
	row_y += 48
	paragraph(profiles,model.prep_profile_hint(),Vector2(120,row_y-4),Vector2(column_width-140,34),12,INK_SOFT)
	row_y += 38
	text(profiles,"Цель сбора",Vector2(20,row_y+11),Vector2(110,22),14,INK_SOFT,"strong")
	var magnet: Dictionary = model.balance["specializations"]["magnet"]
	if not model.spec_unlocked("magnet"):
		text(profiles,"Откроется на 5-м уровне магнита",Vector2(120,row_y+11),Vector2(column_width-140,22),12,INK_FAINT)
		paragraph(profiles,"До этого находки подбираются только в радиусе касания.",Vector2(120,row_y+42),Vector2(column_width-140,30),12,INK_SOFT)
	else:
		var magnet_keys: Array = magnet["options"].keys()
		var magnet_names: Array[String] = []
		for key in magnet_keys: magnet_names.append(str(magnet["options"][key]["name"]))
		var magnet_buttons := segmented(profiles,Vector2(120,row_y),column_width-140,magnet_names,magnet_keys.find(model.choice("magnet")),func(index: int): _choose("magnet",str(magnet_keys[index])),40)
		for index in range(magnet_buttons.size()): magnet_buttons[index].tooltip_text = str(magnet["options"][magnet_keys[index]].get("hint",""))
		paragraph(profiles,str(magnet["options"][model.choice("magnet")].get("hint","")),Vector2(120,row_y+42),Vector2(column_width-140,30),12,INK_SOFT)
	# Active items: everything in stock goes into the next run, one charge of
	# each, bought with gold or made from materials. Diamonds never buy them.
	var items := slab(self,right,Vector2(column_width,262))
	text(items,"Активные предметы",Vector2(20,12),Vector2(260,24),17,INK,"display")
	text(items,"Купленное уходит в следующий забег: по одному каждого",Vector2(20,38),Vector2(column_width-40,20),12,INK_SOFT)
	var item_y := 62.0
	for definition in ItemCatalog.consumables():
		var id := str(definition["id"])
		text(items,str(definition["name"]),Vector2(20,item_y),Vector2(column_width-226,20),14,INK,"strong").tooltip_text = str(definition.get("hint",""))
		var recipe: Array = []
		for material_id in definition["recipe_materials"].keys(): recipe.append("%d %s" % [int(definition["recipe_materials"][material_id]),ItemCatalog.material_name(material_id).to_lower()])
		text(items,"%d/%d · %s" % [model.stock(id),model.stock_max(),str(definition.get("hint",""))],Vector2(20,item_y+20),Vector2(column_width-226,18),12,INK_SOFT)
		var buy := action(items,"%d з." % int(definition["price_gold"]),Vector2(column_width-202,item_y),Vector2(86,40),_buy_item.bind(id),"secondary")
		buy.add_theme_font_size_override("font_size",13)
		buy.disabled = active or model.stock(id)>=model.stock_max() or int(model.profile["gold"])<int(definition["price_gold"])
		buy.tooltip_text = "Купить за золото"
		var craft := action(items,"Собрать",Vector2(column_width-110,item_y),Vector2(90,40),_craft_item.bind(id),"secondary")
		craft.add_theme_font_size_override("font_size",13)
		craft.disabled = active or model.stock(id)>=model.stock_max() or not model.can_craft(id)
		craft.tooltip_text = "Из материалов: "+", ".join(recipe)
		item_y += 48
	# Materials and long-term progress.
	var progress_at := right+Vector2(0,274)
	var progress := slab(self,progress_at,Vector2(column_width,120 if landscape else 100))
	var wallet_parts: Array = []
	for material_id in model.balance["materials"].keys(): wallet_parts.append("%s %d" % [ItemCatalog.material_name(material_id),model.materials(material_id)])
	paragraph(progress,"Материалы: "+" · ".join(wallet_parts),Vector2(20,10),Vector2(column_width-40,40),12,INK)
	var sets := int(model.profile["unlocked_sets"].size())
	text(progress,"Комплекты %d/%d · ориентиры %d · контракты %d" % [sets,model.balance["sets"].size(),model.profile["landmarks"].size(),model.profile["completed_contracts"].size()],Vector2(20,58),Vector2(column_width-40,20),12,INK_SOFT)

func _choose(track: String, option: String) -> void:
	var message := model.set_choice(track,option)
	if track=="hook" and is_instance_valid(game.explorer):
		game.explorer.set_hook_configuration(model.hook_tips(),model.hook_count())
	hud.show_menu_soon()
	game.toast(message)

func _choose_prep(profile_id: String) -> void:
	var message := model.set_prep_profile(profile_id)
	hud.show_menu_soon()
	game.toast(message)

func _toggle_slot(id: String) -> void:
	var loadout: Array = model.profile["active_loadout"]
	var message := ""
	if loadout.has(id): message = model.set_loadout(loadout.find(id),"")
	else:
		var slot := loadout.find("")
		message = model.set_loadout(slot if slot>=0 else loadout.size()-1,id)
	hud.show_menu()
	game.toast(message)

func _buy_item(id: String) -> void:
	var message := model.buy_consumable(id)
	hud.show_menu()
	game.toast(message)

func _craft_item(id: String) -> void:
	var message := model.craft_consumable(id)
	hud.show_menu()
	game.toast(message)

func celebrate_upgrade(frame: Control, dimensions: Vector2, level: int, maximum: bool) -> void:
	# Purchase confirmation: the row glows hold-yellow, bumps, and a burst and
	# the new level rise from it.
	var glow := ColorRect.new()
	glow.color = Color(HOLD,.55)
	glow.size = dimensions-Vector2(0,4)
	glow.material = rounded_material(glow.size,10)
	glow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	frame.add_child(glow)
	create_tween().tween_property(glow,"modulate:a",0.0,.7).set_trans(Tween.TRANS_SINE).set_delay(.12)
	hud.pulse(frame,.04)
	var burst := PlayGauges.Burst.new()
	burst.color = HOLD
	burst.position = Vector2(dimensions.x-87,dimensions.y*.5)
	frame.add_child(burst)
	var rise := PlayGauges.FloatText.new()
	rise.text = "Максимум!" if maximum else "Ур. %d" % level
	rise.font = hud.heading_font
	rise.color = COIN
	rise.position = Vector2(dimensions.x-87,dimensions.y*.5-16)
	frame.add_child(rise)

static func seconds_text(seconds: float) -> String:
	return (str(snappedf(seconds,.01))+" с").replace(".",",")

func settings_switch(parent: Node, title_text: String, subtitle: String, at: Vector2, width: float, enabled: bool, callback: Callable) -> void:
	text(parent,title_text,at+Vector2(0,0 if not subtitle.is_empty() else 10),Vector2(width-104,24),16,INK,"strong")
	if not subtitle.is_empty(): text(parent,subtitle,at+Vector2(0,24),Vector2(width-120,20),13,INK_SOFT)
	var left := at.x+width-96
	var track := slab(parent,Vector2(left,at.y),Vector2(96,44),Color(MOSS,.35) if enabled else STONE_SHADE,Color.TRANSPARENT,0)
	# A switch: the raised block slides right and turns slate when the option
	# is on. It flips in place; the page is not rebuilt.
	var toggle := action(parent,"Вкл" if enabled else "Выкл",Vector2(left+(36 if enabled else 4),at.y+4),Vector2(56,36),Callable(),"selected" if enabled else "secondary")
	toggle.set_meta("on",enabled)
	toggle.pressed.connect(_flip_switch.bind(toggle,track,left,callback))
	_tight_knob(toggle)

# The knob is narrow: thin side padding keeps "Выкл" whole.
func _tight_knob(toggle: Button) -> void:
	toggle.add_theme_font_size_override("font_size",15)
	for state_name in ["normal","hover","pressed","disabled"]:
		var box := toggle.get_theme_stylebox(state_name).duplicate() as StyleBoxFlat
		box.content_margin_left = 2
		box.content_margin_right = 2
		toggle.add_theme_stylebox_override(state_name,box)

func _flip_switch(toggle: Button, track: Panel, left: float, callback: Callable) -> void:
	var on: bool = not bool(toggle.get_meta("on",false))
	toggle.set_meta("on",on)
	toggle.create_tween().tween_property(toggle,"position:x",left+(36 if on else 4),.22).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	track.add_theme_stylebox_override("panel",hud.slab_style(Color(MOSS,.35) if on else STONE_SHADE,Color.TRANSPARENT,0))
	toggle.text = "Вкл" if on else "Выкл"
	hud.skin_button(toggle,"selected" if on else "secondary")
	_tight_knob(toggle)
	callback.call()

func section(parent: Node, value: String) -> void:
	text(parent,value,Vector2(20,14),Vector2(400,24),17,INK,"display")

func build_settings() -> void:
	title(self,"Настройки",Vector2(28,80),500,32)
	var column_width := 500.0 if landscape else 484.0
	var compact := landscape or size.y < 950.0
	var graphics_h := 186.0 if compact else 198.0
	var graphics := slab(self,Vector2(28,126 if compact else 138),Vector2(column_width,graphics_h))
	section(graphics,"Графика")
	var control_x := 150.0
	var control_width := column_width-control_x-20
	text(graphics,"Качество",Vector2(20,54 if compact else 58),Vector2(140,22),15,INK_SOFT)
	var quality := str(model.profile.get("graphics_quality","balanced"))
	var keys := ["high","balanced","battery"]
	segmented(graphics,Vector2(control_x,44 if compact else 48),control_width,["Высокая","Баланс","Экономия"],keys.find(quality),func(index: int): game.set_graphics_quality(keys[index]),40)
	text(graphics,"Цены находок",Vector2(20,98 if compact else 106),Vector2(140,22),15,INK_SOFT)
	var prices_always := str(model.profile.get("loot_prices","near"))=="always"
	var modes := ["near","always"]
	var prices := segmented(graphics,Vector2(control_x,88 if compact else 96),control_width,["Рядом","Всегда"],1 if prices_always else 0,func(index: int): hud.set_loot_prices(modes[index]),40)
	prices[0].tooltip_text = "Цена видна у находок рядом и на линии прицела"
	# Camera scale: 100 % is the original framing. Larger values only narrow
	# the picture; the fall edge and route rules stay the same.
	text(graphics,"Масштаб",Vector2(20,142 if compact else 154),Vector2(140,22),15,INK_SOFT)
	var zoom_levels := model.camera_zoom_levels()
	var zoom_names: Array = []
	for zoom in zoom_levels: zoom_names.append("%d%%" % roundi(float(zoom)*100))
	var zoom_buttons := segmented(graphics,Vector2(control_x,132 if compact else 144),control_width,zoom_names,zoom_levels.find(model.camera_zoom()),func(index: int): game.set_camera_zoom(float(zoom_levels[index])),40)
	for button in zoom_buttons: button.tooltip_text = "Крупнее герой и опоры. Граница падения не меняется."
	# Short portrait screens set the four switches as a 2×2 grid without
	# subtitles, so the controls block keeps its room.
	var switches := [["Музыка","Мелодии лагеря и экспедиций","music",hud.toggle_music],["Звук","Бросок, зацеп и находки","sound",hud.toggle_sound],
		["Вибрация","Короткий отклик при зацепе","vibration",hud.toggle_vibration],["Подсказки","Сообщения внизу экрана","notifications",hud.toggle_notifications]]
	var feedback_h := 150.0 if compact else 248.0
	var feedback_y := (126 + graphics_h + 12) if compact else 350.0
	var feedback := slab(self,Vector2(28,feedback_y),Vector2(column_width,feedback_h))
	section(feedback,"Звук и отклик")
	for index in range(switches.size()):
		var entry: Array = switches[index]
		var on := bool(model.profile.get(str(entry[2]),true))
		if compact:
			var half := (column_width-52)*.5
			settings_switch(feedback,str(entry[0]),"",Vector2(20+(index%2)*(half+12),46+(index/2)*50),half,on,entry[3])
		else:
			settings_switch(feedback,str(entry[0]),str(entry[1]),Vector2(20,50+index*48),column_width-40,on,entry[3])
	var help_y := (feedback_y + feedback_h + 12) if compact else 612.0
	var help_h := minf(size.y - 90.0 - help_y, 302.0) if not landscape else 412.0
	var help_at := Vector2(552,138) if landscape else Vector2(28,help_y)
	var help_size := Vector2(500,412) if landscape else Vector2(484,help_h)
	var help := slab(self,help_at,help_size)
	section(help,"Управление")
	var instructions := [["Брось крюк","Коснись где удобно, потяни как стик и отпусти."],["Раскачайся","На канате веди палец влево или вправо."],["Выбери длину","Держи строго вверх или вниз 0,28 секунды."],["Отцепись","Подними палец. Затем снова прицелься."]]
	if not hud.touch_controls_hint:
		instructions = [["Брось крюк","Зажми ЛКМ, прицелься и отпусти."],["Раскачайся","A / D или стрелки."],["Выбери длину","W / S или колесо мыши."],["Отцепись","Пробел, затем целься снова."]]
	var step := (help_size.y-54)/instructions.size()
	for index in range(instructions.size()):
		var row_y := 46+index*step
		var badge := slab(help,Vector2(20,row_y+2),Vector2(32,32),SLATE,SLATE_LIP,3)
		text(badge,str(index+1),Vector2(0,2),Vector2(32,26),16,STONE,"display").horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		text(help,instructions[index][0],Vector2(64,row_y),Vector2(help_size.x-84,20),15,INK,"strong")
		paragraph(help,instructions[index][1],Vector2(64,row_y+20),Vector2(help_size.x-84,36),12)
	var version := text(help,"Версия "+GameModel.BUILD_VERSION,Vector2(help_size.x-180,18),Vector2(160,20),12,INK_SOFT)
	version.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT

func _notification(what: int) -> void:
	# Kept pages live off the tree; they go with the lobby.
	if what==NOTIFICATION_PREDELETE:
		for tab in page_cache.keys():
			if is_instance_valid(page_cache[tab]): page_cache[tab].free()
