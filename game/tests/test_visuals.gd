extends SceneTree

const FloraModels := preload("res://scripts/flora_models.gd")

const TreasureModels := preload("res://scripts/treasure_models.gd")

const WoodPlatform := preload("res://scripts/wood_platform.gd")

# Visual layer checks: the rock-mass mountain (masses, surface query, shelves,
# arches, overhangs), object mounting, quality-dependent decor, loot models,
# timers, profiles and chunk streaming. Gameplay collision is covered by the
# terrain, generation and integration suites.

var checks := 0
var failures := 0

func mesh_shadows(node: Node) -> bool:
	for mesh: MeshInstance3D in node.find_children("*","MeshInstance3D",true,false):
		if mesh.cast_shadow==GeometryInstance3D.SHADOW_CASTING_SETTING_OFF: return false
	return true

# Share of a paint strip's width that really carries paint.
func painted_share(strip: MeshInstance3D) -> float:
	var spans: Array = []
	var faces := strip.mesh.get_faces()
	for index in range(0,faces.size(),3):
		var low := minf(faces[index].x,minf(faces[index+1].x,faces[index+2].x))
		var high := maxf(faces[index].x,maxf(faces[index+1].x,faces[index+2].x))
		spans.append(Vector2(low,high))
	spans.sort_custom(func(a: Vector2, b: Vector2) -> bool: return a.x<b.x)
	var painted := 0.0
	var reach: float = spans[0].x
	for span: Vector2 in spans:
		painted += maxf(0,span.y-maxf(span.x,reach))
		reach = maxf(reach,span.y)
	return painted/(reach-float(spans[0].x))

func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error("FAIL: "+message)

func transparent_region(path: String, region: Rect2i) -> bool:
	var image := (load(path) as Texture2D).get_image()
	for y in range(region.position.y,mini(region.end.y,image.get_height())):
		for x in range(region.position.x,mini(region.end.x,image.get_width())):
			if image.get_pixel(x,y).a>.01: return false
	return true

func make_world(seed_value: int, quality: String, location: int = 0, version: int = 0) -> MountainWorld:
	var world := MountainWorld.new()
	world.visuals_enabled = false
	root.add_child(world)
	# The first location's zone look (bands, ice and snow with height) is the
	# v13 contract of saved attempts; expeditions are checked in test_levels.
	world.setup(seed_value,location,version if version>0 or location!=0 else 13)
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
		if String(child.name).begins_with("Декор_"): decor += 1
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
	var host_tone := massif.zone_color(10.0)
	var grip_tone := massif.grip_stone_color(host_tone,GripBiomeProfile.for_place(0,10.0),GripSpec.STONE)
	var tone_delta := absf(grip_tone.r-host_tone.r)+absf(grip_tone.g-host_tone.g)+absf(grip_tone.b-host_tone.b)
	check(tone_delta>.07,"hook stones keep a visible contrast step against the host rock")
	var cleanup_anchor: Dictionary = a.nearby_anchors(4,110)[0]
	check(massif._decor_blocked(cleanup_anchor["pos"]+Vector2(1.9,0.0)),
		"decor keeps a clear halo around the visible hook platform")
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
	check(landforms.has("arch") and landforms.has("overhang") and landforms.has("island") and landforms.has("pillar") and not landforms.has("shelf"),"landforms reach the geometry: %s" % str(landforms.keys()))
	check(seats_big and seats<a.nearby_anchors(0,120).size(),"objects never get a pedestal block of their own (%d seats)" % seats)
	# Boulders of the reference: large face masses have a rounded rim of many
	# short edges (no side longer than 40% of the girth) and a high crown, so
	# their facets turn to the light all over. Shelves and arches stay blocks.
	var rounded := 0
	var large := 0
	var crowned := true
	for band in range(0,5):
		for mass in massif.front_band(band):
			if mass.role not in ["trunk","body","island"] or mass.landform=="pillar" or mass.bounds.size.x<3.5: continue
			large += 1
			var girth := 0.0
			var longest := 0.0
			for i in range(mass.outer_contour.size()):
				var edge: float = mass.outer_contour[i].distance_to(mass.outer_contour[(i+1)%mass.outer_contour.size()])
				girth += edge
				longest = maxf(longest,edge)
			if mass.outer_contour.size()>=8 and longest<girth*.4: rounded += 1
			crowned = crowned and mass.front_z-mass.z_rim>=.6 and mass.front_z<=MassifVisuals.FRONT_LIMIT+.001
	check(large>20 and rounded==large and crowned,"large masses are rounded boulders with a high crown (%d / %d)" % [rounded,large])
	var boulder_a := RockMassSpec.boulder_contour(Vector2(3,40),Vector2(6,5),a.seeded_rng(7,947),.2)
	var boulder_b := RockMassSpec.boulder_contour(Vector2(3,40),Vector2(6,5),a.seeded_rng(7,947),.2)
	check(boulder_a==boulder_b and boulder_a.size()>=8,"boulder contours are deterministic per seed stream")
	# Host masses: one body with a front, top, side and underside and real
	# depth; lobes and seats fuse into a host instead of standing alone.
	var hosts_ok := false
	var fused := true
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
	check(hosts_ok,"large host masses show a front, top, side and underside with real depth")
	check(lobes>5 and fused,"lobes and seats fuse into their host body (%d lobes)" % lobes)
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

	# Loot: lit models; on the rock-mass mountain a find lies on the face with
	# no shelf of its own, older mountains keep pedestals.
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
	var visual_items := [
		ItemCatalog.valuable(1,0,"root_wall",1),
		ItemCatalog.valuable(2,0,"root_wall",4,"artifact"),
		ItemCatalog.relic(3,0,"root_wall",3,"forest_relic"),
		ItemCatalog.material(4,0,"root_wall",2,"core"),
		ItemCatalog.contract(5,0,"root_wall",2,"root_impulse")
	]
	var visual_style_ok := true
	for item in visual_items:
		visual_style_ok = visual_style_ok and LootIcon.rarity_color(item)==LootVisuals.rarity_color(item) and LootVisuals.kind_of(item)==str(item["kind"])
	check(visual_style_ok,"map and backpack share the same treasure kind and accent palette")
	check(transparent_region("res://assets/sprites/vegetation/grass_tuft_4.png",Rect2i(0,0,384,32)),"grass tuft has no fragment from the neighbouring texture at its top edge")
	check(transparent_region("res://assets/sprites/treasures/treasure_a_7.png",Rect2i(0,0,16,52)),"chest sprite has no stray strip at its left edge")
	check(transparent_region("res://assets/sprites/treasures/treasure_winter_3.png",Rect2i(0,372,352,12)),"winter music box has no detached object below its feet")
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
	# No shelf, ledge or seat-shaped platform under loot: the only shelves of
	# the face are rest ledges, so a coin never reads as a route platform.
	var loot_clear := true
	var checked := 0
	for band in range(0,5):
		for mass in massif.front_band(band):
			loot_clear = loot_clear and mass.role!="find_shelf" and mass.landform!="shelf"
	for find in a.finds:
		var p: Vector2 = find["pos"]
		if p.y<4 or p.y>110: continue
		checked += 1
		var mount := massif.mount_find(find)
		var host: RockMassSpec = massif.masses_by_id.get(mount.host_mass)
		loot_clear = loot_clear and (host==null or host.landform!="shelf") and mount.holder_position().z>massif.wall_depth(p)+.3
	check(checked>0 and loot_clear,"finds lie on the face with no shelf of their own (%d)" % checked)
	var loot_holder := Node3D.new()
	a.add_child(loot_holder)
	LootVisuals.build(a,{"item":{"id":3,"tier":0,"kind":"coin","value":10},"pos":Vector2.ZERO,"rare":false},loot_holder,"balanced",-.8)
	var stone_meshes := 0
	for node in loot_holder.find_children("*","MeshInstance3D",true,false):
		if (node as MeshInstance3D).material_override==massif.stone_material: stone_meshes += 1
	check(stone_meshes==0 and loot_holder.find_child("Контактная тень",true,false)==null,"a coin hangs free: no stone and no painted shade under it")
	var treasure := loot_holder.find_child("Сокровище",false,false) as Node3D
	var player := treasure.get_node("Анимация") as AnimationPlayer if treasure!=null else null
	check(treasure!=null and treasure.find_child("Модель сокровища",true,false)!=null and treasure.find_children("*","MeshInstance3D",true,false).size()>0 and player.is_playing() and player.current_animation=="idle_spin",
		"a coin on the face is its authored 3D model turning in its idle animation")
	# The bag draws the very pictures of the face: the coin's turntable of
	# its model, the painted treasure itself; each item keeps its picture, and
	# an expedition's finds come from its own sheet.
	var icons_ok := TreasureModels.icon_texture({"kind":"coin"}).get_width()==TreasureModels.PORTRAIT_CELL*TreasureModels.PORTRAIT_FRAMES
	for kind: String in TreasureModels.KINDS:
		if kind=="coin": continue
		var item := {"kind":kind,"set_id":"silk","id":7,"location_id":"stone_spires"}
		var path := TreasureModels.sprite_for(item)
		icons_ok = icons_ok and ResourceLoader.exists(path) and TreasureModels.icon_texture(item)!=null and path==TreasureModels.sprite_for(item.duplicate())
	var desert_ok := true
	var winter_ok := true
	for kind: String in ["amber","crystal","star","crown","chalice","idol","relic"]:
		for id in range(6):
			desert_ok = desert_ok and TreasureModels.sprite_for({"kind":kind,"id":id,"location_id":"stone_spires"}).get_file().begins_with("treasure_desert_")
			winter_ok = winter_ok and TreasureModels.sprite_for({"kind":kind,"id":id,"location_id":"sky_city"}).get_file().begins_with("treasure_winter_")
			var general := TreasureModels.sprite_for({"kind":kind,"id":id,"location_id":"green_peak"}).get_file()
			desert_ok = desert_ok and (general.begins_with("treasure_a_") or general.begins_with("treasure_b_"))
	check(icons_ok and desert_ok and winter_ok,"every treasure kind has its picture for the face and the bag, from the expedition's own set")
	# Sizes: every treasure about half a metre, none tiny and none oversized.
	var sizes_ok := true
	for kind: String in TreasureModels.KINDS:
		var model := TreasureModels.instantiate({"kind":kind},true)
		var model_box := AABB()
		var empty := true
		for mesh: MeshInstance3D in model.find_children("*","MeshInstance3D",true,false):
			model_box = mesh.get_aabb() if empty else model_box.merge(mesh.get_aabb())
			empty = false
		var extent := maxf(model_box.size.x,model_box.size.y)
		sizes_ok = sizes_ok and extent>=.44 and extent<=.6 and mesh_shadows(model)
		model.free()
	check(sizes_ok,"treasures are 0.44-0.6 m across and cast real shadows")
	# The price tag hangs from the find: a lit plate with the value in the
	# HUD font and the rarity lip, swinging with the model.
	var tag := LootVisuals.price_tag(a,treasure,{"kind":"coin","value":1250,"tier":0},true)
	var tag_label := tag.find_child("Цена",false,false) as Label3D
	var tag_plate := tag.find_child("Табличка цены",false,false) as MeshInstance3D
	check(tag.get_parent().name==TreasureModels.PIVOT and tag_label!=null and tag_label.text=="1250" and tag_label.font!=null and tag_plate!=null and tag_plate.cast_shadow==GeometryInstance3D.SHADOW_CASTING_SETTING_ON and tag_plate.material_override is StandardMaterial3D and (tag_plate.material_override as StandardMaterial3D).shading_mode!=BaseMaterial3D.SHADING_MODE_UNSHADED,
		"the price is a lit tag hanging from the find, in the HUD font")

	# Grip shells: several visual variants, collision polygon untouched.
	var grip_chunk := Node3D.new()
	a.add_child(grip_chunk)
	var shapes := {}
	var polygon_kept := true
	var no_pebbles := true
	var no_sticks := true
	for anchor in a.nearby_anchors(20,70):
		var before: PackedVector2Array = anchor["polygon"].duplicate()
		massif.build_anchor(anchor,grip_chunk)
		polygon_kept = polygon_kept and before==anchor["polygon"]
		var holder: Node3D = anchor["visual"]
		no_pebbles = no_pebbles and holder.find_child("Сколы",false,false)==null and holder.find_child("Каменное основание",false,false)==null
		no_sticks = no_sticks and holder.find_child("Корень",true,false)==null
		var signature := ""
		for child in holder.find_children("*","Node3D",true,false): signature += String(child.name).substr(0,6)+","
		shapes[signature] = true
	check(polygon_kept,"visual grips never change the gameplay polygon")
	check(no_pebbles,"grips carry no pebble chips or base ring of their own")
	check(no_sticks,"grips have no branches or sticks protruding through their playable surface")
	# Boulder grips keep a clean stone contact with no chips, moss or hanging
	# tufts inside the playable silhouette; wide blocks still split into stones.
	var footing_ok := true
	var split := 0
	var paint_on_top := true
	for anchor in a.nearby_anchors(20,70):
		var holder: Node3D = anchor["visual"]
		var spec: GripVisualSpec = anchor["visual_spec"]
		if spec.split: split += 1
		# No seam, recess or shade round the block; nothing grows in it.
		footing_ok = footing_ok and holder.find_child("Каменное гнездо",true,false)==null and holder.find_child("Мох и снег в шве",true,false)==null and holder.find_child("Контактная тень",true,false)==null
		var strip := holder.find_child("Полоса состояния",true,false) as MeshInstance3D
		var box: AABB = strip.get_aabb()
		var block := spec.bounds()
		paint_on_top = paint_on_top and box.end.y>=block.end.y-.18 and box.size.y<=block.size.y*.36 and box.size.x>=spec.front_width*.36 and box.size.x<=spec.front_width*(.9 if anchor["permanent"] else .72)
	check(footing_ok,"each grip stands out of the face with no recess, seam, chips or tufts round it")
	check(split>0 and split<a.nearby_anchors(20,70).size(),"some wide grips break into two stones, not all (%d)" % split)
	check(paint_on_top,"the status paint is a stroke across the crown of the boulder, not a plate over it")
	var lean := make_world(58273,"battery")
	var lean_chunk := Node3D.new()
	lean.add_child(lean_chunk)
	var lean_ok := true
	for anchor in lean.nearby_anchors(20,40):
		lean.visuals.build_anchor(anchor,lean_chunk)
		var holder: Node3D = anchor["visual"]
		lean_ok = lean_ok and holder.find_child("Каменное гнездо",true,false)==null and holder.find_child("Мох и снег в шве",true,false)==null and holder.find_child("Контактная тень",true,false)==null
	check(lean_ok,"battery also keeps the grip contact free of decorative sticks and tufts")
	lean.free()
	check(shapes.size()>=4,"grips have several distinct visual builds (%d)" % shapes.size())
	var strip_lit := true
	for node in grip_chunk.find_children("Полоса состояния*","MeshInstance3D",true,false):
		strip_lit = strip_lit and (node as MeshInstance3D).cast_shadow==GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	check(strip_lit,"status strips never add a second shadow line")
	# The block separates by volume and paint on its top chamfer, never a
	# contrast outline.
	var bands := grip_chunk.find_children("Полоса состояния","MeshInstance3D",true,false).size()
	var outlines := grip_chunk.find_children("Контур","MeshInstance3D",true,false).size()
	check(bands>=a.nearby_anchors(20,70).size() and outlines==0,"every grip has a painted band and no outline")
	var dials := 0
	var dial_ok := true
	for anchor in a.nearby_anchors(4,110):
		if int(anchor["kind"])!=1 or anchor.get("permanent",false): continue
		a.build_anchor(anchor,grip_chunk)
		dials += 1
		var label: Label3D = anchor["timer_dial"]["label"]
		dial_ok = dial_ok and label.text=="2,6" and label.outline_size>=6
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
	# The outcrop follows GripVisualSpec: about the gameplay width (a compact
	# boulder, never a plate wider than the hitbox), its
	# top on the hitbox top, a body dropping 0.22-1.0 m below the hitbox into
	# the mountain, a top face the camera sees (it carries the paint), real
	# depth and a back running into the rock; its front stays well behind the
	# hero's plane (z 3.2).
	var block_sized := true
	var clear_of_loot := true
	var before_hero := true
	for anchor in a.nearby_anchors(20,70):
		var holder: Node3D = anchor["visual"]
		var body := holder.find_child("Каменный выступ",true,false) as MeshInstance3D
		var box: AABB = body.get_aabb()
		var size: Vector2 = anchor["dimensions"]
		var spec: GripVisualSpec = anchor["visual_spec"]
		var drop := spec.front_height-size.y-.05
		# Width of what the camera sees: the buried back runs along the view
		# axis, sideways in block space when the face is turned.
		var low_x := INF
		var high_x := -INF
		for vertex: Vector3 in body.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]:
			if vertex.z<-.001: continue
			low_x = minf(low_x,vertex.x)
			high_x = maxf(high_x,vertex.x)
		block_sized = block_sized and high_x-low_x>=size.x*.92 and high_x-low_x<=size.x*1.15 and drop>=GripVisualSpec.MIN_DROP-.001 and drop<=1.0
		block_sized = block_sized and absf(spec.bounds().end.y-(size.y*.5+.05))<=.06 and spec.top_band_height>=.2 and spec.side_depth>=.7
		block_sized = block_sized and box.position.z<=-spec.back_embed+.001 and box.end.z>=spec.side_depth*.9 and spec.back_embed>=.4
		before_hero = before_hero and (holder.global_transform*body.transform*box.end).z<3.0
		# The body never reaches down onto a find under the grip.
		var p: Vector2 = anchor["pos"]
		var foot := p.y+spec.bounds().position.y
		for find in a.finds:
			var q: Vector2 = find["pos"]
			if q.y<p.y and absf(q.x-p.x)<spec.front_width*.5 and q.y+.45>foot: clear_of_loot = false
	check(block_sized,"grip outcrops follow the visual contract: about the hitbox width, a body below it, a visible top face, depth and an embedded back")
	check(clear_of_loot,"no grip outcrop reaches down onto a find below it")
	check(before_hero,"grip outcrops stay behind the hero's plane")
	var simple := true
	for id in range(300):
		for kind in range(5):
			var object := {"id":id,"kind":kind,"dimensions":Vector2(1.15+fposmod(id*.37,.9),.45+fposmod(id*.13,.35))}
			var shape := GripVisualSpec.for_grip(object,GripBiomeProfile.named("forest"),1.0 if id%2==0 else .2)
			simple = simple and not GripVisualSpec.crosses(shape.outline) and not GripVisualSpec.crosses(shape.front)
	check(simple,"outcrop silhouettes and front rims never cross themselves (no holes in the face)")
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
	check(battery_layers==0 and massif.far_layer_count()==0,"distant ranges are painted by the sky, never built as floating 3D bands")
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
	var clean_obstacles := 0
	var hazards := 0
	for obstacle in a.obstacles:
		if not obstacle.get("massif",false) or obstacle["pos"].y>110: continue
		massif.build_obstacle(obstacle,hazard_chunk)
		hazards += 1
		var visual: Node3D = obstacle["visual"]
		clean_obstacles += 1 if visual.find_child("Тёплая кромка",true,false)==null and visual.find_child("obstacle_ember",true,false)==null else 0
	check(hazards>0 and clean_obstacles==hazards,"obstacles have no bright stick-like overlays")
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
	var contact_shadows := true
	var lifetime_ok := true
	var permanent_seen := false
	var disposable_seen := false
	var single_contact := true
	var hosted := true
	for anchor in a.nearby_anchors(4,118):
		if anchor.get("reserve",false): continue
		massif.build_anchor(anchor,mount_chunk)
		var holder: Node3D = anchor["visual"]
		var mount: SurfaceMount = anchor["mount"]
		sockets = sockets and holder.find_child("Каменное гнездо",true,false)==null
		single_contact = single_contact and is_equal_approx(holder.position.z,mount.wall_z()+MountainVisuals.GRIP_STANDOFF) and is_equal_approx(mount.wall_z(),massif.wall_depth(anchor["pos"]))
		hosted = hosted and mount.host_mass>=0 and mount.surface_class!="" and mount.socket_center.is_equal_approx(Vector3(anchor["pos"].x,anchor["pos"].y,mount.wall_z()))
		match GripSpec.kind_of(anchor):
			GripSpec.SPRING:
				var arrow := holder.find_child("Направление выхода",true,false) as MeshInstance3D
				if holder.find_child("Изгиб",false,false)!=null and arrow!=null and arrow.mesh!=null and arrow.mesh.get_surface_count()>0 and arrow.get_aabb().size.length()>=.3: cues["spring"] = true
			GripSpec.ICE: if holder.find_child("Борозда скольжения",true,false)!=null and is_equal_approx((holder.find_child("Наклон",false,false) as Node3D).rotation.z,GripSpec.plate_tilt(anchor)) and absf(GripSpec.plate_tilt(anchor))>.1: cues["ice"] = true
			GripSpec.CRYSTAL: if holder.find_child("Кристалл",true,false)!=null: cues["crystal"] = true
			GripSpec.ROOT: if holder.find_child("Трещина",true,false)!=null: cues["root"] = true
		if anchor["permanent"]: fixed_ok = fixed_ok and holder.find_children("*крепление*","MeshInstance3D",true,false).size()+holder.find_children("Кольцо*","MeshInstance3D",true,false).size()>0
		# One soft contact shadow instead of a cast shadow torn by the facets.
		var body := holder.find_child("Каменный выступ",true,false) as MeshInstance3D
		var contact := holder.find_child("Тень зацепа",false,false) as MeshInstance3D
		contact_shadows = contact_shadows and contact!=null and body.cast_shadow==GeometryInstance3D.SHADOW_CASTING_SETTING_OFF and absf((contact.global_basis*Vector3.BACK).normalized().z-1.0)<.001
		# Lifetime reads at a glance: a whole stroke or a broken one.
		var paint_share := painted_share(holder.find_child("Полоса состояния",true,false) as MeshInstance3D)
		if GripSpec.lifetime(anchor)=="permanent":
			permanent_seen = true
			lifetime_ok = lifetime_ok and paint_share>.97
		elif GripSpec.lifetime(anchor)=="disposable":
			disposable_seen = true
			lifetime_ok = lifetime_ok and paint_share<.8
	check(contact_shadows,"every grip lies on one soft contact shadow facing the camera and casts no torn shadow")
	check(lifetime_ok and permanent_seen and disposable_seen,"permanent grips carry a whole stroke, disposable ones a broken stroke")
	check(sockets and single_contact,"every grip stands at one contact depth from its SurfaceMount, with no socket recess")
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
		shared = shared and holder.find_child("Прямоугольник",false,false)==null and holder.find_child("Блок",true,false)!=null
	for ledge in legacy.ledges:
		legacy.visuals.build_ledge(ledge,legacy_chunk)
		shared = shared and (ledge["visual"] as Node3D).find_child("Деревянная площадка",false,false)!=null
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
	# Ledges: an authored timber model whose deck top is the walking line,
	# standing on the stone over its whole footprint without entering it or
	# any grip, find or hazard, its front behind the hero's plane.
	var shelf_ok := true
	var shelves := 0
	var styles := {}
	for ledge in a.ledges:
		var top := float(ledge["top"])
		if top<4 or top>110 or ledge.has("bridge"): continue
		var before := [ledge["left"],ledge["right"],ledge["top"]]
		a.visuals.build_ledge(ledge,chunk_a)
		shelves += 1
		var holder: Node3D = ledge["visual"]
		var model := holder.find_child("Деревянная площадка",false,false) as Node3D
		var found := model!=null and ResourceLoader.exists(str(model.get_meta("model","")))
		if found:
			styles[ledge["platform_style"]] = true
			var box := AABB()
			var first := true
			for mesh: MeshInstance3D in model.find_children("*","MeshInstance3D",true,false):
				var part := holder.transform*model.transform*mesh.transform*mesh.get_aabb()
				box = part if first else box.merge(part)
				first = false
			var drop: float = WoodPlatform.DROP[ledge["platform_style"]]
			var clear := true
			for row in range(9):
				for column in range(13):
					var at := Vector2(lerpf(box.position.x,box.end.x,column/12.0),lerpf(box.position.y,box.end.y,row/8.0))
					clear = clear and massif.wall_depth(at)<box.position.z+.001
			var room: float = massif._room_under_ledge(ledge)
			found = found and absf(box.end.y-top)<.03 and box.position.x<=float(ledge["left"]) and box.end.x>=float(ledge["right"]) and box.end.z<=MountainVisuals.PLATFORM_FRONT+.01 and clear and box.size.y<=drop+.12 and (room>=drop or ledge["platform_style"]=="bracket")
		shelf_ok = shelf_ok and found and before==[ledge["left"],ledge["right"],ledge["top"]] and (ledge["mount"] as SurfaceMount).host_mass>=0
	check(shelves>0 and shelf_ok,"every ledge is a timber model on the walking line that never enters the stone (%d)" % shelves)
	check(styles.size()==2,"rest platforms use both support styles: %s" % str(styles.keys()))
	# A grip lifted out of a hollow runs back into the rock along the view
	# axis: nothing of it shows past its own silhouette as a slanted tail.
	var tails_ok := true
	var lifted := 0
	for anchor in a.anchors:
		if not is_instance_valid(anchor.get("visual")) or not anchor.has("visual_spec"): continue
		var spec: GripVisualSpec = anchor["visual_spec"]
		if spec.back_embed<.9: continue
		lifted += 1
		var block := (anchor["visual"] as Node3D).find_child("Блок",true,false) as Node3D
		var body := block.find_child("Каменный выступ",false,false) as MeshInstance3D
		var to_world: Transform3D = (anchor["visual"] as Node3D).transform*(block.get_parent() as Node3D).transform*block.transform
		# The face and the wall ring (frame z>=0) give the silhouette; the
		# buried back must project inside it.
		var silhouette := Rect2()
		var buried: Array[Vector2] = []
		for vertex: Vector3 in body.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]:
			var at := to_world*vertex
			if vertex.z>=-.001: silhouette = Rect2(Vector2(at.x,at.y),Vector2.ZERO) if silhouette.size==Vector2.ZERO and silhouette.position==Vector2.ZERO else silhouette.expand(Vector2(at.x,at.y))
			else: buried.append(Vector2(at.x,at.y))
		for point in buried: tails_ok = tails_ok and silhouette.grow(.1).has_point(point)
	check(lifted>0 and tails_ok,"lifted grips show no slanted tail past their silhouette (%d)" % lifted)
	# A consumed grip leaves nothing on the face.
	var consumed := false
	for anchor in a.anchors:
		if anchor.get("permanent",true) or not is_instance_valid(anchor.get("visual")): continue
		a.consume_anchor(anchor["id"])
		var holder: Node3D = anchor["visual"]
		# The seam belongs to the grip; grips cast real shadows instead of a disc decal.
		consumed = not holder.visible and holder.find_child("Каменное гнездо",true,false)==null and holder.find_child("Контактная тень",true,false)==null and not massif.has_method("_occlusion")
		break
	check(consumed,"consume_anchor hides the grip; no seam, contact disc or anything baked stays behind")
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
			if not String(child.name).begins_with("Декор_"): continue
			decor += 1
			if not child.find_children("Декор_crystal*","",true,false).is_empty(): crystals += 1
			var at := Vector2(child.position.x,child.position.y)
			on_faces = on_faces and massif.surface_query(at).valid()
		snow_caps += count_named(decor_chunk,"Растение_snow_plant")+count_named(decor_chunk,"Декор_stone_snow")+count_named(decor_chunk,"Декор_scree_snow")
		budget_ok = budget_ok and decor<=28 and crystals<=3
		decor_chunk.free()
	check(budget_ok,"decor and crystals stay within the balanced budget per chunk")
	check(on_faces,"every decor piece grows from a rock face")
	# Every sprite grows the way it is painted and where it belongs: what
	# stands has stone under its foot, what hangs has stone above it, a
	# climbing vine a wall behind it; and the place's climate picked it.
	var placed_ok := true
	var climate_ok := true
	var modes := {}
	for index in range(0,5):
		var chunk := Node3D.new()
		a.add_child(chunk)
		massif.build_chunk(index,chunk)
		for holder in chunk.get_children():
			if not String(holder.name).begins_with("Декор_") or holder.get_child_count()==0: continue
			var parts := String(holder.get_child(0).name).split("_")
			var kind := "_".join(parts.slice(1,parts.size()-1))
			if not FloraModels.CATALOGUE.has(kind): continue
			var mode := FloraModels.mode_of(kind,int(parts[parts.size()-1]))
			modes[mode] = int(modes.get(mode,0))+1
			var at := Vector2((holder as Node3D).position.x,(holder as Node3D).position.y)
			var size: Vector2 = ((holder.get_child(0) as MeshInstance3D).mesh as QuadMesh).size
			match mode:
				"hang": placed_ok = placed_ok and massif.stone_field(at+Vector2(0,.05))>=0
				"climb": placed_ok = placed_ok and not massif.open_at(at+Vector2(0,size.y*.55))
				_: placed_ok = placed_ok and massif.stone_field(at-Vector2(0,.15))>=0
			var here := FloraModels.climate(massif.profile_at(at.y))
			var foreign: Array = {"green":["cactus","dry_plant","vine_dry","snow_plant","vine_frost","icicle","tree_dead","tree_snow"],"dry":["bush","vine_green","snow_plant","vine_frost","icicle","tree_green","tree_snow"],"cold":["cactus","dry_plant","vine_dry","bush","vine_green","tree_green","tree_dead"]}[here]
			climate_ok = climate_ok and kind not in foreign
		chunk.free()
	check(placed_ok and modes.has("stand") and modes.has("hang") and modes.has("climb"),"sprites stand on stone, hang from it or climb a wall, as painted: %s" % str(modes))
	check(climate_ok,"every sprite belongs to the climate it grows in")
	# Landmarks are painted sprites and flag models only: no piece built of
	# faceted prisms is left.
	var landmarks := 0
	var crafted := true
	for index in range(0,8):
		var chunk := Node3D.new()
		a.add_child(chunk)
		massif.build_chunk(index,chunk)
		for holder in chunk.find_children("Крупный элемент*","Node3D",false,false)+chunk.find_children("Ориентир акта*","Node3D",false,false):
			landmarks += 1
			for mesh: MeshInstance3D in holder.find_children("*","MeshInstance3D",true,false):
				var flagged := false
				var node: Node = mesh
				while node!=holder and node!=null:
					if String(node.name) in ["Флаг на древке","Гирлянда флагов"]: flagged = true
					node = node.get_parent()
				crafted = crafted and (mesh.mesh is QuadMesh or flagged)
		chunk.free()
	check(landmarks>0 and crafted,"landmarks are built of painted sprites and flag models only (%d)" % landmarks)
	check(snow_caps>0,"the snow zone grows snow plants and snowy stones instead of grass (%d)" % snow_caps)
	# Location slots 1 and 2 use the same masses and mount contract.
	for location in [1,2]:
		var legacy := make_world(58273,"balanced",location,4)
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
		var plants := count_named(skin,"Растение")
		check(plants>0,"location %d grows its profile's plants" % location)
		legacy.free()
	# Chunk streaming: leaving and returning rebuilds the same chunks and
	# frees every mesh of the released ones.
	var streamed := MountainWorld.new()
	root.add_child(streamed)
	streamed.setup(58273,0,13)
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
