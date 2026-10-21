extends SceneTree

# Visual layer checks: deterministic procedural stone, quality-dependent decor,
# loot models for every item kind and consistent shadow settings. Gameplay
# collision is covered by the terrain, generation and integration suites.

var checks := 0
var failures := 0

func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error("FAIL: "+message)

func make_world(seed_value: int, quality: String) -> MountainWorld:
	var world := MountainWorld.new()
	world.visuals_enabled = false
	root.add_child(world)
	world.setup(seed_value,0)
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

func _initialize() -> void:
	call_deferred("run_tests")

func run_tests() -> void:
	var a := make_world(58273,"balanced")
	var b := make_world(58273,"balanced")
	var other := make_world(4242,"balanced")
	var first := skin_signature(a,1)
	var second := skin_signature(b,1)
	check(first[0]==second[0] and (first[1] as Vector3).is_equal_approx(second[1]) and is_equal_approx(first[2],second[2]) and first[3]==second[3],"the same seed rebuilds identical stone facets, colours and decor")
	check(first[0]!=skin_signature(other,1)[0] or not (first[1] as Vector3).is_equal_approx(skin_signature(other,1)[1]),"another seed produces different stone")
	var massif: MassifVisuals = a.visuals
	var low := INF
	var high := -INF
	var on_plane := true
	for x in range(-12,13,3):
		for y in range(26,46,3):
			var point := Vector2(x,y)
			if a.layout.rock_field(point)<.4: continue
			var depth := massif.wall_depth(point)
			low = minf(low,depth)
			high = maxf(high,depth)
			on_plane = on_plane and is_equal_approx(depth,massif.vertex(point).z)
	check(on_plane,"decor and grips sample the exact facet plane used by the mesh")
	check(high<MassifVisuals.GRIP_Z and low>-2.3,"grips stay in front of the stone so their shadows land close to them")

	var counts := {}
	for quality in ["high","balanced","battery"]:
		var world := make_world(58273,quality)
		var total := 0
		for index in range(1,4): total += int(skin_signature(world,index)[3])
		counts[quality] = total
		world.free()
	check(counts["high"]>counts["balanced"] and counts["balanced"]>counts["battery"] and counts["battery"]>0,"decor density follows the graphics preset: %s" % str(counts))

	# Every loot kind builds a lit model on a stone base; rare finds get a halo.
	var holder_parent := Node3D.new()
	a.add_child(holder_parent)
	var kinds := ["coin","amber","crown","chalice","idol","star","relic",""]
	var all_lit := true
	var all_contact := true
	for index in range(kinds.size()):
		var holder := Node3D.new()
		holder_parent.add_child(holder)
		var find := {"item":{"id":index,"tier":index%6,"kind":kinds[index],"value":100},"pos":Vector2.ZERO,"rare":index%2==1}
		LootVisuals.build(a,find,holder,"high",-.8)
		var has_contact := holder.find_child("Каменн*",false,false)!=null
		var has_halo := false
		for node in holder.find_children("*","MeshInstance3D",true,false):
			var mesh_node := node as MeshInstance3D
			if mesh_node.name.begins_with("Ореол"): has_halo = true
			var material := mesh_node.material_override
			if material is StandardMaterial3D and (material as StandardMaterial3D).shading_mode==BaseMaterial3D.SHADING_MODE_UNSHADED: all_lit = false
		all_contact = all_contact and has_contact
		check(has_halo==(index%2==1),"rarity halo matches the rare flag for %s" % kinds[index])
	check(all_lit and all_contact,"loot models take sun and shade, each grounded on stone")
	check(LootVisuals.kind_of({"tier":4})=="idol" and LootVisuals.kind_of({"tier":0,"kind":"coin"})=="coin","items without a kind fall back to their tier model")

	# Grip shells: several visual variants, collision polygon untouched.
	var grip_chunk := Node3D.new()
	a.add_child(grip_chunk)
	var shapes := {}
	var polygon_kept := true
	for anchor in a.nearby_anchors(20,70):
		var before: PackedVector2Array = anchor["polygon"].duplicate()
		massif.build_anchor(anchor,grip_chunk)
		polygon_kept = polygon_kept and before==anchor["polygon"]
		var holder: Node3D = anchor["visual"]
		var signature := ""
		for child in holder.get_children(): signature += String(child.name).substr(0,6)+","
		shapes[signature] = true
	check(polygon_kept,"visual grips never change the gameplay polygon")
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
	# Boulder massif: stone under every gameplay object and along the route
	# corridor, polygonal boulders, and real sky openings between them.
	var stone_under := true
	for anchor in a.nearby_anchors(4,110):
		stone_under = stone_under and massif.stone_field(anchor["pos"])>=MassifVisuals.grip_clearance(anchor)-.05
	for find in a.finds:
		if find["pos"].y<110: stone_under = stone_under and massif.stone_field(find["pos"])>=MassifVisuals.FIND_CLEARANCE-.05
	for obstacle in a.obstacles:
		if obstacle["pos"].y<110: stone_under = stone_under and massif.stone_field(obstacle["pos"])>=0
	check(stone_under,"every grip, find and obstacle keeps stone behind it")
	var corridor := true
	for y in range(4,110,2):
		var route: float = a.layout.route_x(y)
		for offset in [-2.3,0.0,2.3]:
			corridor = corridor and massif.stone_field(Vector2(route+offset,y))>=0
	check(corridor,"the route corridor of 2.4 m stays solid stone")
	var sides_ok := true
	var boulder_count := 0
	for band in range(0,4):
		for boulder in massif.front_band(band):
			boulder_count += 1
			var corners: int = boulder["points"].size()
			sides_ok = sides_ok and corners>=5 and corners<=10
	check(sides_ok and boulder_count>20,"the massif is built from many faceted polygonal boulders (%d)" % boulder_count)
	var open := 0
	var total := 0
	for x in range(-7,8):
		for y in range(20,100):
			total += 1
			if massif.stone_field(Vector2(x,y))<0: open += 1
	var sky_share := float(open)/total
	check(sky_share>.08 and sky_share<.6,"sky opens between the boulders around the climb (%.2f)" % sky_share)
	# Grip shells follow the gameplay polygon, with a small dark underside.
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
	# Crown and chalice stand on stone pedestals.
	var pedestals := 0
	for node in holder_parent.find_children("Каменный постамент","Node3D",true,false): pedestals += 1
	check(pedestals==2,"crown and chalice rest on stone pedestals")
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
	check(battery_layers==1 and massif.far_layer_count()==2,"distant cliff layers follow the graphics preset")
	var far_a := Node3D.new()
	var far_b := Node3D.new()
	a.add_child(far_a)
	b.add_child(far_b)
	massif.build_far_band(1,2,far_a)
	(b.visuals as MassifVisuals).build_far_band(1,2,far_b)
	var far_mesh_a: ArrayMesh = far_a.get_child(0).mesh
	var far_mesh_b: ArrayMesh = far_b.get_child(0).mesh
	check(far_mesh_a.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]==far_mesh_b.surface_get_arrays(0)[Mesh.ARRAY_VERTEX],"distant cliffs are deterministic per seed")
	# Grip types differ by material, not only by the status strip.
	var names := {}
	var identity_kept := true
	for kind in range(5):
		names[massif.grip_material_name({"kind":kind,"permanent":false})] = true
		identity_kept = identity_kept and massif.grip_material_name({"kind":kind,"permanent":true})==massif.grip_material_name({"kind":kind,"permanent":false})
	check(names.size()==5 and identity_kept,"each grip type has its own material and permanence keeps it (%s)" % str(names.keys()))
	# Every profile keeps the five types apart and names them for the HUD.
	var profiles_ok := true
	for profile_id in GripBiomeProfile.IDS:
		var profile := GripBiomeProfile.named(profile_id)
		var families := {}
		for kind in range(5): families[profile.family(kind)] = true
		profiles_ok = profiles_ok and families.size()==5 and profile.type_titles.size()==5
	check(profiles_ok and GripBiomeProfile.id_for(0,70)=="snow" and GripBiomeProfile.id_for(1,10)=="desert" and GripBiomeProfile.id_for(2,10)=="sky","five biome profiles map onto locations and zones")
	# Hazards are set into the rock: no closed outline, a warm glint only on
	# upward edges and rubble at the foot.
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
	check(hazards>0 and glints==hazards and not massif.has_method("_outline_polygon"),"hazards carry an edge glint instead of a sticker outline")
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
	# Every find rests on stone.
	var supported := true
	for holder in holder_parent.get_children():
		supported = supported and (holder.find_child("Каменный постамент",false,false)!=null or holder.find_child("Каменная полка",false,false)!=null)
	check(supported,"every find sits on a stone shelf or pedestal")
	# Mounted grips: one socket per grip, type cues and lifetime fixings.
	var mount_chunk := Node3D.new()
	a.add_child(mount_chunk)
	var sockets := true
	var cues := {}
	var fixed_ok := true
	var single_contact := true
	for anchor in a.nearby_anchors(4,118):
		if anchor.get("reserve",false): continue
		massif.build_anchor(anchor,mount_chunk)
		var holder: Node3D = anchor["visual"]
		var mount: SurfaceMount = anchor["mount"]
		sockets = sockets and holder.find_child("Каменное гнездо",false,false)!=null
		single_contact = single_contact and is_equal_approx(holder.position.z,mount.wall_z()+MountainVisuals.GRIP_STANDOFF) and is_equal_approx(mount.wall_z(),massif.wall_depth(anchor["pos"]))
		match GripSpec.kind_of(anchor):
			GripSpec.SPRING: if holder.find_child("Изгиб",false,false)!=null and holder.find_child("Направление выхода",true,false)!=null: cues["spring"] = true
			GripSpec.ICE: if holder.find_child("Трещина",true,false)!=null: cues["ice"] = true
			GripSpec.CRYSTAL: if holder.find_child("Кристалл",true,false)!=null: cues["crystal"] = true
			GripSpec.ROOT: if holder.find_child("Трещина",true,false)!=null: cues["root"] = true
		if anchor["permanent"]: fixed_ok = fixed_ok and holder.find_children("*крепление*","MeshInstance3D",true,false).size()+holder.find_children("Кольцо*","MeshInstance3D",true,false).size()>0
	check(sockets and single_contact,"every grip sits in a stone socket at one contact depth from its SurfaceMount")
	check(cues.size()==4 and fixed_ok,"type cues (bend, slide track, crystal, root) and permanent fixings are built: %s" % str(cues.keys()))
	# Side faces of the massif: same silhouette in every preset, deterministic.
	var flank_counts := {}
	for quality in ["high","balanced","battery"]:
		var world := make_world(58273,quality)
		var chunk := Node3D.new()
		world.add_child(chunk)
		world.visuals.build_chunk(2,chunk)
		var flank: MeshInstance3D = chunk.get_node_or_null("Боковые грани_2")
		flank_counts[quality] = flank.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX].size() if flank!=null else 0
		world.free()
	check(flank_counts["high"]>0 and flank_counts["high"]==flank_counts["balanced"] and flank_counts["balanced"]==flank_counts["battery"],"massif flanks keep one silhouette across presets: %s" % str(flank_counts))
	# Legacy locations use the shared builder: no rectangle boxes remain.
	var legacy := MountainWorld.new()
	legacy.visuals_enabled = false
	root.add_child(legacy)
	legacy.setup(58273,1)
	legacy.generate_to(40,true,140)
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
	print("VISUAL_TESTS %d checks, %d failures" % [checks,failures])
	a.free()
	b.free()
	other.free()
	quit(1 if failures>0 else 0)
