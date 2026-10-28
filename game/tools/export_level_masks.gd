extends SceneTree

# Writes the masks and brief of the levels as they stand now (LevelSource):
# the starting point for drawing them in the level editor.
#
#   Godot --headless --path game --script res://tools/export_level_masks.gd
#   ... -- --only=0:1          one level (location:route)
#
# silhouette and depth are read from the baked mountain; solid, route,
# branch, rest, difficulty, loot and one zone per hazard from its layout.
# Material and decor layers are left out: they derive from the relief.

const KIND_NAMES := ["stone","root","spring","ice","crystal"]
const ROUTE_RADIUS := 1.2
const BRANCH_RADIUS := .8

var only := ""

func _initialize() -> void:
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--only="): only = argument.trim_prefix("--only=")
	call_deferred("run")

func run() -> void:
	var count := 0
	for location in range(LevelCatalog.LEVELS.size()):
		for route in range(LevelCatalog.routes(location).size()):
			if not only.is_empty() and only!="%d:%d" % [location,route]: continue
			var level := LevelBake.find(location,route,MountainWorld.generation_version_for(location))
			if level==null:
				push_error("EXPORT %d:%d has no current bake" % [location,route])
				continue
			export_level(level)
			count += 1
	print("EXPORT_DONE levels=%d" % count)
	quit(0)

func export_level(level: LevelBake) -> void:
	var started := Time.get_ticks_msec()
	var world := MountainWorld.new()
	world.visuals_enabled = false
	root.add_child(world)
	world.setup(level.seed_value,level.location,level.generation_version,false,level.route)
	world.load_bake(level)
	var layout := world.layout as ExpeditionLayout
	var massif := world.visuals as MassifVisuals
	var source := LevelSource.new()
	var route_data: Dictionary = LevelCatalog.route(level.location,level.route)
	source.brief = {"id":LevelBake.directory(level.location,level.route).get_file(),"location":level.location,"route":level.route,
		"name":str(route_data.get("name","")),"height":level.height,"seeds":{"route":level.seed_value},"pins":[],"zones":[]}
	source.masks["silhouette"] = _relief(source,massif,false)
	source.masks["depth"] = _relief(source,massif,true)
	source.masks["solid"] = _solid(source,layout)
	var main_ids := {}
	for id in layout.main_route: main_ids[id] = true
	source.masks["route"] = source.new_mask()
	for index in range(layout.main_route.size()-1):
		_capsule(source,source.masks["route"],layout.anchors[layout.main_route[index]]["pos"],layout.anchors[layout.main_route[index+1]]["pos"],ROUTE_RADIUS)
	source.masks["branch"] = source.new_mask()
	for edge in layout.edges:
		if main_ids.has(edge.x) and main_ids.has(edge.y): continue
		_capsule(source,source.masks["branch"],layout.anchors[edge.x]["pos"],layout.anchors[edge.y]["pos"],BRANCH_RADIUS)
	source.masks["rest"] = source.new_mask()
	for ledge in layout.ledges:
		_rect(source,source.masks["rest"],Rect2(float(ledge["left"]),float(ledge["top"])-.4,float(ledge["right"])-float(ledge["left"]),.6),1.0)
	source.masks["difficulty"] = _difficulty(source,layout)
	source.masks["loot"] = _loot(source,layout)
	_zones(source,layout)
	source.brief["acts"] = _acts(layout)
	var budget := 0
	for find in layout.finds: budget += int(find["item"].get("value",0))
	source.brief["loot_budget"] = budget
	var error := source.save(LevelSource.source_directory(level.location,level.route))
	if error!=OK: push_error("EXPORT %s failed: %d" % [source.brief["id"],error])
	world.free()
	print("EXPORT %s masks=%d zones=%d in %d ms" % [source.brief["id"],source.masks.size(),source.brief["zones"].size(),Time.get_ticks_msec()-started])

# Stone presence (a soft edge one pixel wide) or the depth of the front face.
func _relief(source: LevelSource, massif: MassifVisuals, depth: bool) -> Image:
	var image := source.new_mask()
	for y in range(image.get_height()):
		for x in range(image.get_width()):
			var point := source.to_world(Vector2(x+.5,y+.5))
			var value := 0.0
			if depth:
				var hit := massif.surface_query(point)
				if hit.valid(): value = clampf((hit.position.z+5.0)/7.0,.02,1.0)
			else:
				value = clampf(.5+massif.stone_field(point)*LevelSource.PX_PER_UNIT,0,1)
			if value>0: image.set_pixel(x,y,Color(value,value,value))
		if y%128==0: massif.query_cache.clear()
	return image

func _solid(source: LevelSource, layout: MountainLayout) -> Image:
	var image := source.new_mask()
	for obstacle in layout.obstacles:
		var polygon := SolidGeometry.polygon(obstacle)
		var bounds := Rect2(polygon[0],Vector2.ZERO)
		for point in polygon: bounds = bounds.expand(point)
		_fill(source,image,bounds,func(point: Vector2) -> float: return 1.0 if Geometry2D.is_point_in_polygon(point,polygon) else 0.0)
	return image

# Brighter is easier: the gap between consecutive main grips, 2.5 units
# reading as easy and 6 as hard, smoothed over about two rows.
func _difficulty(source: LevelSource, layout: MountainLayout) -> Image:
	var image := source.new_mask()
	var rows := PackedFloat32Array()
	rows.resize(image.get_height())
	rows.fill(-1.0)
	for index in range(layout.main_route.size()-1):
		var a: Vector2 = layout.anchors[layout.main_route[index]]["pos"]
		var b: Vector2 = layout.anchors[layout.main_route[index+1]]["pos"]
		var hard := clampf((a.distance_to(b)-2.5)/3.5,0,1)
		for y in range(int(source.to_pixel(b).y),int(source.to_pixel(a).y)+1):
			if y>=0 and y<rows.size(): rows[y] = hard
	var last := 0.0
	for y in range(rows.size()-1,-1,-1):
		if rows[y]<0: rows[y] = last
		last = rows[y]
	var radius := 2*LevelSource.PX_PER_UNIT
	for y in range(rows.size()):
		var total := 0.0
		var count := 0
		for k in range(maxi(0,y-radius),mini(rows.size(),y+radius+1)):
			total += rows[k]
			count += 1
		var easy := 1.0-total/maxi(1,count)
		for x in range(image.get_width()): image.set_pixel(x,y,Color(easy,easy,easy))
	return image

# Treasure (not coins) as soft blobs, brighter for richer finds.
func _loot(source: LevelSource, layout: MountainLayout) -> Image:
	var image := source.new_mask()
	var richest := 1
	for find in layout.finds:
		if str(find["item"].get("family",""))!="coin": richest = maxi(richest,int(find["item"].get("value",0)))
	for find in layout.finds:
		if str(find["item"].get("family",""))=="coin": continue
		var weight := maxf(.35,float(find["item"].get("value",0))/richest)
		var center: Vector2 = find["pos"]
		_fill(source,image,Rect2(center-Vector2(1.2,1.2),Vector2(2.4,2.4)),func(point: Vector2) -> float: return weight*smoothstep(1.2,.4,point.distance_to(center)))
	return image

# One mask per hazard; its timing and force go into the brief.
func _zones(source: LevelSource, layout: MountainLayout) -> void:
	for hazard in layout.hazards:
		var image := source.new_mask()
		match str(hazard["kind"]):
			"field": _rect(source,image,hazard["rect"],1.0)
			"contact":
				var center: Vector2 = hazard["pos"]
				var radius := float(hazard.get("radius",.6))
				_fill(source,image,Rect2(center-Vector2.ONE*radius,Vector2.ONE*radius*2),func(point: Vector2) -> float: return 1.0 if point.distance_to(center)<=radius else 0.0)
			"falling":
				var radius := float(hazard.get("radius",.5))
				_rect(source,image,Rect2(float(hazard["x"])-radius,float(hazard["top"])-6.0,radius*2,6.0),1.0)
			"collapse":
				var ledge: Dictionary = layout.ledges[int(hazard["ledge"])]
				_rect(source,image,Rect2(float(ledge["left"]),float(ledge["top"])-.4,float(ledge["right"])-float(ledge["left"]),.6),1.0)
		var name := "zone_%d" % source.brief["zones"].size()
		source.masks[name] = image
		var params := {}
		for key in ["telegraph_time","active_time","calm_time","phase","radius","haze","affects_main"]:
			if hazard.has(key) and not is_inf(float(hazard[key]) if hazard[key] is float else 0.0): params[key] = hazard[key]
		if hazard.has("force"): params["force"] = [hazard["force"].x,hazard["force"].y]
		source.brief["zones"].append({"mask":name,"type":str(hazard["def"]),"kind":str(hazard["kind"]),"act":int(hazard.get("act",0)),"params":params})

func _acts(layout: ExpeditionLayout) -> Array:
	var result := []
	for index in range(layout.spans.size()):
		var span: Dictionary = layout.spans[index]
		var counts := {}
		var total := 0
		for anchor in layout.anchors:
			var y: float = anchor["pos"].y
			if y<float(span["y_start"]) or y>=float(span["y_end"]): continue
			var kind: String = KIND_NAMES[clampi(int(anchor["kind"]),0,KIND_NAMES.size()-1)]
			counts[kind] = int(counts.get(kind,0))+1
			total += 1
		var grips := {}
		for kind in counts: grips[kind] = snappedf(float(counts[kind])/maxi(1,total),.01)
		result.append({"id":str(span["id"]),"until":snappedf(float(span["y_end"]),.01),
			"biome":str(layout.span(index)["def"].get("biome_profile","")),"grips":grips})
	return result

# --- Painting helpers: max-blend over the shape's bounds only ---------------------

func _fill(source: LevelSource, image: Image, bounds: Rect2, value: Callable) -> void:
	var low := source.to_pixel(Vector2(bounds.position.x,bounds.end.y)).floor()
	var high := source.to_pixel(Vector2(bounds.end.x,bounds.position.y)).ceil()
	for y in range(maxi(0,int(low.y)),mini(image.get_height(),int(high.y)+1)):
		for x in range(maxi(0,int(low.x)),mini(image.get_width(),int(high.x)+1)):
			var amount: float = value.call(source.to_world(Vector2(x+.5,y+.5)))
			if amount>image.get_pixel(x,y).r: image.set_pixel(x,y,Color(amount,amount,amount))

func _rect(source: LevelSource, image: Image, rect: Rect2, value: float) -> void:
	_fill(source,image,rect,func(point: Vector2) -> float: return value if rect.has_point(point) else 0.0)

func _capsule(source: LevelSource, image: Image, a: Vector2, b: Vector2, radius: float) -> void:
	var bounds := Rect2(a,Vector2.ZERO).expand(b).grow(radius)
	_fill(source,image,bounds,func(point: Vector2) -> float:
		var distance := Geometry2D.get_closest_point_to_segment(point,a,b).distance_to(point)
		return smoothstep(radius,radius-.4,distance))
