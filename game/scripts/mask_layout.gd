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
# What the rock is made of: boulders, or the RockSurface of "desert" or
# "winter", built from this coarse field of the mask.
var rock_form: String = "boulder"
# What a location's rock marks on its face (winter: its shelves).
var rock_marks: Array = []
# Rocks wedged over gaps for the route: stone the mask itself does not have.
var wedged_rocks: Array = []
var rock_grid: PackedFloat32Array = PackedFloat32Array()
var rock_grid_size: Vector2i = Vector2i.ZERO
var rock_grid_origin: Vector2 = Vector2.ZERO
var rock_grid_step: float = .5
# Main route row -> grip kind forced by a pin.
var pinned_rows: Dictionary = {}
# What the masks asked for and could not get, for the editor and the bake log.
var mask_notes: Array = []
var masks_finished := false
# Filler grips in columns across the face (the expedition generator's); off
# for drawn levels unless the brief asks for them.
var filler_grips := false

var _inside := PackedFloat32Array()
var _corridor := PackedVector2Array()
var _rest_zones: Array[Rect2] = []
var _width := 0
var _height := 0

func use_source(level: LevelSource) -> void:
	source = level
	filler_grips = bool(source.brief.get("filler_grips",false))
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

# Objects keep 0.9 units clear of the painted edge, so the stone seats under
# them never grow over sky windows and gaps.
const EDGE_CLEAR := .9

func outside(point: Vector2, margin: float = .65) -> bool:
	if not _inside.is_empty(): return inside_distance(point)<EDGE_CLEAR-margin
	return super.outside(point,margin)

# --- Relief -------------------------------------------------------------------------

# Rock masses that fill the silhouette: broad ones where the painted mass is
# thick, small ones along its edges, until every stone pixel is covered.
# Greedy over sample points by depth into the mass.
func _plan_relief() -> void:
	relief.clear()
	rock_form = str(source.brief.get("rock","boulder"))
	rock_marks = source.brief.get("marks",source.brief.get("shelves",[]))
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

# The mask as a coarse distance field: all a RockSurface needs of it, kept in
# the bake with the layout.
func _store_rock_grid() -> void:
	if rock_form=="boulder": return
	rock_grid_origin = Vector2(LevelSource.X_MIN,-3.0)
	var top := float(source.brief.get("height",120.0))+7.0
	rock_grid_size = Vector2i(roundi((LevelSource.X_MAX-LevelSource.X_MIN)/rock_grid_step)+1,roundi((top-rock_grid_origin.y)/rock_grid_step)+1)
	rock_grid.resize(rock_grid_size.x*rock_grid_size.y)
	for y in range(rock_grid_size.y):
		for x in range(rock_grid_size.x):
			rock_grid[y*rock_grid_size.x+x] = snappedf(inside_distance(rock_grid_origin+Vector2(x,y)*rock_grid_step),.01)

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
	if act>0 and bool(source.brief.get("free_route",false)):
		# The last act ends wherever its stone let it: the new one starts in
		# reach of that.
		var last: Vector2 = route_points[-1]
		var across := sqrt(maxf(0.0,REACH*REACH-pow(start.y-last.y,2)))
		start.x = _stone_x(clampf(start.x,last.x-across,last.x+across),start.y,last.x-across,last.x+across)
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
				dx = float(template[0])*direction*_sway_at(y,sway)
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
		x = _stone_x(x,y,point.x-reach,point.x+reach)
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

# Width of the zigzag at a height: the brief's `pace` (from the designer:
# wide swings on walls, near-level hops on traverses) or the route's own.
func _sway_at(y: float, fallback: float) -> float:
	for entry in source.brief.get("pace",[]):
		if y>=float(entry["from"]) and y<float(entry["to"]): return clampf(float(entry["sway"]),.8,1.6)
	return fallback

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

# The generator lays its extra grips in columns across the face and only
# clamps them to the outer edge; on a painted mountain a column can fall in
# a gap or window. Such a spot slides towards the corridor onto stone.
func auxiliary_point(index: int, column: int, point: Vector2, random: RandomNumberGenerator) -> Vector2:
	# A drawn level has no filler columns: every side grip belongs to a
	# branch, a fork or a split path. Returning the row's own point makes the
	# generator skip the column.
	if source!=null and not filler_grips: return point
	var candidate := super.auxiliary_point(index,column,point,random)
	if _inside.is_empty() or inside_distance(candidate)>=EDGE_CLEAR: return candidate
	var center := corridor_at(candidate.y).x
	var step := signf(center-candidate.x)*.25
	var probe := candidate
	for attempt in range(int(absf(center-candidate.x)/.25)+1):
		probe.x += step
		if inside_distance(probe)>=EDGE_CLEAR: return probe
	return candidate

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

# --- Split paths --------------------------------------------------------------------
#
# A split is a second way up, chosen at a main grip and rejoining the main
# route rows later. The brief gives its line (`splits`: path, style) on a
# ridge of its own; grips go along that line at the style's hop length, each
# within base-kit reach of the last and on painted stone. No grip of the
# split comes within ISOLATION of the main route between its ends, so once
# on one way the player stays on it: even the longest rope (8.8) cannot
# cross.

const ISOLATION := 9.4
const HOPS := {"ledge":[4.2,.35,0.0],"ridge":[3.4,.25,.9],"arc":[3.9,.3,0.0],"stones":[4.2,.2,0.0],"diagonal":[4.4,.3,.4],"butte":[4.4,.3,.3]}  # length, length jitter, side swing

# Finds of a main stretch that move onto its split's second way.
const SPLIT_LOOT_OUT := 6.0
const SPLIT_LOOT := ["main_safe","detour","choice","route_treasure","route_cache","fork_collection","fork_risky_shortcut","fork_speed"]

var splits_built: Array = []
var _split_spots: Array[Vector2] = []
# Why split spots were turned down, by reason (for tools and the editor).
var split_rejects: Dictionary = {}
var splits_done := false

func _rows_done(complete: bool) -> void:
	if source==null or not complete or splits_done: return
	splits_done = true
	for index in range(source.brief.get("splits",[]).size()): _build_split(index,source.brief["splits"][index])

# On a mask that owes the route no stone, the nearest place on stone along the
# row, within the given range.
func _stone_x(x: float, y: float, low: float, high: float) -> float:
	if not bool(source.brief.get("free_route",false)): return x
	for step in range(0,17):
		for sign_x in [1.0,-1.0]:
			var probe: float = x+sign_x*step*.35
			if probe>=low and probe<=high and inside_distance(Vector2(probe,y))>=EDGE_CLEAR+.1: return probe
	_wedge_rock(Vector2(x,y))
	return x

# No stone in reach: a rock wedged in the gap carries the grip, the way
# chockstones hang in real slots. It joins the mask and the relief.
func _wedge_rock(at: Vector2) -> void:
	var center := source.to_pixel(at)
	var radius := roundi(2.2*LevelSource.PX_PER_UNIT)
	for y in range(maxi(0,int(center.y)-radius),mini(_height,int(center.y)+radius+1)):
		for x in range(maxi(0,int(center.x)-radius),mini(_width,int(center.x)+radius+1)):
			var depth := 2.2-Vector2(x-center.x,y-center.y).length()/LevelSource.PX_PER_UNIT
			if depth>0.0: _inside[y*_width+x] = maxf(_inside[y*_width+x],depth)
	relief.append([snappedf(at.x,.01),snappedf(at.y,.01),1.6,.55,"island"])
	wedged_rocks.append(at)

# An end of a split's line, drawn in to the nearest main grip below it (or
# above it) when that grip's zigzag swung out of reach.
func _toward_main(point: Vector2, below: bool) -> Vector2:
	var nearest := Vector2.INF
	for id in main_route:
		var at: Vector2 = anchors[id]["pos"]
		if (at.y<point.y)==below and at.distance_to(point)<nearest.distance_to(point): nearest = at
	if not nearest.is_finite() or nearest.distance_to(point)<=REACH: return point
	return nearest+(point-nearest).limit_length(REACH-.3)

# Splits take finds from their main stretches, so loot waits for all rows.
func _loot_limit(limit: float) -> float:
	return limit if limit==INF or source==null else -INF

func _build_split(index: int, spec: Dictionary) -> void:
	var path := PackedVector2Array()
	for point in spec.get("path",[]): path.append(Vector2(point[0],point[1]))
	if path.size()<2: return
	path[0] = _toward_main(path[0],true)
	path[-1] = _toward_main(path[-1],false)
	var style := str(spec.get("style","ledge"))
	var hop: Array = HOPS.get(style,HOPS["ledge"])
	# The main grips it leaves from and returns to.
	var entry_row := -1
	var exit_row := -1
	for row in range(main_route.size()):
		var at: Vector2 = anchors[main_route[row]]["pos"]
		if at.y<path[0].y and at.distance_to(path[0])<=REACH and (entry_row<0 or at.y>anchors[main_route[entry_row]]["pos"].y): entry_row = row
		if at.y>=path[-1].y and at.distance_to(path[-1])<=REACH and exit_row<0: exit_row = row
	if entry_row<0 or exit_row<=entry_row+2:
		mask_notes.append("Развилка %d: нет опоры основного пути у её начала или конца" % (index+1))
		return
	var entry: Vector2 = anchors[main_route[entry_row]]["pos"]
	var exit: Vector2 = anchors[main_route[exit_row]]["pos"]
	var line := PackedVector2Array([entry])
	line.append_array(path)
	line.append(exit)
	var random := rng(index,733)
	var points := PackedVector2Array()
	var previous := entry
	var distance := 0.0
	var total := _line_length(line)
	var swing := 1.0
	# Strict isolation holds where the line is far across from the main
	# route; near the split's ends the two ways still meet.
	var main_axis := (entry.x+exit.x)*.5
	while true:
		var step := float(hop[0])+random.randf_range(-float(hop[1]),float(hop[1]))
		distance += step
		if distance>=total-step*.6: break
		var along := _along(line,distance)
		var point: Vector2 = along[0]+(along[1] as Vector2).orthogonal()*float(hop[2])*swing
		swing = -swing
		var strict := absf(float(along[0].x)-main_axis)>=ISOLATION+2.4
		split_rejects.clear()
		var placed := _place_split_grip(point,previous,entry_row,exit_row,strict)
		if not placed.is_finite():
			mask_notes.append("Развилка %d: не нашлось места для опоры у x %.1f, %d м (от x %.1f, %d м; %s)" % [index+1,point.x,roundi(point.y*10),previous.x,roundi(previous.y*10),str(split_rejects)])
			return
		points.append(placed)
		previous = placed
		distance = _project(line,placed)
	# Short closing hops while the main grip is still out of reach.
	var closing := 0
	while (previous.distance_to(exit)>REACH-.2 or not transition_clear(previous,exit)) and closing<3:
		closing += 1
		var toward := previous+(exit-previous).limit_length(REACH-.6)
		var placed := _place_split_grip(toward,previous,entry_row,exit_row,false)
		if not placed.is_finite(): break
		points.append(placed)
		previous = placed
	if previous.distance_to(exit)>REACH or not transition_clear(previous,exit) or points.size()<2:
		mask_notes.append("Развилка %d не возвращается на основной путь: от x %.1f, %d м до опоры x %.1f, %d м (%.1f)" % [index+1,previous.x,roundi(previous.y*10),exit.x,roundi(exit.y*10),previous.distance_to(exit)])
		return
	# Built only when complete: grips, links, rewards.
	var ids: Array[int] = []
	var from_id: int = main_route[entry_row]
	for point in points:
		var id := _add_anchor(point,GripSpec.STONE,Vector2(random.randf_range(1.5,1.9),random.randf_range(.55,.7)))
		anchors[id]["role"] = "auxiliary"
		anchors[id]["split"] = index
		anchors[id]["permanent"] = false
		_add_edge(Vector2i(from_id,id))
		from_id = id
		ids.append(id)
	_add_edge(Vector2i(from_id,main_route[exit_row]))
	# The crystal at the parting points at both ways.
	var fork: Dictionary = anchors[main_route[entry_row]]
	fork["kind"] = GripSpec.CRYSTAL
	fork["fork"] = index
	fork.erase("exit_dir")
	fork["choice_exits"] = [main_route[entry_row+1],ids[0]]
	if economy_loot: _stock_split(entry_row,exit_row,points)
	splits_built.append({"entry":main_route[entry_row],"exit":main_route[exit_row],"grips":ids,"style":style})

# The second way is where the reward is. The valuables of the main stretch
# move onto it, so the direct way is quick and poor and the long way pays:
# coins from the first hop on (seen from the crystal), a set part on the way
# out, a treasure on the far turn and a cache on the way back.
func _stock_split(entry_row: int, exit_row: int, points: PackedVector2Array) -> void:
	_split_spots.clear()
	var entry: Vector2 = anchors[main_route[entry_row]]["pos"]
	var exit: Vector2 = anchors[main_route[exit_row]]["pos"]
	var far := 0
	var out: Array[int] = []
	for k in range(points.size()):
		if absf(points[k].x-entry.x)>absf(points[far].x-entry.x): far = k
		if absf(points[k].x-(entry.x+exit.x)*.5)>=SPLIT_LOOT_OUT: out.append(k)
	if out.is_empty(): out.append(far)
	var slot := 0
	for request in loot_plan.pending:
		if int(request["row"])<=entry_row or int(request["row"])>=exit_row or not str(request["role"]) in SPLIT_LOOT: continue
		request["pos"] = _split_spot(points,out[slot%out.size()],entry_row)
		request["from"] = Vector2.INF
		slot += 1
	# Trails run close under the line: the stone band is narrow.
	for k in range(-1,points.size()):
		var from: Vector2 = entry if k<0 else points[k]
		var to: Vector2 = points[k+1] if k+1<points.size() else exit
		loot_plan.request(entry_row,from+Vector2(0,.1),"trail",to+Vector2(0,.1),{"count":3})
	loot_plan.request(entry_row,_split_spot(points,far,entry_row),"route_treasure")
	loot_plan.request(entry_row,_split_spot(points,out[0],entry_row),"detour")
	loot_plan.request(entry_row,_split_spot(points,out[-1],entry_row),"route_cache")

# A free place for a find beside a grip of the second way, on its stone;
# the neighbouring grips when that one has none.
func _split_spot(points: PackedVector2Array, index: int, row: int) -> Vector2:
	for step in [0,-1,1,-2,2]:
		var grip: Vector2 = points[clampi(index+int(step),0,points.size()-1)]
		for offset in [Vector2(0,-1.45),Vector2(.6,-1.3),Vector2(-.6,-1.3),Vector2(1.35,0),Vector2(-1.35,0),Vector2(0,1.4),Vector2(1.3,1.0),Vector2(-1.3,1.0)]:
			var spot: Vector2 = grip+offset
			if not loot_plan.clear(spot,row): continue
			var free := true
			for taken in _split_spots:
				if spot.distance_to(taken)<LootPlacement.FIND_SPACING+.1: free = false
			if free:
				_split_spots.append(spot)
				return spot
	return points[index]+Vector2(0,-1.45)

func _in_split(y: float) -> bool:
	if source==null: return false
	for spec in source.brief.get("splits",[]):
		if y>=float(spec["from"])-1.0 and y<=float(spec["to"])+1.0: return true
	return false

# A crystal means a real parting, so drawn levels keep it for the splits, and
# a split's main stretch has no side grips of its own.
func _beat_detour(index: int, point: Vector2, entry: int, zone: int, info: Dictionary) -> void:
	if source!=null and (int(info["def"]["branch"])==GripSpec.CRYSTAL or _in_split(point.y)): return
	super._beat_detour(index,point,entry,zone,info)

func _fork(index: int, point: Vector2, entry: int, zone: int, info: Dictionary) -> void:
	if not _in_split(point.y): super._fork(index,point,entry,zone,info)

# A split grip near `point`: on stone, within reach of the previous grip,
# clear of other grips, and in the middle of the split (`strict`) beyond any
# rope's reach of the main route between the split's ends. Near its ends the
# two ways still meet. Nearest fitting spot first; INF when none.
func _place_split_grip(point: Vector2, previous: Vector2, entry_row: int, exit_row: int, strict: bool) -> Vector2:
	var candidates: Array[Vector2] = [point]
	for ring in range(1,7):
		for step in range(12): candidates.append(point+Vector2.from_angle(TAU*step/12.0)*ring*.35)
	for candidate in candidates:
		if inside_distance(candidate)<EDGE_CLEAR:
			_reject("sky")
			continue
		if candidate.distance_to(previous)>REACH-.1 or candidate.distance_to(previous)<2.2:
			_reject("reach")
			continue
		if not transition_clear(previous,candidate):
			_reject("blocked")
			continue
		if crowded(candidate):
			_reject("crowded")
			continue
		var isolated := true
		if strict:
			for row in range(entry_row+1,exit_row):
				if anchors[main_route[row]]["pos"].distance_to(candidate)<ISOLATION: isolated = false
		if isolated: return candidate
		_reject("isolation")
	return Vector2.INF

func _reject(reason: String) -> void:
	split_rejects[reason] = int(split_rejects.get(reason,0))+1

static func _line_length(line: PackedVector2Array) -> float:
	var total := 0.0
	for k in range(1,line.size()): total += line[k-1].distance_to(line[k])
	return total

# Point and direction at an arc length along the line.
static func _along(line: PackedVector2Array, distance: float) -> Array:
	var left := distance
	for k in range(1,line.size()):
		var segment := line[k-1].distance_to(line[k])
		if left<=segment or k==line.size()-1:
			var direction := (line[k]-line[k-1]).normalized()
			return [line[k-1]+direction*minf(left,segment),direction]
		left -= segment
	return [line[-1],Vector2.UP]

# Arc length of the line's point nearest to `point`.
static func _project(line: PackedVector2Array, point: Vector2) -> float:
	var best := INF
	var result := 0.0
	var walked := 0.0
	for k in range(1,line.size()):
		var near := Geometry2D.get_closest_point_to_segment(point,line[k-1],line[k])
		var gap := near.distance_to(point)
		if gap<best:
			best = gap
			result = walked+line[k-1].distance_to(near)
		walked += line[k-1].distance_to(line[k])
	return result

# --- After the route ----------------------------------------------------------------

func generate_to(height: float, is_finite: bool, summit_height: float) -> void:
	super.generate_to(height,is_finite,summit_height)
	if source==null or masks_finished or not summit_added: return
	masks_finished = true
	_add_free_pins()
	_add_mask_obstacles()
	_add_mask_rests()
	_summit_ledge_last()
	_settle_on_stone()
	_seat_ledges()
	_store_rock_grid()
	_note_objects_in_sky()

# Side grips and finds the generator left over painted sky move to the
# nearest stone within 2 units, as long as every transfer of the grip stays
# within reach and clear. Main route grips are never moved.
func _settle_on_stone() -> void:
	var main := {}
	for id in main_route: main[id] = true
	var links := {}
	for edge in edges:
		links[edge.x] = links.get(edge.x,[])+[edge.y]
		links[edge.y] = links.get(edge.y,[])+[edge.x]
	for anchor in anchors:
		var id: int = anchor["id"]
		var from: Vector2 = anchor["pos"]
		if main.has(id) or str(anchor.get("role",""))!="auxiliary" or anchor.get("reserve",false) or inside_distance(from)>=EDGE_CLEAR: continue
		for spot in _stone_spots(from):
			var fits := true
			for other in links.get(id,[]):
				var there: Vector2 = anchors[other]["pos"]
				if spot.distance_to(there)>REACH or not transition_clear(spot,there): fits = false
			if not fits: continue
			_move_anchor(id,spot)
			break
	for find in finds:
		var at: Vector2 = find["pos"]
		if inside_distance(at)>=.4: continue
		var spots := _stone_spots(at)
		if not spots.is_empty():
			find["pos"] = spots[0]
			find["origin"] = spots[0]

# Stone points round a spot, nearest first (rings of 0.4 units).
func _stone_spots(at: Vector2) -> Array[Vector2]:
	var result: Array[Vector2] = []
	for ring in range(1,6):
		var radius := ring*.4
		for step in range(12):
			var spot := at+Vector2.from_angle(TAU*step/12.0)*radius
			if inside_distance(spot)>=EDGE_CLEAR: result.append(spot)
	return result

func _move_anchor(id: int, spot: Vector2) -> void:
	var old_key := int(floor(anchors[id]["pos"].y/CHUNK_HEIGHT))
	var new_key := int(floor(spot.y/CHUNK_HEIGHT))
	anchors[id]["pos"] = spot
	if old_key!=new_key:
		(bins[old_key] as Array).erase(id)
		if not bins.has(new_key): bins[new_key] = []
		bins[new_key].append(id)

# Grips, finds and platforms must stand on painted stone; their seats would
# otherwise fill a sky window or gap. Each one in the sky is noted.
var sky_objects := 0

# A platform the free route left over a gap rests on a wedged rock.
func _seat_ledges() -> void:
	if not bool(source.brief.get("free_route",false)): return
	for ledge in ledges:
		var at := Vector2((float(ledge["left"])+float(ledge["right"]))*.5,float(ledge["top"])-.3)
		if inside_distance(at)<.15: _wedge_rock(at+Vector2(0,-.5))

func _note_objects_in_sky() -> void:
	sky_objects = 0
	var points: Array = []
	for anchor in anchors: points.append(["Опора (%s)" % anchor.get("role",""),anchor["pos"]])
	for find in finds: points.append(["Находка",find["pos"]])
	for ledge in ledges: points.append(["Площадка",Vector2((float(ledge["left"])+float(ledge["right"]))*.5,float(ledge["top"])-.3)])
	for entry in points:
		var point: Vector2 = entry[1]
		if point.y<1.0 or point.y>summit: continue
		if inside_distance(point)<.15:
			sky_objects += 1
			mask_notes.append("%s в небе: x %.1f, %d м" % [entry[0],point.x,roundi(point.y*10)])

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

# The summit platform stays the last ledge, as on every other level.
func _summit_ledge_last() -> void:
	for index in range(ledges.size()):
		if absf(float(ledges[index]["top"])-(summit-.4))<.001 and not ledges[index].get("mask",false):
			var platform: Dictionary = ledges[index]
			ledges.remove_at(index)
			ledges.append(platform)
			return

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
