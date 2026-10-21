extends SceneTree

# Visual layer checks: the rock-mass mountain (masses, surface query, shelves,
# arches, overhangs), object mounting, quality-dependent decor, loot models,
# timers, profiles and chunk streaming. Gameplay collision is covered by the
# terrain, generation and integration suites.

var checks := 0
var failures := 0

func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error("FAIL: "+message)

func make_world(seed_value: int, quality: String, location: int = 0, version: int = 0) -> MountainWorld:
	var world := MountainWorld.new()
	world.visuals_enabled = false
	root.add_child(world)
	world.setup(seed_value,location,version)
	world.generate_to(126,true,120)
	world.visual_quality = quality
	world.visuals.set_quality(quality)
	return world

func skin_signature(world: MountainWorld, index: int) -> Array:
	var chunk := Node3D.new()
	world.add_child(chunk)
	world.visuals.build_chunk(index,chunk)
	var mesh: ArrayMesh = chunk.get_node("Скальный массив_%d" % index).mesh
	var arrays := mesh.surface_get_arrays(0)
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var colors: PackedColorArray = arrays[Mesh.ARRAY_COLOR]
	var sum := Vector3.ZERO
	for vertex in vertices: sum += vertex
	var color_sum := 0.0
	for color in colors: color_sum += color.r+color.g+color.b
	var decor := 0
	for child in chunk.get_children():
		if String(child.name).contains("Процедурный декор"): decor += 1
	chunk.free()
	return [vertices.size(),sum,color_sum,decor]

func count_named(node: Node, prefix: String) -> int:
	return node.find_children(prefix+"*","",true,false).size()

func polygon_on_stone(visuals: MassifVisuals, object: Dictionary, margin: float) -> bool:
	var half: Vector2 = object["dimensions"]*.5
	var p: Vector2 = object["pos"]
	for corner in [Vector2(-half.x,-half.y),Vector2(half.x,-half.y),half,Vector2(-half.x,half.y),Vector2.ZERO]:
		if visuals.stone_field(p+corner)<margin: return false
	return true

func _initialize() -> void:
	call_deferred("run_tests")

func run_tests() -> void:
	var a := make_world(58273,"balanced")
	var b := make_world(58273,"balanced")
	var other := make_world(4242,"balanced")
	var massif: MassifVisuals = a.visuals
	var first := skin_signature(a,1)
	var second := skin_signature(b,1)
	check(first[0]==second[0] and (first[1] as Vector3).is_equal_approx(second[1]) and is_equal_approx(first[2],second[2]) and first[3]==second[3],"the same seed rebuilds identical masses, colours and decor")
	var third := skin_signature(other,1)
	check(first[0]!=third[0] or not (first[1] as Vector3).is_equal_approx(third[1]),"another seed produces different stone")

	# Surface query: one frontmost face per point, the depth everybody uses.
	var consistent := true
	var front := true
	var in_range := true
	for x in range(-12,13,2):
		for y in range(26,46,2):
			var point := Vector2(x,y)
			var hit := massif.surface_query(point)
			if not hit.valid(): continue
			consistent = consistent and is_equal_approx(massif.wall_depth(point),hit.position.z) and is_equal_approx(massif.vertex(point).z,hit.position.z)
			for mass in massif.front_band(int(floor(y/24.0))):
				var surface: Dictionary = mass.surface_at(point)
				if not surface.is_empty() and float(surface["z"])>hit.position.z+.0001: front = false
			in_range = in_range and hit.position.z<MassifVisuals.GRIP_Z-.3 and hit.position.z>-3.6
	check(consistent and front,"the surface query returns the frontmost face, and wall depth reads it")
	check(in_range,"rock faces stay behind the plane of grips and the hero")

	# Masses: many blocks with names, faces split by facing, landforms.
	var masses := 0
	var corners_ok := true
	var named := true
	var classes := {}
	var landforms := {}
	var seats := 0
	var seats_big := true
	for band in range(0,5):
		for mass in massif.front_band(band):
			masses += 1
			corners_ok = corners_ok and mass.outer_contour.size()>=4 and mass.outer_contour.size()<=48
			named = named and mass.role!="" and mass.landform!="" and mass.seed_stream==947 and mass.material_profile!=""
			landforms[mass.landform] = true
			for face in mass.faces: classes[face["class"]] = true
			if mass.role=="seat":
				seats += 1
				seats_big = seats_big and mass.bounds.size.x>=2.4 and mass.bounds.size.y>=2.2
	check(masses>100 and corners_ok and named,"the mountain is built from many named blocks (%d)" % masses)
	check(classes.has(RockMassSpec.FACE) and classes.has(RockMassSpec.TOP) and classes.has(RockMassSpec.SIDE) and classes.has(RockMassSpec.UNDERSIDE) and classes.has(RockMassSpec.INNER) and classes.has(RockMassSpec.WALL),"masses have front, top, side, underside, arch and wall faces: %s" % str(classes.keys()))
	check(landforms.has("arch") and landforms.has("overhang") and landforms.has("island") and landforms.has("pillar") and landforms.has("shelf"),"landforms reach the geometry: %s" % str(landforms.keys()))
	check(seats_big and seats<a.nearby_anchors(0,120).size(),"objects never get a pedestal block of their own (%d seats)" % seats)
	# Host masses: one body with a front, top, side and underside and real
	# depth; lobes, seats and shelves fuse into a host instead of standing
	# alone; shelves keep a broad underside, never a wedge.
	var hosts_ok := false
	var fused := true
	var shelves_square := true
	var lobes := 0
	for band in range(0,5):
		for mass in massif.front_band(band):
			if mass.role=="trunk":
				var host_classes := {}
				for face in mass.faces: host_classes[face["class"]] = true
				if host_classes.has(RockMassSpec.FACE) and host_classes.has(RockMassSpec.TOP) and host_classes.has(RockMassSpec.SIDE) and host_classes.has(RockMassSpec.UNDERSIDE) and mass.front_z-mass.z_rim>.6 and mass.bounds.size.x>=5.0: hosts_ok = true
			if mass.role=="lobe":
				lobes += 1
				fused = fused and mass.group!=mass.id
			if mass.role in ["ledge_shelf","find_shelf"]:
				fused = fused and mass.group!=mass.id
				var top_width := 0.0
				var bottom_width := 0.0
				var top_y: float = mass.bounds.end.y
				var bottom_y: float = mass.bounds.position.y
				var low_x := INF
				var high_x := -INF
				for point in mass.outer_contour:
					if absf(point.y-top_y)<.01: top_width = mass.bounds.size.x
					if point.y<bottom_y+(top_y-bottom_y)*.25:
						low_x = minf(low_x,point.x)
						high_x = maxf(high_x,point.x)
				bottom_width = high_x-low_x
				shelves_square = shelves_square and bottom_width>=top_width*.25 and mass.bounds.size.y>=.85
	check(hosts_ok,"large host masses show a front, top, side and underside with real depth")
	check(lobes>5 and fused,"lobes, seats and shelves fuse into their host body (%d lobes)" % lobes)
	check(shelves_square,"shelves keep a broad, thick underside instead of a wedge")
	var practice := MountainWorld.new()
	practice.visuals_enabled = false
	root.add_child(practice)
	practice.setup(58273,0,0,true)
	check(practice.visuals is MassifVisuals,"the practice route uses the same rock-mass mountain")
	practice.free()
	# Arches: a real opening onto the sky with inner faces round it.
	var arches_ok := massif.arch_openings.size()>0
	for opening in massif.arch_openings:
		arches_ok = arches_ok and massif.open_at(opening.get_center()) and not massif.open_at(opening.get_center()+Vector2(0,opening.size.y*.5+.8)) and not massif.open_at(opening.get_center()-Vector2(0,opening.size.y*.5+.5))
	check(arches_ok,"every arch frames an open window with stone above and below (%d)" % massif.arch_openings.size())
	# Overhangs: a broad underside of the same mass.
	var overhang_ok := false
	for band in range(0,5):
		for mass in massif.front_band(band):
			if mass.landform!="overhang": continue
			var under := 0.0
			for face in mass.faces:
				if face["class"]!=RockMassSpec.UNDERSIDE: continue
				var p0: Vector3 = face["a"]
				var p1: Vector3 = face["b"]
				var p2: Vector3 = face["c"]
				under += absf(Vector2(p1.x-p0.x,p1.y-p0.y).cross(Vector2(p2.x-p0.x,p2.y-p0.y)))*.5
			overhang_ok = under>1.0
	check(overhang_ok,"an overhang shows a broad underside of its own mass")

	var counts := {}
	for quality in ["high","balanced","battery"]:
		var world := make_world(58273,quality)
		var total := 0
		for index in range(1,4): total += int(skin_signature(world,index)[3])
		counts[quality] = total
		world.free()
	check(counts["high"]>counts["balanced"] and counts["balanced"]>counts["battery"] and counts["battery"]>0,"decor density follows the graphics preset: %s" % str(counts))
	var silhouettes := {}
	for quality in ["high","battery"]:
		var world := make_world(58273,quality)
		var outline := 0
		for mass in (world.visuals as MassifVisuals).front_band(2): outline += mass.outer_contour.size()
		silhouettes[quality] = outline
		world.free()
	check(silhouettes["high"]==silhouettes["battery"],"every preset builds the same masses: %s" % str(silhouettes))

	# Loot: lit models; on the rock-mass mountain a find stands on a shelf of
	# the face, older mountains keep pedestals.
	var holder_parent := Node3D.new()
	a.add_child(holder_parent)
	var kinds := ["coin","amber","crown","chalice","idol","star","relic",""]
	var all_lit := true
	var no_pedestal := true
	for index in range(kinds.size()):
		var holder := Node3D.new()
		holder_parent.add_child(holder)
		var find := {"item":{"id":index,"tier":index%6,"kind":kinds[index],"value":100},"pos":Vector2.ZERO,"rare":index%2==1}
		LootVisuals.build(a,find,holder,"high",-.8)
		no_pedestal = no_pedestal and holder.find_child("Каменный постамент",false,false)==null and holder.find_child("Каменная полка",false,false)==null
		var has_halo := false
		for node in holder.find_children("*","MeshInstance3D",true,false):
			var mesh_node := node as MeshInstance3D
			if mesh_node.name.begins_with("Ореол"): has_halo = true
			var material := mesh_node.material_override
			if material is StandardMaterial3D and (material as StandardMaterial3D).shading_mode==BaseMaterial3D.SHADING_MODE_UNSHADED: all_lit = false
		check(has_halo==(index%2==1),"rarity halo matches the rare flag for %s" % kinds[index])
	check(all_lit and no_pedestal,"loot models take sun and shade, with no pedestal on the rock-mass mountain")
	check(LootVisuals.kind_of({"tier":4})=="idol" and LootVisuals.kind_of({"tier":0,"kind":"coin"})=="coin","items without a kind fall back to their tier model")
	var old := make_world(58273,"high",0,10)
	var old_parent := Node3D.new()
	old.add_child(old_parent)
	var pedestals := 0
	for kind in ["crown","chalice","coin"]:
		var holder := Node3D.new()
		old_parent.add_child(holder)
		LootVisuals.build(old,{"item":{"id":1,"tier":2,"kind":kind,"value":100},"pos":Vector2.ZERO,"rare":false},holder,"high",-.8)
		if holder.find_child("Каменный постамент",false,false)!=null or holder.find_child("Каменная полка",false,false)!=null: pedestals += 1
	check(pedestals==3,"older mountains still stand finds on pedestals")
	old.free()
	var shelves_ok := true
	var shelved := 0
	for find in a.finds:
		var p: Vector2 = find["pos"]
		if p.y<4 or p.y>110: continue
		var mount := massif.mount_find(find)
		var shelf: RockMassSpec = massif.masses_by_id.get(mount.host_mass)
		if shelf==null or shelf.role!="find_shelf":
			shelves_ok = false
			continue
		shelved += 1
		shelves_ok = shelves_ok and absf(shelf.bounds.end.y-(p.y-.4))<.05 and shelf.bounds.size.x>=1.5 and is_equal_approx(mount.holder_position().z,shelf.front_z+.05)
	check(shelved>0 and shelves_ok,"every find stands on a wide shelf of the face, at its front (%d)" % shelved)

	# Grip shells: several visual variants, collision polygon untouched.
	var grip_chunk := Node3D.new()
	a.add_child(grip_chunk)
	var shapes := {}
	var polygon_kept := true
	var no_pebbles := true
	for anchor in a.nearby_anchors(20,70):
		var before: PackedVector2Array = anchor["polygon"].duplicate()
		massif.build_anchor(anchor,grip_chunk)
		polygon_kept = polygon_kept and before==anchor["polygon"]
		var holder: Node3D = anchor["visual"]
		no_pebbles = no_pebbles and holder.find_child("Сколы",false,false)==null and holder.find_child("Каменное основание",false,false)==null
		var signature := ""
		for child in holder.get_children(): signature += String(child.name).substr(0,6)+","
		shapes[signature] = true
	check(polygon_kept,"visual grips never change the gameplay polygon")
	check(no_pebbles,"grips carry no pebble chips or base ring of their own")
	check(shapes.size()>=4,"grips have several distinct visual builds (%d)" % shapes.size())
	var strip_lit := true
	for node in grip_chunk.find_children("Полоса состояния*","MeshInstance3D",true,false):
		strip_lit = strip_lit and (node as MeshInstance3D).cast_shadow==GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	check(strip_lit,"status strips never add a second shadow line")
	var contours := grip_chunk.find_children("Контур","MeshInstance3D",true,false).size()
	check(contours>=a.nearby_anchors(20,70).size(),"every grip has a contrast contour")
	var dials := 0
	var dial_ok := true
	for anchor in a.nearby_anchors(4,110):
		if int(anchor["kind"])!=1 or anchor.get("permanent",false): continue
		a.build_anchor(anchor,grip_chunk)
		dials += 1
		var label: Label3D = anchor["timer_dial"]["label"]
		dial_ok = dial_ok and label.text=="2,6"
		a.update_anchor_timer(anchor["id"],1.0)
		var material: ShaderMaterial = anchor["timer_dial"]["material"]
		dial_ok = dial_ok and label.text=="1,0" and absf(float(material.get_shader_parameter("remaining"))-1.0/MountainWorld.FRAGILE_SECONDS)<.001
	check(dials>0 and dial_ok,"fragile grips carry their own countdown dial (%d)" % dials)
	# Stone under every grip outline, find and obstacle; the route corridor.
	var stone_under := true
	for anchor in a.nearby_anchors(4,110):
		stone_under = stone_under and polygon_on_stone(massif,anchor,.1)
	for find in a.finds:
		if find["pos"].y<110: stone_under = stone_under and massif.stone_field(find["pos"])>=.1
	for obstacle in a.obstacles:
		if obstacle["pos"].y<110: stone_under = stone_under and polygon_on_stone(massif,obstacle,.1)
	check(stone_under,"every grip, find and obstacle lies on stone with its whole outline")
	var corridor := true
	for y in range(4,110,2):
		var route: float = a.layout.route_x(y)
		for offset in [-2.3,0.0,2.3]:
			corridor = corridor and massif.stone_field(Vector2(route+offset,y))>=0
	check(corridor,"the route corridor of 2.4 m stays solid stone")
	var open := 0
	var total := 0
	for x in range(-7,8):
		for y in range(20,100):
			total += 1
			if massif.stone_field(Vector2(x,y))<0: open += 1
	var sky_share := float(open)/total
	check(sky_share>.05 and sky_share<.6,"sky opens between the masses around the climb (%.2f)" % sky_share)
	# Visible grip stone stays within the gameplay polygon.
	var inside_polygon := true
	for anchor in a.nearby_anchors(20,70):
		var holder: Node3D = anchor["visual"]
		var bounds := Rect2(anchor["polygon"][0],Vector2.ZERO)
		for point in anchor["polygon"]: bounds = bounds.expand(point)
		for child in holder.get_children():
			if child.name.begins_with("Каменный выступ"):
				var box: AABB = (child as MeshInstance3D).get_aabb()
				inside_polygon = inside_polygon and box.position.x>=bounds.position.x-.02 and box.end.x<=bounds.end.x+.02 and box.end.y<=bounds.end.y+.02 and box.position.y>=bounds.position.y-.15
	check(inside_polygon,"visible grip stone stays within the gameplay polygon")
	# Prices: hidden by default far from the hero, shown nearby, along the aim
	# or always when the setting asks for it.
	var priced := MountainWorld.new()
	root.add_child(priced)
	var label := Label3D.new()
	priced.add_child(label)
	priced.finds.append({"pos":Vector2(10,10),"price_visual":label})
	priced.update_loot_prices(true,false,Vector2(0,10),Vector2.INF)
	var hidden := not label.visible
	priced.update_loot_prices(true,false,Vector2(8,10),Vector2.INF)
	var near := label.visible
	priced.update_loot_prices(true,false,Vector2(0,10),Vector2(14,10))
	var aimed := label.visible
	priced.update_loot_prices(true,true,Vector2(0,40),Vector2.INF)
	var always := label.visible
	priced.update_loot_prices(false,true,Vector2(10,10),Vector2.INF)
	check(hidden and near and aimed and always and not label.visible,"loot prices follow the near / aim / always setting")
	priced.free()
	massif.set_quality("battery")
	var battery_layers := massif.far_layer_count()
	massif.set_quality("high")
	check(battery_layers==1 and massif.far_layer_count()==2,"distant ranges follow the graphics preset")
	var far_a := Node3D.new()
	var far_b := Node3D.new()
	a.add_child(far_a)
	b.add_child(far_b)
	massif.build_far_band(1,2,far_a)
	(b.visuals as MassifVisuals).build_far_band(1,2,far_b)
	var far_mesh_a: ArrayMesh = far_a.get_child(0).mesh
	var far_mesh_b: ArrayMesh = far_b.get_child(0).mesh
	check(far_mesh_a.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]==far_mesh_b.surface_get_arrays(0)[Mesh.ARRAY_VERTEX],"distant ranges are deterministic per seed")
	# Grip types differ by material, not only by the status strip.
	var names := {}
	var identity_kept := true
	for kind in range(5):
		names[massif.grip_material_name({"kind":kind,"permanent":false})] = true
		identity_kept = identity_kept and massif.grip_material_name({"kind":kind,"permanent":true})==massif.grip_material_name({"kind":kind,"permanent":false})
	check(names.size()==5 and identity_kept,"each grip type has its own material and permanence keeps it (%s)" % str(names.keys()))
	# Every profile keeps the five types apart, names them, and has a rock.
	var profiles_ok := true
	for profile_id in GripBiomeProfile.IDS:
		var profile := GripBiomeProfile.named(profile_id)
		var families := {}
		for kind in range(5): families[profile.family(kind)] = true
		profiles_ok = profiles_ok and families.size()==5 and profile.type_titles.size()==5
		for key in ["base_color","facet_palette","roughness","normal_strength","strata_scale","cavity_strength","top_light_tint","underside_tint","weathering_mask","decor_palette"]:
			profiles_ok = profiles_ok and profile.rock_material.has(key)
	check(profiles_ok and GripBiomeProfile.id_for(0,70)=="snow" and GripBiomeProfile.id_for(1,10)=="desert" and GripBiomeProfile.id_for(2,10)=="sky","five profiles with rock materials map onto locations and zones")
	check(GripBiomeProfile.named("desert").rock_material["base_color"]!=GripBiomeProfile.named("snow").rock_material["base_color"] and float(GripBiomeProfile.named("desert").rock_material["strata_scale"])>float(GripBiomeProfile.named("forest").rock_material["strata_scale"]),"desert and snow differ in rock, not only in tint")
	# Hazards are set into the rock: a warm glint only on upward edges.
	var hazard_chunk := Node3D.new()
	a.add_child(hazard_chunk)
	var glints := 0
	var hazards := 0
	for obstacle in a.obstacles:
		if not obstacle.get("massif",false) or obstacle["pos"].y>110: continue
		massif.build_obstacle(obstacle,hazard_chunk)
		hazards += 1
		for child in (obstacle["visual"] as Node3D).get_children():
			if child.name.begins_with("Тёплая кромка"): glints += 1
	check(hazards>0 and glints==hazards,"hazards carry an edge glint")
	# Large themed set pieces stand on side islands, clear of the route.
	var landmarks := 0
	var landmarks_clear := true
	for index in range(0,5):
		var chunk := Node3D.new()
		a.add_child(chunk)
		massif.build_chunk(index,chunk)
		for child in chunk.get_children():
			if String(child.name).begins_with("Крупный элемент"):
				landmarks += 1
				var at := Vector2(child.position.x,child.position.y)
				landmarks_clear = landmarks_clear and absf(at.x-a.layout.route_x(at.y))>3.0
		chunk.free()
	check(landmarks>=2 and landmarks_clear,"themed landmarks stand on side islands away from the route (%d)" % landmarks)
	# Mounted grips: one socket per grip, type cues and lifetime fixings.
	var mount_chunk := Node3D.new()
	a.add_child(mount_chunk)
	var sockets := true
	var cues := {}
	var fixed_ok := true
	var single_contact := true
	var hosted := true
	for anchor in a.nearby_anchors(4,118):
		if anchor.get("reserve",false): continue
		massif.build_anchor(anchor,mount_chunk)
		var holder: Node3D = anchor["visual"]
		var mount: SurfaceMount = anchor["mount"]
		sockets = sockets and holder.find_child("Каменное гнездо",false,false)!=null
		single_contact = single_contact and is_equal_approx(holder.position.z,mount.wall_z()+MountainVisuals.GRIP_STANDOFF) and is_equal_approx(mount.wall_z(),massif.wall_depth(anchor["pos"]))
		hosted = hosted and mount.host_mass>=0 and mount.surface_class!="" and mount.socket_center.is_equal_approx(Vector3(anchor["pos"].x,anchor["pos"].y,mount.wall_z()))
		match GripSpec.kind_of(anchor):
			GripSpec.SPRING: if holder.find_child("Изгиб",false,false)!=null and holder.find_child("Направление выхода",true,false)!=null: cues["spring"] = true
			GripSpec.ICE: if holder.find_child("Трещина",true,false)!=null: cues["ice"] = true
			GripSpec.CRYSTAL: if holder.find_child("Кристалл",true,false)!=null: cues["crystal"] = true
			GripSpec.ROOT: if holder.find_child("Трещина",true,false)!=null: cues["root"] = true
		if anchor["permanent"]: fixed_ok = fixed_ok and holder.find_children("*крепление*","MeshInstance3D",true,false).size()+holder.find_children("Кольцо*","MeshInstance3D",true,false).size()>0
	check(sockets and single_contact,"every grip sits in a stone socket at one contact depth from its SurfaceMount")
	check(hosted,"every grip is mounted on a host mass found by the surface query")
	check(cues.size()==4 and fixed_ok,"type cues (bend, slide track, crystal, root) and permanent fixings are built: %s" % str(cues.keys()))
	# Legacy locations use the shared builder: no rectangle boxes remain.
	var legacy := make_world(58273,"balanced",1)
	var legacy_chunk := Node3D.new()
	legacy.add_child(legacy_chunk)
	var shared := true
	for anchor in legacy.nearby_anchors(0,24):
		legacy.visuals.build_anchor(anchor,legacy_chunk)
		var holder: Node3D = anchor["visual"]
		shared = shared and holder.find_child("Прямоугольник",false,false)==null and holder.find_child("Каменное гнездо",false,false)!=null
	for ledge in legacy.ledges: legacy.visuals.build_ledge(ledge,legacy_chunk)
	check(shared and legacy_chunk.find_children("Площадка отдыха*","Node3D",false,false).size()==legacy.ledges.size(),"legacy locations build grips and shelves through the shared mount API")
	legacy.free()
	await mount_contract_checks()
	print("VISUAL_TESTS %d checks, %d failures" % [checks,failures])
	a.free()
	b.free()
	other.free()
	quit(1 if failures>0 else 0)

# Mount contract, every location slot, decor budgets and chunk streaming.
func mount_contract_checks() -> void:
	var a := make_world(58273,"balanced")
	var b := make_world(58273,"balanced")
	var massif: MassifVisuals = a.visuals
	var chunk_a := Node3D.new()
	var chunk_b := Node3D.new()
	a.add_child(chunk_a)
	b.add_child(chunk_b)
	var same := true
	var placed := true
	for index in range(a.anchors.size()):
		var anchor: Dictionary = a.anchors[index]
		if anchor["pos"].y<4 or anchor["pos"].y>60: continue
		var before: Vector2 = anchor["pos"]
		a.visuals.build_anchor(anchor,chunk_a)
		b.visuals.build_anchor(b.anchors[index],chunk_b)
		var mount: SurfaceMount = anchor["mount"]
		same = same and mount.signature()==(b.anchors[index]["mount"] as SurfaceMount).signature()
		placed = placed and anchor["pos"]==before and mount.layout_point==before and (anchor["visual"] as Node3D).position.is_equal_approx(mount.holder_position())
	check(same,"the same seed gives the same mount for every grip")
	check(placed,"grip holders stand on their mount at the unchanged layout point")
	# Ledges: a shelf mass whose top edge is the walking line.
	var shelf_ok := true
	var shelves := 0
	for ledge in a.ledges:
		var top := float(ledge["top"])
		if top<4 or top>110: continue
		var before := [ledge["left"],ledge["right"],ledge["top"]]
		a.visuals.build_ledge(ledge,chunk_a)
		shelves += 1
		var found := false
		for mass in massif.front_band(int(floor(top/24.0))):
			if mass.role!="ledge_shelf" or absf(mass.bounds.end.y-top)>.01: continue
			found = mass.bounds.position.x<=float(ledge["left"]) and mass.bounds.end.x>=float(ledge["right"]) and mass.bounds.size.y>=.8 and not mass.top_edges.is_empty()
		shelf_ok = shelf_ok and found and before==[ledge["left"],ledge["right"],ledge["top"]] and (ledge["mount"] as SurfaceMount).host_mass>=0
	check(shelves>0 and shelf_ok,"every ledge is a shelf of the face with its top on the walking line (%d)" % shelves)
	# A consumed grip takes its socket and shade with it; the face is clean.
	var consumed := false
	for anchor in a.anchors:
		if anchor.get("permanent",true) or not is_instance_valid(anchor.get("visual")): continue
		a.consume_anchor(anchor["id"])
		var holder: Node3D = anchor["visual"]
		consumed = not holder.visible and holder.find_child("Каменное гнездо",false,false)!=null and holder.find_child("Контактная тень",false,false)!=null and not massif.has_method("_occlusion")
		break
	check(consumed,"consume_anchor hides the grip with its socket and shade, nothing baked stays behind")
	# Decor budgets per chunk and profile-specific decor.
	var budget_ok := true
	var snow_caps := 0
	var on_faces := true
	for index in range(0,5):
		var decor_chunk := Node3D.new()
		a.add_child(decor_chunk)
		massif.build_chunk(index,decor_chunk)
		var decor := 0
		var crystals := 0
		for child in decor_chunk.get_children():
			if not String(child.name).begins_with("Процедурный декор"): continue
			decor += 1
			if child.find_child("Кристалл",false,false)!=null: crystals += 1
			var at := Vector2(child.position.x,child.position.y)
			on_faces = on_faces and massif.surface_query(at).valid()
		snow_caps += count_named(decor_chunk,"Снежный карниз")
		budget_ok = budget_ok and decor<=22 and crystals<=3
		decor_chunk.free()
	check(budget_ok,"decor and crystals stay within the balanced budget per chunk")
	check(on_faces,"every decor piece grows from a rock face")
	check(snow_caps>0,"the snow zone grows snow cornices instead of grass (%d)" % snow_caps)
	# Location slots 1 and 2 use the same masses and mount contract.
	for location in [1,2]:
		var legacy := make_world(58273,"balanced",location)
		var visuals := legacy.visuals as MassifVisuals
		check(visuals!=null,"location %d builds the shared rock-mass mountain" % location)
		if visuals==null:
			legacy.free()
			continue
		var stone_behind := true
		var mounted := true
		var legacy_chunk := Node3D.new()
		legacy.add_child(legacy_chunk)
		for anchor in legacy.nearby_anchors(2,100):
			stone_behind = stone_behind and polygon_on_stone(visuals,anchor,.1)
			visuals.build_anchor(anchor,legacy_chunk)
			mounted = mounted and is_equal_approx((anchor["visual"] as Node3D).position.z,visuals.wall_depth(anchor["pos"])+MountainVisuals.GRIP_STANDOFF)
		for find in legacy.finds:
			if find["pos"].y<100: stone_behind = stone_behind and visuals.stone_field(find["pos"])>=.1
		var corridor := true
		for y in range(4,100,2):
			for offset in [-2.3,0.0,2.3]:
				corridor = corridor and visuals.stone_field(Vector2(visuals.route_x_at(y)+offset,y))>=0
		check(stone_behind and corridor,"location %d keeps stone behind every grip, find and the route" % location)
		check(mounted,"location %d grips sit on the masses at one contact depth" % location)
		var skin := Node3D.new()
		legacy.add_child(skin)
		visuals.build_chunk(1,skin)
		check(skin.get_node_or_null("Скальный массив_1")!=null,"location %d has its rock masses" % location)
		var plants := count_named(skin,"Кактус")+count_named(skin,"Трава")
		check(plants>0,"location %d grows its profile's plants" % location)
		legacy.free()
	# Chunk streaming: leaving and returning rebuilds the same chunks and
	# frees every mesh of the released ones.
	var streamed := MountainWorld.new()
	root.add_child(streamed)
	streamed.setup(58273,0)
	streamed.set_visual_quality("balanced")
	streamed.generate_to(126,true,120)
	streamed.update_visibility(30,0)
	await process_frame
	var first := streamed.find_children("*","MeshInstance3D",true,false).size()
	var keys := streamed.chunks.keys()
	keys.sort()
	var materials := 0
	for trip in range(2):
		streamed.update_visibility(100,0)
		await process_frame
		await process_frame
		streamed.update_visibility(30,0)
		await process_frame
		await process_frame
		# The first trip meets new zones and their materials; later trips
		# must reuse them.
		if trip==0: materials = streamed.materials.size()
	var again := streamed.find_children("*","MeshInstance3D",true,false).size()
	var back := streamed.chunks.keys()
	back.sort()
	check(first==again and keys==back,"chunk streaming rebuilds the same chunks without leftovers (%d / %d meshes)" % [first,again])
	check(streamed.materials.size()==materials,"material cache stops growing once every zone was seen (%d -> %d)" % [materials,streamed.materials.size()])
	streamed.free()
	a.free()
	b.free()
