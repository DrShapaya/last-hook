class_name MountainWorld
extends Node3D

const GENERATION_VERSION := 10
const COLORS := [Color("e3b95e"),Color("b97bed"),Color("61d6a5"),Color("88dafa"),Color("ed99da")]
var layout := MountainLayout.new()
var visuals: MountainVisuals
var visuals_enabled := true
var anchors: Array[Dictionary] = []
var main_route: Array[int] = []
var route_edges: Array[Vector2i] = []
var obstacles: Array[Dictionary] = []
var finds: Array[Dictionary] = []
var ledges: Array[Dictionary] = []
var chunks: Dictionary = {}
var materials: Dictionary = {}
var seed_value := 0
var location := 0
var generation_version := GENERATION_VERSION
var generated_height := 0.0
var ghost_texture: ImageTexture
var sky_backdrop: ProceduralSkyBackdrop
var camera_center := Vector2(0,7)
var show_loot_prices := true

static func generation_version_for(biome: int) -> int:
	return GENERATION_VERSION if biome==0 else 4

func setup(world_seed: int, world_location: int, saved_version: int = 0, practice: bool = false) -> void:
	seed_value = world_seed
	location = world_location
	generation_version = saved_version if saved_version>0 else generation_version_for(location)
	if generation_version>=10 and location==0: layout = EncounterLayout.new()
	if practice: layout = PracticeLayout.new()
	layout.gentle_intro = generation_version>=7
	layout.sparse_route = generation_version>=8
	layout.safe_routes = generation_version>=9
	if location!=0: layout = LegacyMountainLayout.new()
	layout.setup(world_seed,world_location)
	anchors = layout.anchors
	main_route = layout.main_route
	obstacles = layout.obstacles
	finds = layout.finds
	ledges = layout.ledges
	visuals = MountainVisuals.new(self,layout)
	if location!=0: visuals = LegacyMountainVisuals.new(self,layout)
	if visuals_enabled and location==0: _build_sky()

func seeded_rng(index: int, stream: int) -> RandomNumberGenerator:
	return layout.rng(index,stream)

func cliff_edge(index: int, side: int) -> float:
	return layout.outer_edge(index*4.0,side)

func outside_mountain(point: Vector2) -> bool:
	return layout.outside(point)

func generate_to(height: float, finite: bool, summit: float = 120) -> void:
	var target := minf(height,summit+6) if finite else height
	layout.generate_to(target,finite,summit)
	route_edges = layout.edges
	generated_height = maxf(generated_height,target)
	# The top chunk changes when the summit is added; refresh it if loaded.
	if layout.summit_added:
		var key := int(floor(summit/24))
		if chunks.has(key): _release_chunk(key)
	if visuals_enabled: update_visibility(camera_center.y,camera_center.x)

func add_anchor(point: Vector2, kind: int, _bush: bool = false, dimensions: Vector2 = Vector2(1.8,.65)) -> void:
	var id := layout._add_anchor(point,kind,dimensions)
	if visuals_enabled:
		var key := int(floor(point.y/24))
		if chunks.has(key): visuals.build_anchor(anchors[id],chunks[key])

func add_obstacle(point: Vector2, dimensions: Vector2) -> void:
	var object := {"pos":point,"dimensions":dimensions}
	obstacles.append(object)
	if visuals_enabled:
		var key := int(floor(point.y/24))
		if chunks.has(key): visuals.build_obstacle(object,chunks[key])

func add_ledge(point: Vector2, width: float) -> void:
	var object := {"left":point.x-width*.5,"right":point.x+width*.5,"top":point.y+.15}
	ledges.append(object)
	if visuals_enabled:
		var key := int(floor(point.y/24))
		if chunks.has(key): visuals.build_ledge(object,chunks[key])

func nearby_anchors(low: float, high: float) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for id in layout.nearby_ids(low,high): result.append(anchors[id])
	return result

func nearby_obstacles(low: float, high: float) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for object in obstacles:
		if object["pos"].y+object["dimensions"].y*.5>=low and object["pos"].y-object["dimensions"].y*.5<=high:
			result.append(object)
	return result

func rope_blocked(from: Vector2, to: Vector2) -> bool:
	return not rope_contact(from,to).is_empty()

func rope_contact(from: Vector2, to: Vector2) -> Dictionary:
	var best: Dictionary = {}
	for obstacle in nearby_obstacles(minf(from.y,to.y)-.1,maxf(from.y,to.y)+.1):
		var hit := SolidGeometry.contour_cast(from,to,obstacle,0)
		if not hit.is_empty() and (best.is_empty() or hit["fraction"]<best["fraction"]): best = hit
	return best

func update_rope_path(sim: RopeSim) -> bool:
	if not sim.attached: return true
	const ROPE_CLEARANCE := .16
	var root := sim.anchor
	for point in sim.rope_pivots:
		if rope_blocked(root,point):
			sim.rope_pivots.clear()
			break
		root = point
	# Unwrap only when the previous fixed point can see the body directly.
	# Keeping the intervening corners until then prevents side-to-side jumps.
	while not sim.rope_pivots.is_empty():
		var previous: Vector2 = sim.anchor if sim.rope_pivots.size()==1 else sim.rope_pivots[-2]
		# Discard temporary corners when the direct route is clear again.
		if rope_blocked(previous,sim.pos): break
		sim.rope_pivots.pop_back()
	for iteration in range(6):
		var pivot := sim.effective_anchor()
		var collision := rope_contact(pivot,sim.pos)
		if collision.is_empty(): return true
		if sim.rope_pivots.size()>=4: return false
		var best := Vector2.INF
		var best_score := INF
		for corner in SolidGeometry.corners(collision["object"],ROPE_CLEARANCE):
			if corner.distance_to(pivot)<.05 or sim.rope_pivots.has(corner): continue
			if rope_blocked(pivot,corner): continue
			if sim.fixed_length()+pivot.distance_to(corner)>sim.length-.4: continue
			var score := pivot.distance_to(corner)+corner.distance_to(sim.pos)
			if score<best_score:
				best = corner
				best_score = score
		if not best.is_finite(): return false
		sim.rope_pivots.append(best)
		sim.request_length(sim.target_length)
	return not rope_blocked(sim.effective_anchor(),sim.pos)

func mat(key: String, color: Color, unlit: bool = true) -> StandardMaterial3D:
	if materials.has(key):
		return materials[key]
	var result := StandardMaterial3D.new()
	result.albedo_color = color
	result.roughness = .93
	if unlit:
		result.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	materials[key] = result
	return result

func box(node_name: String, where: Vector3, dimensions: Vector3, material: Material, parent: Node3D = null) -> MeshInstance3D:
	var mesh := BoxMesh.new()
	mesh.size = dimensions
	var instance := MeshInstance3D.new()
	instance.name = node_name
	instance.mesh = mesh
	instance.material_override = material
	var owner_node: Node3D = self if parent==null else parent
	owner_node.add_child(instance)
	instance.position = owner_node.to_local(where)
	return instance

func sphere(node_name: String, where: Vector3, dimensions: Vector3, material: Material, parent: Node3D = null) -> MeshInstance3D:
	var instance := MeshInstance3D.new()
	var mesh := SphereMesh.new()
	mesh.radius = .5
	mesh.height = 1
	mesh.radial_segments = 8
	mesh.rings = 4
	instance.mesh = mesh
	instance.material_override = material
	(self if parent==null else parent).add_child(instance)
	instance.name = node_name
	instance.position = where if parent==null else parent.to_local(where)
	instance.scale = dimensions
	return instance

static func rectangle_hit(from: Vector2, to: Vector2, center: Vector2, half: Vector2) -> float:
	return RopeSim.hit_polygon(from,to,PackedVector2Array([center-half,center+Vector2(half.x,-half.y),center+half,center+Vector2(-half.x,half.y)]))

func hit_object(from: Vector2, to: Vector2, object: Dictionary, grip: float) -> float:
	var tolerance := .04+maxf(0,grip-.32)
	if object.has("polygon"):
		var polygon := PackedVector2Array()
		var scale_value: Vector2 = Vector2.ONE+Vector2.ONE*tolerance*2/object["dimensions"]
		for p in object["polygon"]: polygon.append(p*scale_value+object["pos"])
		return RopeSim.hit_polygon(from,to,polygon)
	return rectangle_hit(from,to,object["pos"],object["dimensions"]*.5+Vector2.ONE*tolerance)

func cast_hook(from: Vector2, to: Vector2, grip: float, ignore_anchor: int = -1) -> Dictionary:
	var best := 2.0
	var result: Dictionary = {}
	for object in nearby_anchors(minf(from.y,to.y)-2,maxf(from.y,to.y)+2):
		if object["broken"] or int(object["id"])==ignore_anchor:
			continue
		var fraction := hit_object(from,to,object,grip)
		if fraction>=0 and fraction<best:
			best = fraction
			result = {"object":object,"fraction":fraction,"contact":from.lerp(to,fraction)}
	for obstacle in nearby_obstacles(minf(from.y,to.y),maxf(from.y,to.y)):
		var contact := SolidGeometry.contour_cast(from,to,obstacle,grip)
		var fraction: float = contact.get("fraction",-1.0)
		if fraction>=0 and fraction<=best:
			best = fraction
			result = {"blocked":true,"object":obstacle,"fraction":fraction,"contact":from.lerp(to,fraction),"normal":contact["normal"]}
	return result

func move_player(from: Vector2, to: Vector2, velocity: Vector2) -> Dictionary:
	var position_value := from
	var remaining := to-from
	var grounded := false
	var rest := false
	var impact := 0.0
	var contacts: Array[Vector2] = []
	# Convex sweeps use the actual drawn contour expanded by body size.
	# Resolve the remaining motion along each face; never discard the whole
	# frame after a collision or reflect velocity into another solid.
	for iteration in range(6):
		var best: Dictionary = {}
		for obstacle in nearby_obstacles(minf(position_value.y,position_value.y+remaining.y)-1,maxf(position_value.y,position_value.y+remaining.y)+1):
			var hit := SolidGeometry.cast(position_value,position_value+remaining,obstacle,SolidGeometry.BODY_HALF,true)
			if not hit.is_empty() and (best.is_empty() or hit["fraction"]<best["fraction"]):
				best = hit
		if remaining.y<-.000001:
			for ledge in ledges:
				var top: float = ledge["top"]+SolidGeometry.BODY_HALF.y
				if position_value.y<top-.004: continue
				var fraction := (top-position_value.y)/remaining.y
				if fraction<-.001 or fraction>1: continue
				var x := position_value.x+remaining.x*maxf(0,fraction)
				if x<float(ledge["left"])-.24 or x>float(ledge["right"])+.24: continue
				if best.is_empty() or fraction<best["fraction"]:
					best = {"fraction":maxf(0,fraction),"normal":Vector2(0,1),"depth":0.0,"object":{"rest":true}}
		if best.is_empty():
			position_value += remaining
			break
		var normal: Vector2 = best["normal"]
		var fraction: float = best["fraction"]
		position_value += remaining*fraction+normal*(float(best["depth"])+.0001)
		remaining *= 1-fraction
		remaining -= normal*minf(0,remaining.dot(normal))
		impact = maxf(impact,-velocity.dot(normal))
		velocity -= normal*minf(0,velocity.dot(normal))
		contacts.append(normal)
		if normal.y>.6:
			grounded = true
			rest = bool(best["object"].get("rest",false))
	return {"position":position_value,"velocity":velocity,"grounded":grounded,"rest":rest,"impact":impact,"contacts":contacts}

func _build_find(find: Dictionary, parent: Node3D) -> void:
	var holder := Node3D.new()
	parent.add_child(holder)
	var point: Vector2 = find["pos"]
	holder.position = Vector3(point.x,point.y,2.2)
	find["visual"] = holder
	var mesh := box("Предмет",holder.position,Vector3(.28,.38,.26),mat("loot",Color("ffca60")),holder)
	mesh.rotation_degrees.z = 35
	var price := Label3D.new()
	price.text = str(find["item"]["value"])
	price.font_size = 30
	price.pixel_size = .012
	price.outline_size = 9
	price.modulate = Color("ffe5a0")
	price.outline_modulate = Color("233743")
	holder.add_child(price)
	price.position = Vector3(0,.55,.2)
	price.visible = show_loot_prices
	find["price_visual"] = price
	holder.visible = not find.get("picked",false)

func set_loot_prices_visible(show_prices: bool) -> void:
	show_loot_prices = show_prices
	for find in finds:
		if is_instance_valid(find.get("price_visual")):
			find["price_visual"].visible = show_prices

func _build_sky() -> void:
	sky_backdrop = ProceduralSkyBackdrop.new()
	add_child(sky_backdrop)
	sky_backdrop.setup(seed_value)
	sky_backdrop.set_view(camera_center)

func _release_chunk(key: int) -> void:
	for object in nearby_anchors(key*24,(key+1)*24-.001):
		if int(floor(object["pos"].y/24))==key: object["visual"] = null
	for object in obstacles:
		if int(floor(object["pos"].y/24))==key: object["visual"] = null
	for object in finds:
		if int(floor(object["pos"].y/24))==key: object["visual"] = null
	var chunk: Node3D = chunks[key]
	remove_child(chunk)
	chunk.queue_free()
	chunks.erase(key)

func update_visibility(center_y: float, center_x: float = 0) -> void:
	camera_center = Vector2(center_x,center_y)
	if is_instance_valid(sky_backdrop): sky_backdrop.set_view(camera_center)
	if not visuals_enabled: return
	var first := maxi(0,int(floor((center_y-32)/24)))
	var ready_chunk := int(floor((layout.main_point(layout.row).y-2)/24))-1
	if location!=0: ready_chunk = int(ceil(generated_height/24))
	if layout.finite and layout.main_point(layout.row).y>=layout.summit-.8:
		ready_chunk = int(floor(layout.summit/24))
	var last := mini(ready_chunk,int(floor((center_y+32)/24)))
	for key in chunks.keys():
		if key<first or key>last: _release_chunk(key)
	for key in range(first,last+1):
		if chunks.has(key): continue
		var chunk := Node3D.new()
		chunk.name = "Участок_%d" % key
		add_child(chunk)
		chunks[key] = chunk
		visuals.build_chunk(key,chunk)
		for object in nearby_anchors(key*24,(key+1)*24-.001):
			if int(floor(object["pos"].y/24))==key: visuals.build_anchor(object,chunk)
		for object in obstacles:
			if int(floor(object["pos"].y/24))==key: visuals.build_obstacle(object,chunk)
		for object in ledges:
			if int(floor(object["top"]/24))==key: visuals.build_ledge(object,chunk)
		for find in finds:
			if int(floor(find["pos"].y/24))==key: _build_find(find,chunk)
		if layout.summit_added and int(floor(layout.summit/24))==key:
			var p: Vector2 = anchors[main_route[-1]]["pos"]
			box("Флагшток",Vector3(p.x+.8,layout.summit+1,2),Vector3(.08,2,.1),mat("flagpole",Color("d8d8c3")),chunk)
			box("Флаг",Vector3(p.x+1.2,layout.summit+1.7,2),Vector3(.8,.5,.1),mat("flag",Color("e6b64b")),chunk)
	for object in nearby_anchors(center_y-40,center_y+40):
		if is_instance_valid(object.get("visual")): object["visual"].visible = not object["broken"]
	for find in finds:
		if is_instance_valid(find.get("visual")): find["visual"].visible = not find.get("picked",false)
func anchor_by_id(id: int) -> Dictionary:
	return anchors[id] if id>=0 and id<anchors.size() else {}

func revive_plan(safe_id: int, safe_pos: Vector2, maximum: float, contact: Vector2 = Vector2.INF) -> Dictionary:
	var safe := anchor_by_id(safe_id)
	if safe_id>=0 and (safe.is_empty() or safe["broken"] or not safe.get("permanent",false)):
		return {"available":false,"anchors":[]}
	var previous: Vector2 = safe["pos"] if safe_id>=0 else safe_pos
	if safe_id>=0 and contact.is_finite(): previous = contact
	var reserves: Array[int] = []
	var exits := 0
	for id in main_route:
		var object := anchor_by_id(id)
		if object["pos"].y<=previous.y+.01: continue
		var target: Vector2 = object["pos"]
		if object["broken"]:
			if not layout.rescue_anchors.has(id): return {"available":false,"anchors":[]}
			var reserve_id: int = layout.rescue_anchors[id]
			target = anchors[reserve_id]["pos"]
			reserves.append(reserve_id)
			exits = 0
		else:
			exits += 1
		if previous.distance_to(target)>maximum or not layout.transition_clear(previous,target):
			return {"available":false,"anchors":[]}
		previous = target
	return {"available":exits>0,"anchors":reserves}

func activate_rescue_anchors(ids: Array) -> void:
	for id in ids:
		var object := anchor_by_id(int(id))
		if not object.get("reserve",false): continue
		object["broken"] = false
		if is_instance_valid(object.get("visual")): object["visual"].visible = true

func consume_anchor(id: int) -> void:
	var object := anchor_by_id(id)
	if object.is_empty() or object.get("permanent",true): return
	object["broken"] = true
	if is_instance_valid(object.get("visual")):
		object["visual"].visible = false
		if visuals_enabled:
			var p: Vector2 = object["pos"]
			for index in range(4):
				var chip := box("Осколок",Vector3(p.x+(index-1.5)*.22,p.y,2.5),Vector3(.16,.13,.15),mat("crumb",Color("b3ab87")))
				var tween := create_tween().set_parallel(true)
				tween.tween_property(chip,"position",chip.position+Vector3((index-1.5)*.35,-1.4,0),.36).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
				tween.tween_property(chip,"scale",Vector3.ZERO,.36)
				tween.chain().tween_callback(chip.queue_free)

func object_description(object: Dictionary) -> String:
	return "Постоянная опора" if object.get("permanent",true) else ["Одноразовая опора","Хрупкий · 2,6 с","Упругая · одноразовая","Скользкая · одноразовая","Кристалл · одноразовый"][int(object["kind"])]

func _make_glow_texture() -> void:
	var image := Image.create(48,48,false,Image.FORMAT_RGBA8)
	for x in range(48):
		for y in range(48):
			var distance := Vector2(x-23.5,y-23.5).length()/24
			image.set_pixel(x,y,Color(1,1,1,pow(maxf(0,1-distance),2)*.6))
	ghost_texture = ImageTexture.create_from_image(image)
