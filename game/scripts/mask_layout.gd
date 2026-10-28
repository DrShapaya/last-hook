class_name MaskLayout
extends ExpeditionLayout

# A level generated from its painted source (LevelSource,
# docs/LEVEL_PIPELINE.md). The acts keep the expedition generator's beats,
# rises and rhythm; the masks decide where they go:
# - route rows follow the corridor: its centre carries the path and its width
#   bounds the zigzag;
# - pins take the row nearest to them;
# - the silhouette bounds the mountain (outside, outer_edge) and plans the
#   rock relief (`relief`), deep and broad where the painted mass is thick;
# - solid and rest masks add obstacles and platforms that keep every
#   transfer clear.
# All the game needs afterwards lives in the layout's own data (edge_rows,
# relief, ...), so a baked level carries no masks. Members starting with "_"
# are generation scratch and are not baked.

const ROW_STEP := .5
const REACH := 5.15
const CORRIDOR_MARGIN := .45
const DEFAULT_HALF := 3.0
const KINDS := {"stone":GripSpec.STONE,"root":GripSpec.ROOT,"spring":GripSpec.SPRING,"ice":GripSpec.ICE,"crystal":GripSpec.CRYSTAL}

var source: LevelSource
# [left, right] of the mountain every ROW_STEP from y=0.
var edge_rows := PackedVector2Array()
# Planned rock masses: [x, y, radius, depth 0..1, role].
var relief: Array = []
# Main route row -> grip kind forced by a pin.
var pinned_rows: Dictionary = {}
# What the masks asked for and could not get, for the editor and the bake log.
var mask_notes: Array = []
var masks_finished := false

var _inside := PackedFloat32Array()
var _corridor := PackedVector2Array()
var _rest_zones: Array[Rect2] = []
var _width := 0
var _height := 0

func use_source(level: LevelSource) -> void:
	source = level
	_width = source.size().x
	_height = source.size().y
	_inside = _signed_distance(_mask_bytes("silhouette"))
	_corridor = _corridor_rows()
	_build_edges()
	_plan_relief()
	for component in _components("rest"):
		var bounds := Rect2(component[0],Vector2.ZERO)
		for point in component: bounds = bounds.expand(point)
		_rest_zones.append(bounds.grow(1.2))

# --- Fields -------------------------------------------------------------------------

func _mask_bytes(layer: String) -> PackedByteArray:
	var image: Image = source.masks.get(layer)
	if image==null:
		var empty := PackedByteArray()
		empty.resize(_width*_height)
		return empty
	return image.get_data()

# Signed distance to the silhouette edge in units: positive inside the
# mountain. Two-pass chamfer (1, sqrt 2) over the mask, once each way.
func _signed_distance(bytes: PackedByteArray) -> PackedFloat32Array:
	var inside := _chamfer(bytes,true)
	var outside := _chamfer(bytes,false)
	var result := PackedFloat32Array()
	result.resize(bytes.size())
	for index in range(bytes.size()):
		result[index] = (inside[index]-outside[index])/LevelSource.PX_PER_UNIT
	return result

func _chamfer(bytes: PackedByteArray, solid: bool) -> PackedFloat32Array:
	var far := 1e9
	var distance := PackedFloat32Array()
	distance.resize(bytes.size())
	for index in range(bytes.size()): distance[index] = far if (bytes[index]>=128)==solid else 0.0
	var w := _width
	var h := _height
	for y in range(h):
		for x in range(w):
			var index := y*w+x
			var value := distance[index]
			if value==0.0: continue
			if x>0: value = minf(value,distance[index-1]+1.0)
			if y>0:
				value = minf(value,distance[index-w]+1.0)
				if x>0: value = minf(value,distance[index-w-1]+1.4142)
				if x<w-1: value = minf(value,distance[index-w+1]+1.4142)
			distance[index] = value
	for y in range(h-1,-1,-1):
		for x in range(w-1,-1,-1):
			var index := y*w+x
			var value := distance[index]
			if value==0.0: continue
			if x<w-1: value = minf(value,distance[index+1]+1.0)
			if y<h-1:
				value = minf(value,distance[index+w]+1.0)
				if x<w-1: value = minf(value,distance[index+w+1]+1.4142)
				if x>0: value = minf(value,distance[index+w-1]+1.4142)
			distance[index] = value
	return distance

func _pixel_index(point: Vector2) -> int:
	var pixel := source.to_pixel(point)
	var x := clampi(int(pixel.x),0,_width-1)
	var y := clampi(int(pixel.y),0,_height-1)
	return y*_width+x

func inside_distance(point: Vector2) -> float:
	return _inside[_pixel_index(point)] if not _inside.is_empty() else 0.0

# Corridor centre and half width (units) per mask row, bottom-up, following
# the span nearest the previous row's centre. Rows without corridor take the
# nearest painted row.
func _corridor_rows() -> PackedVector2Array:
	var bytes := _mask_bytes("route")
	var rows := PackedVector2Array()
	rows.resize(_height)
	var known: Array[int] = []
	var previous := 0.0
	for y in range(_height-1,-1,-1):
		var best := Vector2.INF
		var start := -1
		for x in range(_width+1):
			var on := x<_width and bytes[y*_width+x]>=128
			if on and start<0: start = x
			elif not on and start>=0:
				var left := source.to_world(Vector2(start,y+.5)).x
				var right := source.to_world(Vector2(x,y+.5)).x
				var span := Vector2((left+right)*.5,(right-left)*.5)
				if not best.is_finite() or absf(span.x-previous)<absf(best.x-previous): best = span
				start = -1
		if best.is_finite():
			rows[y] = best
			previous = best.x
			known.append(y)
		else:
			rows[y] = Vector2.INF
	if known.is_empty():
		for y in range(_height): rows[y] = Vector2(0,DEFAULT_HALF)
		mask_notes.append("Коридор маршрута не нарисован: путь идёт по центру")
		return rows
	for y in range(_height):
		if rows[y].is_finite(): continue
		var nearest: int = known[0]
		for candidate in known:
			if absi(candidate-y)<absi(nearest-y): nearest = candidate
		rows[y] = rows[nearest]
	return rows

func corridor_at(y: float) -> Vector2:
	if _corridor.is_empty(): return Vector2(0,DEFAULT_HALF)
	var row := clampi(int(source.to_pixel(Vector2(0,y)).y),0,_height-1)
	return _corridor[row]

# Mountain extent per height: the stone span holding the corridor (or the
# nearest one), so islands beside the massif do not widen it.
func _build_edges() -> void:
	edge_rows.clear()
	var y := 0.0
	var top := source.top()
	while y<=top+ROW_STEP:
		var row := clampi(int(source.to_pixel(Vector2(0,y)).y),0,_height-1)
		var center := corridor_at(y).x
		var best := Vector2(center-DEFAULT_HALF,center+DEFAULT_HALF)
		var best_gap := INF
		var start := -1
		for x in range(_width+1):
			var on := x<_width and _inside[row*_width+x]>0.0
			if on and start<0: start = x
			elif not on and start>=0:
				var left := source.to_world(Vector2(start,0)).x
				var right := source.to_world(Vector2(x,0)).x
				var gap := 0.0 if center>=left and center<=right else minf(absf(center-left),absf(center-right))
				if gap<best_gap:
					best_gap = gap
					best = Vector2(left,right)
				start = -1
		edge_rows.append(best)
		y += ROW_STEP

func outer_edge(y: float, side: int) -> float:
	if edge_rows.is_empty(): return super.outer_edge(y,side)
	var edges := edge_rows[clampi(int(y/ROW_STEP),0,edge_rows.size()-1)]
	return edges.x if side<0 else edges.y

func outside(point: Vector2, margin: float = .65) -> bool:
	if not _inside.is_empty(): return inside_distance(point)< -margin
	return super.outside(point,margin)

# --- Relief -------------------------------------------------------------------------

# Rock masses that fill the silhouette: broad ones where the painted mass is
# thick, small ones along its edges, until every stone pixel is covered.
# Greedy over sample points by depth into the mass.
func _plan_relief() -> void:
	relief.clear()
	var random := rng(0,811)
	var depth := _mask_bytes("depth")
	var candidates: Array = []
	var step := LevelSource.PX_PER_UNIT
	for y in range(step/2,_height,step):
		for x in range(step/2,_width,step):
			var inside := _inside[y*_width+x]
			if inside<.35: continue
			var jitter := Vector2(random.randf_range(-.4,.4),random.randf_range(-.4,.4))
			candidates.append([inside,source.to_world(Vector2(x,y))+jitter,depth[y*_width+x]/255.0])
	candidates.sort_custom(func(a: Array, b: Array) -> bool: return a[0]>b[0])
	var placed: Array = []
	for candidate in candidates:
		var at: Vector2 = candidate[1]
		var covered := false
		for other in placed:
			if at.distance_to(Vector2(other[0],other[1]))<float(other[2])*.75:
				covered = true
				break
		if covered: continue
		# Boulders, not domes: a thick mass is built of several, so creases
		# between them read as in the hand-made massif.
		var radius := clampf(float(candidate[0])*.9,.8,3.0)
		var role := "body" if float(candidate[0])>3.2 else "island"
		var entry := [snappedf(at.x,.01),snappedf(at.y,.01),snappedf(radius,.01),snappedf(float(candidate[2]),.01),role]
		placed.append(entry)
	relief = placed

# --- Route --------------------------------------------------------------------------

func start_point(act: int) -> Vector2:
	var base := super.start_point(act)
	if source==null: return base
	var center := corridor_at(base.y).x
	# The hero starts at x 0 on the first ledge.
	return Vector2(clampf(center,-1.6,1.6) if act==0 else center,base.y)

# ExpeditionLayout._plan_act with the corridor in place of the fixed lateral
# bounds: the path drifts with the corridor centre, the zigzag turns at the
# corridor's sides, and no transfer is longer than the base kit reaches.
func _plan_act(act: int) -> void:
	if source==null:
		super._plan_act(act)
		return
	var info := span(act)
	var random := act_rng(act,0,20)
	var start := start_point(act)
	var target := start_point(act+1)
	var beats := beats_of(act)
	var counts: Array[int] = []
	for beat in beats: counts.append(int(BASE_ROWS[beat["beat"]]))
	var total := 0
	for count in counts: total += count
	var wanted := roundi((target.y-start.y)/LINK_RISE)
	var guard := 0
	while total<wanted and guard<12:
		guard += 1
		for index in range(beats.size()):
			var kind: String = beats[index]["beat"]
			if total<wanted and MAX_ROWS.has(kind) and counts[index]<int(MAX_ROWS[kind]):
				counts[index] += 1
				total += 1
	var steps: Array = []
	for index in range(beats.size()):
		var kind: String = beats[index]["beat"]
		if kind=="start": continue
		for step in range(counts[index]): steps.append([index,step])
	var rises: Array[float] = []
	var nominal := FINAL_RISE
	for entry in steps:
		var template: Array = STEPS[beats[entry[0]]["beat"]][entry[1]]
		nominal += float(template[1])
		rises.append(float(template[1]))
	var scale := (target.y-start.y)/nominal
	var first_row := route_points.size()
	route_points.append(start)
	row_info.append({"act":act,"beat":0,"step":0,"type":"start","def":beats[0]})
	var plan := {"index":act,"id":info["id"],"first_row":first_row,"start":start,"target":target,"beats":beats,"counts":counts,"variant":variant_of(act),"forks":[]}
	var point := start
	var direction := -1 if random.randf()<.5 else 1
	var authored := route_act(act)
	var sway := clampf(float(authored.get("sway",1.0)),.8,1.2)
	if not authored.is_empty(): direction = -1 if int(authored.get("dir",1))<0 else 1
	var last_direction := 0
	var fork_side := 1
	var remaining := steps.size()
	for k in range(steps.size()):
		var entry: Array = steps[k]
		var beat: Dictionary = beats[entry[0]]
		var kind: String = beat["beat"]
		var template: Array = STEPS[kind][entry[1]]
		var rise := rises[k]*scale+(random.randf_range(-.08,.08) if kind!="exit" else 0.0)
		var y := point.y+rise
		var corridor := corridor_at(y)
		var half := maxf(.3,corridor.y-CORRIDOR_MARGIN)
		# The path rides along with the corridor.
		var drift := clampf(corridor.x-corridor_at(point.y).x,-2.0,2.0)
		var base := point.x+drift
		var dx := 0.0
		match str(template[2]):
			"flip", "same":
				if template[2]=="flip": direction = -direction
				if remaining<=5 and absf(base-target.x)>3.0 and signf(target.x-base)!=direction: direction = -direction
				dx = float(template[0])*direction*sway
				if absf(base+dx-corridor.x)>half and absf(base-dx-corridor.x)<absf(base+dx-corridor.x):
					direction = -direction
					dx = -dx
			"bulge":
				if entry[1]==0:
					fork_side = -last_direction if last_direction!=0 else (-1 if random.randf()<.5 else 1)
					if absf(base+3.4*fork_side-corridor.x)>half+2.0: fork_side = -fork_side
					plan["forks"].append({"entry_row":first_row+k,"side":fork_side,"beat":entry[0]})
				direction = fork_side
				dx = float(template[0])*fork_side
			"back":
				direction = -fork_side
				dx = float(template[0])*direction
			"exit":
				var ideal := _exit_x(Vector2(base,point.y),target,random,direction)
				if entry[1]==0:
					var middle := (base+ideal)*.5
					dx = clampf(middle-base-direction*1.8*(1 if absf(ideal-base)<3.0 else 0),-3.6,3.6)
				else:
					dx = clampf(ideal-base,-3.6,3.6)
				if absf(dx)>.05: direction = int(signf(dx))
		if absf(dx)>.05: last_direction = int(signf(dx))
		var jitter := random.randf_range(-.12,.12) if kind in ["intro","teach","combo","rest"] else 0.0
		var x := base+dx+jitter
		# Inside the corridor (forks may lean out over their branch), then
		# within the base kit's reach of the previous grip.
		var limit := half+(2.0 if kind=="fork" else 0.0)
		if kind!="exit": x = clampf(x,corridor.x-limit,corridor.x+limit)
		var reach := sqrt(maxf(0.0,REACH*REACH-rise*rise))
		x = clampf(x,point.x-reach,point.x+reach)
		point = Vector2(x,y)
		route_points.append(point)
		row_info.append({"act":act,"beat":entry[0],"step":entry[1],"type":kind,"def":beat,"side":fork_side if kind=="fork" else direction})
		remaining -= 1
	_apply_pins(first_row,route_points.size()-1)
	for fork in plan["forks"]:
		var entry_row: int = int(fork["entry_row"])
		var low := route_points[entry_row]
		var high := route_points[entry_row+3]
		var spot := (low+high)*.5+Vector2(-int(fork["side"])*1.6,0)
		fork["spot"] = spot
		for row in range(entry_row,entry_row+4): reserved_spots[row] = reserved_spots.get(row,[])+[spot]
	act_plans.append(plan)

# A pin of a route grip type (stone, spring) takes the nearest ordinary row
# within 1.6 units of height when both neighbours stay within reach; other
# pins are added as extra grips once the route exists.
func _apply_pins(first: int, last: int) -> void:
	for pin in source.brief.get("pins",[]):
		var at := Vector2(pin["pos"][0],pin["pos"][1])
		var kind: int = KINDS.get(str(pin.get("type","stone")),GripSpec.STONE)
		if not GripSpec.network_kind(kind): continue
		var best := -1
		for row in range(first+1,last+1):
			if str(row_info[row]["type"]) in ["fork","exit"] or pinned_rows.has(row): continue
			if absf(route_points[row].y-at.y)>1.6: continue
			if best<0 or absf(route_points[row].y-at.y)<absf(route_points[best].y-at.y): best = row
		if best<0: continue
		var before := route_points[best-1]
		var after := route_points[best+1] if best+1<=last else at
		if at.y<=before.y or at.distance_to(before)>REACH or at.distance_to(after)>REACH or after.y<=at.y:
			mask_notes.append("Пин %s на высоте %d м недостижим из маршрута" % [pin.get("type","stone"),roundi(at.y*10)])
			continue
		route_points[best] = at
		pinned_rows[best] = kind

# Painted rest areas are kept free of the generator's extra grips, so their
# platforms fit later.
func crowded(point: Vector2) -> bool:
	for zone in _rest_zones:
		if zone.has_point(point): return true
	return super.crowded(point)

func branch_allowed(point: Vector2, index: int) -> bool:
	for zone in _rest_zones:
		if zone.has_point(point): return false
	return super.branch_allowed(point,index)

func _main_kind(index: int, random: RandomNumberGenerator) -> int:
	var kind := super._main_kind(index,random)
	return int(pinned_rows.get(index,kind))

# Painted solid is the level's whole say on obstacles: the generator's own
# encounter blocks stay out when the mask has any.
func _build_obstacles(index: int, encounter: Dictionary) -> void:
	if source!=null and not _components_empty("solid"): return
	super._build_obstacles(index,encounter)

var _solid_painted := -1

func _components_empty(layer: String) -> bool:
	if _solid_painted<0:
		_solid_painted = 0
		for value in _mask_bytes(layer):
			if value>=128:
				_solid_painted = 1
				break
	return _solid_painted==0

# --- After the route ----------------------------------------------------------------

func generate_to(height: float, is_finite: bool, summit_height: float) -> void:
	super.generate_to(height,is_finite,summit_height)
	if source==null or masks_finished or not summit_added: return
	masks_finished = true
	_add_free_pins()
	_add_mask_obstacles()
	_add_mask_rests()

func _add_free_pins() -> void:
	for pin in source.brief.get("pins",[]):
		var at := Vector2(pin["pos"][0],pin["pos"][1])
		var kind: int = KINDS.get(str(pin.get("type","stone")),GripSpec.STONE)
		var taken := false
		for id in nearby_ids(at.y-1,at.y+1):
			if anchors[id]["pos"].distance_to(at)<.3: taken = true
		if taken: continue
		var id := _add_anchor(at,kind,Vector2(1.8,.65))
		anchors[id]["role"] = "auxiliary"
		if str(pin.get("lifetime",""))=="permanent": anchors[id]["permanent"] = true
		_add_edges_near(id)

# Links a free grip to every grip it reaches, as the generator does for its
# auxiliary grips.
func _add_edges_near(id: int) -> void:
	var at: Vector2 = anchors[id]["pos"]
	for other in nearby_ids(at.y-REACH,at.y+REACH):
		if other==id: continue
		var there: Vector2 = anchors[other]["pos"]
		if at.distance_to(there)<=REACH and transition_clear(at,there):
			_add_edge(Vector2i(other,id) if there.y<at.y else Vector2i(id,other))

# Painted solid becomes convex obstacles. One that would block a transfer,
# cover a grip, find or platform is left out and noted.
func _add_mask_obstacles() -> void:
	for component in _components("solid"):
		var hull := Geometry2D.convex_hull(component)
		if hull.size()<4: continue
		var bounds := Rect2(hull[0],Vector2.ZERO)
		for point in hull: bounds = bounds.expand(point)
		var center := bounds.get_center()
		var polygon := PackedVector2Array()
		for point in hull.slice(0,hull.size()-1): polygon.append(point-center)
		var candidate := {"pos":center,"dimensions":bounds.size,"polygon":polygon,"type":"pillar" if bounds.size.y>bounds.size.x else "wedge","encounter":true,"massif":true,"rest":false,"mask":true}
		if _obstacle_conflicts(candidate):
			mask_notes.append("Выступ на высоте %d м перекрыл бы маршрут и не поставлен" % roundi(center.y*10))
			continue
		obstacles.append(candidate)

func _obstacle_conflicts(candidate: Dictionary) -> bool:
	for anchor in anchors:
		if not SolidGeometry.cast(anchor["pos"],anchor["pos"],candidate,Vector2(.9,.9)).is_empty(): return true
	for find in finds:
		if not SolidGeometry.cast(find["pos"],find["pos"],candidate,Vector2(.6,.6)).is_empty(): return true
	for ledge in ledges:
		var deck := Rect2(float(ledge["left"])-.5,float(ledge["top"])-1.0,float(ledge["right"])-float(ledge["left"])+1.0,3.0)
		if Rect2(candidate["pos"]-candidate["dimensions"]*.5,candidate["dimensions"]).intersects(deck): return true
	for edge in edges:
		if not transition_clear(anchors[edge.x]["pos"],anchors[edge.y]["pos"],candidate): return true
	return false

# Painted rest areas become platforms at the top of each painted patch. A
# grip standing in the deck cuts it; the widest free part is kept if it is
# still a platform (1.2 units).
func _add_mask_rests() -> void:
	for component in _components("rest"):
		var bounds := Rect2(component[0],Vector2.ZERO)
		for point in component: bounds = bounds.expand(point)
		var top := bounds.end.y
		var free: Array[Vector2] = [Vector2(bounds.position.x,bounds.end.x)]
		for id in nearby_ids(top-2,top+2):
			var grip: Vector2 = anchors[id]["pos"]
			if absf(grip.y-top)>=1.4: continue
			free = _cut(free,Vector2(grip.x-.8,grip.x+.8))
		for ledge in ledges:
			if absf(float(ledge["top"])-top)<1.5: free = _cut(free,Vector2(float(ledge["left"])-.3,float(ledge["right"])+.3))
		var best := Vector2.ZERO
		for part in free:
			if part.y-part.x>best.y-best.x: best = part
		if best.y-best.x<1.2:
			mask_notes.append("Площадка на высоте %d м не поместилась между опорами" % roundi(top*10))
			continue
		ledges.append({"left":best.x,"right":best.y,"top":top,"style":int(rng(roundi(top*10),330).randi_range(0,2)),"role":"rest","mask":true})

static func _cut(parts: Array[Vector2], hole: Vector2) -> Array[Vector2]:
	var result: Array[Vector2] = []
	for part in parts:
		if hole.y<=part.x or hole.x>=part.y:
			result.append(part)
			continue
		if hole.x>part.x: result.append(Vector2(part.x,hole.x))
		if hole.y<part.y: result.append(Vector2(hole.y,part.y))
	return result

# Connected patches of a mask (value >= .5), as world-space pixel corners.
func _components(layer: String) -> Array:
	var bytes := _mask_bytes(layer)
	var seen := PackedByteArray()
	seen.resize(bytes.size())
	var result: Array = []
	for start in range(bytes.size()):
		if bytes[start]<128 or seen[start]: continue
		var points := PackedVector2Array()
		var stack: Array[int] = [start]
		seen[start] = 1
		while not stack.is_empty():
			var index: int = stack.pop_back()
			var x := index%_width
			var y := index/_width
			for corner in [Vector2(x,y),Vector2(x+1,y),Vector2(x,y+1),Vector2(x+1,y+1)]: points.append(source.to_world(corner))
			for next in [index-1,index+1,index-_width,index+_width]:
				if next<0 or next>=bytes.size() or seen[next] or bytes[next]<128: continue
				if (next==index-1 and x==0) or (next==index+1 and x==_width-1): continue
				seen[next] = 1
				stack.append(next)
		if points.size()>=16: result.append(points)
	return result
