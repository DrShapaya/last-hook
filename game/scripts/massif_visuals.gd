class_name MassifVisuals
extends MountainVisuals

# Grips stand in front of the wall, never past this plane (gameplay is XY).
const GRIP_Z := 2.35
const FACET_SIZE := 1.3
const FAR_FACET_SIZE := 3.2
# Render-only boulder massif: the climbing face is a union of convex,
# faceted boulders laid around the route and every gameplay object.
const BOULDER_BAND := 24.0
const BOULDER_BIN := 4.0
const ROUTE_CLEAR := 2.4
const WALL_BACK := -2.2
const WALL_FRONT := 1.95
const RIM_LIP := .3
const RIM_FALL := 1.5
const STACK_SHARE := .3
# Distant parallax layers: depth, share of camera motion and haze.
const FAR_LAYERS := [{"z":-9.0,"follow":.42,"haze":.66,"cell":1.5},{"z":-15.0,"follow":.68,"haze":.80,"cell":2.0}]
var massif: MassifLayout
var rock_material := ShaderMaterial.new()
var flank_material := ShaderMaterial.new()
var far_materials: Array[ShaderMaterial] = []
# 0 is the climbing massif, 1 and 2 are the distant layers.
var layer := 0
var positions: Dictionary = {}
var normals: Dictionary = {}
var eval_cache: Dictionary = {}
var form_cache: Dictionary = {}
var facet_depths: Dictionary = {}
var facet_cells: Dictionary = {}
var facet_tones: Dictionary = {}
var route_cache: Dictionary = {}
var band_boulders: Dictionary = {}
var band_islands: Dictionary = {}
var boulder_bins: Dictionary = {}
var boulder_signature := Vector3i(-1,-1,-1)
var emitted_vertices := 0
var far_shader: Shader

func _init(owner_world: Node3D, source: MountainLayout) -> void:
	super._init(owner_world,source)
	massif = source as MassifLayout
	rock_material.shader = preload("res://shaders/massif_rock.gdshader")
	rock_material.set_shader_parameter("facet_strength",1.0)
	flank_material.shader = rock_material.shader
	flank_material.set_shader_parameter("facet_strength",1.0)
	flank_material.set_shader_parameter("detail_strength",.7)
	# Distant cliffs: one flat facet light, no shadow lookups, mixed into
	# the sky colour. Cheap enough for every preset, including phones.
	far_shader = Shader.new()
	far_shader.code = "shader_type spatial; render_mode unshaded, cull_disabled, shadows_disabled; uniform vec3 haze : source_color = vec3(.42,.68,.92); uniform float haze_amount = .7; varying vec3 world_pos; void vertex(){ world_pos=(MODEL_MATRIX*vec4(VERTEX,1.0)).xyz; } void fragment(){ vec3 n=normalize(cross(dFdx(world_pos),dFdy(world_pos))); if(n.z<0.0){ n=-n; } float l=dot(n,normalize(vec3(-.55,.62,.56))); vec3 c=COLOR.rgb*mix(.80,1.10,smoothstep(-.2,.9,l)); ALBEDO=mix(c,haze,haze_amount); }"
	for settings in FAR_LAYERS:
		var material := ShaderMaterial.new()
		material.shader = far_shader
		material.set_shader_parameter("haze_amount",settings["haze"])
		far_materials.append(material)

func far_layer_count() -> int:
	return 1 if quality=="battery" else FAR_LAYERS.size()

func zone_color(height: float) -> Color:
	# Warm, light limestone, slowly cooling towards the summit.
	var palette := [Color("6b6b61"),Color("6d6d63"),Color("6f6f66"),Color("6a6f72"),Color("6e6c67"),Color("7e8285")]
	var t := clampf(height/20,0,5)
	var index := mini(int(t),4)
	return palette[index].lerp(palette[index+1],smoothstep(0,1,t-index))

func _use_layer(value: int) -> void:
	# Every cache is per layer: the distant layers live in their own plane.
	if value==layer: return
	layer = value
	positions.clear()
	normals.clear()
	eval_cache.clear()
	form_cache.clear()
	facet_depths.clear()
	facet_cells.clear()
	facet_tones.clear()

func vertex(point: Vector2) -> Vector3:
	if not positions.has(point): positions[point] = Vector3(point.x,point.y,_depth(point))
	return positions[point]

func _depth(point: Vector2) -> float:
	# The stone is piecewise planar over large, slightly warped triangles: every
	# fine contour vertex inside one facet lies on the same plane, so the
	# shader's flat normal gives the broad low-poly planes of the reference
	# while the dense grid keeps the silhouette and seams exact.
	var cell := _facet_cell(point)
	var keys: Array = cell["keys"]
	var weights: Vector3 = cell["weights"]
	return _facet_depth(keys[0])*weights.x+_facet_depth(keys[1])*weights.y+_facet_depth(keys[2])*weights.z

func _facet_size() -> float:
	return FACET_SIZE if layer==0 else FAR_FACET_SIZE

func _lattice_point(key: Vector2i) -> Vector2:
	# Jittered triangular lattice. The jitter stays below the inradius of a
	# lattice triangle, so the triangulation never folds: facets are irregular
	# but every fine vertex inside one lies exactly on its plane.
	var size := _facet_size()
	var jitter := Vector2(facet_hash(key.x,key.y,41.0+layer),facet_hash(key.x,key.y,73.0+layer))-Vector2(.5,.5)
	return Vector2(key.x*size+key.y*size*.5,key.y*size*.8660254)+jitter*size*.38

static func _barycentric(p: Vector2, a: Vector2, b: Vector2, c: Vector2) -> Vector3:
	var v0 := b-a
	var v1 := c-a
	var v2 := p-a
	var d := v0.x*v1.y-v1.x*v0.y
	var u := (v2.x*v1.y-v1.x*v2.y)/d
	var v := (v0.x*v2.y-v2.x*v0.y)/d
	return Vector3(1.0-u-v,u,v)

func _facet_keys(i: int, j: int, upper: int) -> Array:
	if upper==0: return [Vector2i(i,j),Vector2i(i+1,j),Vector2i(i,j+1)]
	return [Vector2i(i+1,j+1),Vector2i(i,j+1),Vector2i(i+1,j)]

func _facet_cell(point: Vector2) -> Dictionary:
	if facet_cells.has(point): return facet_cells[point]
	var size := _facet_size()
	var b := point.y/(size*.8660254)
	var a := (point.x-b*size*.5)/size
	var i0 := int(floor(a))
	var j0 := int(floor(b))
	var first := 0 if (a-i0)+(b-j0)<1.0 else 1
	var cell := {}
	var best := -INF
	# The regular cell is the usual answer; jitter can move a point into a
	# neighbouring triangle, so test those next.
	for candidate in [Vector3i(i0,j0,first),Vector3i(i0,j0,1-first),Vector3i(i0-1,j0,1),Vector3i(i0,j0-1,1),Vector3i(i0+1,j0,0),Vector3i(i0,j0+1,0),Vector3i(i0-1,j0+1,1),Vector3i(i0+1,j0-1,0),Vector3i(i0-1,j0,0),Vector3i(i0,j0-1,0),Vector3i(i0+1,j0,1),Vector3i(i0,j0+1,1),Vector3i(i0+1,j0-1,1),Vector3i(i0-1,j0+1,0)]:
		var keys := _facet_keys(candidate.x,candidate.y,candidate.z)
		var weights := _barycentric(point,_lattice_point(keys[0]),_lattice_point(keys[1]),_lattice_point(keys[2]))
		var lowest := minf(weights.x,minf(weights.y,weights.z))
		if lowest>best:
			best = lowest
			cell = {"keys":keys,"weights":weights,"id":candidate}
		if lowest>=-.00001: break
	facet_cells[point] = cell
	return cell

func _facet_depth(key: Vector2i) -> float:
	if facet_depths.has(key): return facet_depths[key]
	var sample := _evaluate(_lattice_point(key))
	# A per-vertex lift breaks each dome into tilted facets of varied light.
	var lift := (facet_hash(key.x,key.y,float(layer)*3.0)-.5)*(.6 if layer>0 else .22)*clampf(sample.x/.8,0,1)
	var depth := clampf(sample.y+lift,WALL_BACK,WALL_FRONT) if layer==0 else sample.y+lift
	facet_depths[key] = depth
	return depth

# --- Boulders -----------------------------------------------------------------

func _route_x(y: float) -> float:
	var key := int(round(y*8.0))
	if not route_cache.has(key): route_cache[key] = massif.route_x(key/8.0)
	return route_cache[key]

func _make_boulder(center: Vector2, radius: float, height: float, random: RandomNumberGenerator, sides_low: int = 6, sides_high: int = 10) -> Dictionary:
	# A convex hull of 6-10 jittered corners: broken, polygonal silhouettes
	# like the boulders of the reference, never a smooth implicit blob.
	var sides := random.randi_range(sides_low,sides_high)
	var turn := random.randf()*TAU
	var stretch := Vector2(random.randf_range(.95,1.12),random.randf_range(.84,1.02))
	var points := PackedVector2Array()
	for i in range(sides):
		var angle := turn+TAU*(i+random.randf_range(-.26,.26))/sides
		points.append(center+Vector2(cos(angle)*stretch.x,sin(angle)*stretch.y)*radius*random.randf_range(.86,1.0))
	return _boulder_from(Geometry2D.convex_hull(points),center,height,random.randf())

func _boulder_from(hull: PackedVector2Array, center: Vector2, height: float, tone: float) -> Dictionary:
	var points := _dedupe(hull)
	var edge_normals := PackedVector2Array()
	var offsets := PackedFloat32Array()
	var reach := 0.0
	var inner := INF
	for i in range(points.size()):
		var a := points[i]
		var b := points[(i+1)%points.size()]
		var n := Vector2(-(b-a).y,(b-a).x).normalized()
		if n.dot(center-a)<0: n = -n
		edge_normals.append(n)
		offsets.append(n.dot(a))
		reach = maxf(reach,center.distance_to(a))
		inner = minf(inner,n.dot(center)-n.dot(a))
	return {"c":center,"points":points,"n":edge_normals,"o":offsets,"reach":reach,"inner":maxf(.5,inner),"h":height,"tone":tone}

func _scaled_boulder(boulder: Dictionary, factor: float) -> Dictionary:
	var center: Vector2 = boulder["c"]
	var points := PackedVector2Array()
	for point in boulder["points"]: points.append(center+(point-center)*factor)
	return _boulder_from(points,center,boulder["h"],boulder["tone"])

static func boulder_inside(boulder: Dictionary, point: Vector2) -> float:
	# Signed distance to a convex polygon: positive inside, straight edges.
	var edge_normals: PackedVector2Array = boulder["n"]
	var offsets: PackedFloat32Array = boulder["o"]
	var result := INF
	for i in range(edge_normals.size()):
		result = minf(result,edge_normals[i].dot(point)-offsets[i])
	return result

func _refresh_boulders() -> void:
	var signature := Vector3i(layout.anchors.size(),layout.finds.size(),layout.obstacles.size())
	if signature==boulder_signature: return
	boulder_signature = signature
	band_boulders.clear()
	band_islands.clear()
	boulder_bins.clear()
	mount_signature = Vector4i(-1,-1,-1,-1)
	eval_cache.clear()
	form_cache.clear()
	facet_depths.clear()

func _covered(list: Array, point: Vector2, radius: float) -> bool:
	for boulder in list:
		if boulder_inside(boulder,point)>=radius: return true
	return false

func _cover_object(list: Array, point: Vector2, radius: float, random: RandomNumberGenerator) -> void:
	# A boulder for a gameplay object: the object sits off-centre on it and its
	# whole protected disc stays on stone.
	if _covered(list,point,radius+.15): return
	var offset := Vector2.from_angle(random.randf()*TAU)*random.randf_range(.15,.45)
	var size := maxf(random.randf_range(1.9,2.4),(radius+offset.length()+.15)/.8)
	var boulder := _make_boulder(point+offset,minf(size,4.5),size*random.randf_range(.68,.8),random)
	for attempt in range(4):
		if boulder_inside(boulder,point)>=radius+.1: break
		boulder = _scaled_boulder(boulder,1.14)
	list.append(boulder)

func front_band(band: int) -> Array:
	# Boulders whose centres lie in one 24 m band. Each band depends only on
	# the seed and the gameplay objects in it, so build order never matters.
	_refresh_boulders()
	var key := Vector2i(0,band)
	if band_boulders.has(key): return band_boulders[key]
	var list: Array = []
	var random := layout.rng(band,947)
	var low := band*BOULDER_BAND
	var high := low+BOULDER_BAND
	var top := massif.summit+1.5 if massif.finite else INF
	# Pairs of mid-sized boulders flank the climbing route, so the corridor
	# is covered by several separate masses rather than one wide block.
	var y := low+random.randf_range(0,1.2)
	while y<high:
		if y>-3.0 and y<top:
			var route := _route_x(y)
			var shift := random.randf_range(-.5,.5)
			for side in [-1.0,1.0]:
				var center := Vector2(route+shift+side*random.randf_range(1.0,1.6),y+random.randf_range(-.6,.6))
				var radius := random.randf_range(2.0,2.6)
				list.append(_make_boulder(center,radius,radius*random.randf_range(.68,.8),random))
		y += random.randf_range(2.3,2.9)
	for anchor in layout.anchors:
		var p: Vector2 = anchor["pos"]
		if p.y>=low and p.y<high: _cover_object(list,p,grip_clearance(anchor),random)
	for find in layout.finds:
		var p: Vector2 = find["pos"]
		if p.y>=low and p.y<high: _cover_object(list,p,FIND_CLEARANCE,random)
	for obstacle in layout.obstacles:
		var p: Vector2 = obstacle["pos"]
		if p.y>=low and p.y<high: _cover_object(list,p,minf(maxf(obstacle["dimensions"].x,obstacle["dimensions"].y)*.6+1.0,3.9),random)
	# A few smaller boulders lean against the masses and break up the outline.
	var anchors_count := list.size()
	for extra in range(3 if anchors_count>0 else 0):
		var parent: Dictionary = list[random.randi_range(0,anchors_count-1)]
		var direction := Vector2.from_angle(random.randf()*TAU)
		var center: Vector2 = parent["c"]+direction*float(parent["reach"])*random.randf_range(.75,1.0)
		if center.y<-2.0 or center.y>top: continue
		var radius := random.randf_range(1.3,1.9)
		list.append(_make_boulder(center,radius,radius*random.randf_range(.7,.85),random,6,8))
	# Side islands: separate clusters of boulders well off the route give the
	# mountain its broken macro silhouette, with open sky between them and
	# the climbing trunk. Ridges and ravines keep one, other landforms two.
	var form: Dictionary = massif.landform(int(floor((low+12.0)/MassifLayout.REGION_HEIGHT)))
	var islands: Array = []
	for cluster in range(1 if int(form["kind"]) in [2,3] else 2):
		var cy := low+random.randf_range(3.0,21.0)
		var side := -1.0 if (cluster==0)==(random.randf()<.5) else 1.0
		if cy<3.0 or cy>top-3.0: continue
		var cx := _route_x(cy)+side*random.randf_range(7.5,11.5)
		var members: Array = []
		for member in range(random.randi_range(3,5)):
			var center := Vector2(cx,cy)+Vector2(random.randf_range(-2.6,2.6),random.randf_range(-2.0,2.0))
			var radius := random.randf_range(1.5,2.6)
			var boulder := _make_boulder(center,radius,radius*random.randf_range(.68,.8),random)
			members.append(boulder)
			list.append(boulder)
		islands.append(members)
	band_islands[band] = islands
	band_boulders[key] = list
	_register(list,0)
	return list

func far_band(far: int, band: int) -> Array:
	var key := Vector2i(far,band)
	if band_boulders.has(key): return band_boulders[key]
	var list: Array = []
	var random := layout.rng(band*7+far,951)
	var count := random.randi_range(4,6)
	for index in range(count):
		var x := lerpf(-44.0,44.0,(index+random.randf_range(.1,.9))/count)
		var y := band*BOULDER_BAND+random.randf_range(0,BOULDER_BAND)
		var radius := random.randf_range(4.0,7.5)*(1.0+.25*(far-1))
		list.append(_make_boulder(Vector2(x,y),radius,radius*random.randf_range(.35,.5),random,7,10))
	band_boulders[key] = list
	_register(list,far)
	return list

func _register(list: Array, owner_layer: int) -> void:
	for boulder in list:
		var center: Vector2 = boulder["c"]
		var reach: float = boulder["reach"]
		for bin in range(int(floor((center.y-reach)/BOULDER_BIN)),int(floor((center.y+reach)/BOULDER_BIN))+1):
			var bin_key := Vector2i(owner_layer,bin)
			if not boulder_bins.has(bin_key): boulder_bins[bin_key] = []
			boulder_bins[bin_key].append(boulder)

func _boulders_near(point: Vector2) -> Array:
	var band := int(floor(point.y/BOULDER_BAND))
	for neighbour in [band-1,band,band+1]:
		if layer==0: front_band(neighbour)
		else: far_band(layer,neighbour)
	return boulder_bins.get(Vector2i(layer,int(floor(point.y/BOULDER_BIN))),[])

func _evaluate(point: Vector2) -> Vector4:
	# x: stone field (>=0 is stone), y: surface depth, z: crease shade, w: tone.
	if eval_cache.has(point): return eval_cache[point]
	var field := -INF
	var total := 0.0
	var best := -INF
	var tone := .5
	var form := 0.0
	var rims: Array[Vector2] = []
	for boulder in _boulders_near(point):
		var center: Vector2 = boulder["c"]
		var reach: float = boulder["reach"]
		var distance_squared := point.distance_squared_to(center)
		if distance_squared>(reach+1.0)*(reach+1.0):
			field = maxf(field,reach-sqrt(distance_squared))
			continue
		var inside := boulder_inside(boulder,point)
		field = maxf(field,inside)
		if inside<=-RIM_FALL: continue
		var height: float = boulder["h"]
		if inside<=0:
			# Just outside, the rim lip fades out, so silhouette facets slope
			# back gently instead of dropping straight to the back plane.
			total += height*RIM_LIP*(1.0+inside/RIM_FALL)
			continue
		# Boulders stack: each one is a convex dome with a low lip, laid over
		# whatever is behind it, so overlapping masses keep their own outline.
		# The crown leans to the lower right, so the upper-left slopes face
		# the sun and the underside drops into shade.
		var t := clampf(inside/float(boulder["inner"]),0,1)
		var lean := (point-center).dot(Vector2(.5,-.6))/reach
		var dome := height*(RIM_LIP+(1.0-RIM_LIP)*(1.0-pow(1.0-t,2.2)))*(1.0+.14*lean)
		total += dome
		if dome>best:
			best = dome
			tone = boulder["tone"]
			# Painterly form: the lower-right rim of the boulder that owns this
			# point falls into its underbelly shade, the upper-left rim catches
			# the light. Encoded in the tone so facets stay clean planes.
			var away := (point-center)/reach
			form = (1.0-t)*(clampf(away.dot(Vector2(-.6,.8)),0,1)*.5-clampf(away.dot(Vector2(.55,-.83)),0,1))
		if t<.4: rims.append(Vector2(t,dome))
	# The tallest dome shapes the surface and the others only lift it a
	# little, so neighbouring boulders meet in a crease: the upper one's
	# lower rim turns away from the sun, the lower one's crown faces it.
	var stacked := 4.0*tanh((maxf(best,0.0)+STACK_SHARE*(total-maxf(best,0.0)))/4.0)
	if layer==0:
		# Gameplay guarantees: the route corridor and every protected disc keep
		# stone behind them even where no boulder would reach.
		var limit := massif.summit+.4 if massif.finite else INF
		if point.y>-2.0 and point.y<limit:
			var corridor := ROUTE_CLEAR-absf(point.x-_route_x(point.y))
			if corridor>field:
				field = corridor
				stacked = maxf(stacked,2.0*sqrt(clampf(corridor/ROUTE_CLEAR,0,1)))
		if field<.4:
			var protect := -_protected_clearance(point)
			if protect>field:
				field = protect
				stacked = maxf(stacked,1.6*sqrt(clampf(protect/1.2,0,1)))
	# Soft shade where a rim lies on the boulder behind it.
	var joint := 0.0
	for rim in rims:
		joint = maxf(joint,(1.0-rim.x/.4)*smoothstep(.2,1.0,total-rim.y))
	var result := Vector4(field,(WALL_BACK if layer==0 else 0.0)+stacked,joint,tone)
	eval_cache[point] = result
	form_cache[point] = form
	return result

func stone_field(point: Vector2) -> float:
	_use_layer(0)
	return _evaluate(point).x

func _field(point: Vector2) -> float:
	return _evaluate(point).x

var protect_bins: Dictionary = {}
var protect_signature := Vector3i(-1,-1,-1)
var mount_bins: Dictionary = {}
var occlusion_cache: Dictionary = {}
var mount_signature := Vector4i(-1,-1,-1,-1)

func _refresh_mounts() -> void:
	# Footprints of gameplay objects for the baked contact shade: [centre, half size, strength].
	var signature := Vector4i(layout.anchors.size(),layout.finds.size(),layout.obstacles.size(),layout.ledges.size())
	if signature!=mount_signature:
		mount_signature = signature
		mount_bins.clear()
		occlusion_cache.clear()
		for anchor in layout.anchors:
			var d: Vector2 = anchor["dimensions"]
			_add_mount(anchor["pos"]+Vector2(0,-.2),Vector2(d.x*.5+.85,d.y*.5+.95),.95)
		for find in layout.finds: _add_mount(find["pos"]+Vector2(0,-.45),Vector2(1.25,1.05),.8)
		for obstacle in layout.obstacles:
			var d: Vector2 = obstacle["dimensions"]
			_add_mount(obstacle["pos"]+Vector2(0,-.2),d*.5+Vector2(.95,.95),1.1)
		for ledge in layout.ledges:
			var left: float = ledge["left"]
			var right: float = ledge["right"]
			_add_mount(Vector2((left+right)*.5,float(ledge["top"])-.45),Vector2((right-left)*.5+.85,1.2),1.0)

func _add_mount(center: Vector2, size: Vector2, height: float) -> void:
	var key := int(floor(center.y/4.0))
	if not mount_bins.has(key): mount_bins[key] = []
	mount_bins[key].append([center,Vector2(minf(size.x,3.6),minf(size.y,3.6)),height])

func _occlusion(point: Vector2) -> float:
	# Baked contact shade on the stone itself, offset down-right with the sun,
	# so objects sit in the rock without separate shadow decals.
	if occlusion_cache.has(point): return occlusion_cache[point]
	_refresh_mounts()
	var shade := 0.0
	var key := int(floor(point.y/4.0))
	for bin in range(key-1,key+2):
		for mount in mount_bins.get(bin,[]):
			var size: Vector2 = mount[1]
			var t: float = ((point-mount[0]-Vector2(.3,-.35))/(size*1.15)).length()
			if t<1.0: shade = maxf(shade,(1.0-smoothstep(.2,1.0,t))*.09*float(mount[2]))
	occlusion_cache[point] = shade
	return shade
func _protected_clearance(point: Vector2) -> float:
	# Distance from the nearest gameplay object's protected disc, using 4 m
	# height bins rebuilt only when the generator adds objects.
	var signature := Vector3i(layout.anchors.size(),layout.finds.size(),layout.obstacles.size())
	if signature!=protect_signature:
		protect_signature = signature
		protect_bins.clear()
		for anchor in layout.anchors: _add_protected(anchor["pos"],grip_clearance(anchor))
		for find in layout.finds: _add_protected(find["pos"],FIND_CLEARANCE)
		for obstacle in layout.obstacles: _add_protected(obstacle["pos"],maxf(obstacle["dimensions"].x,obstacle["dimensions"].y)*.6+1.0)
	var result := INF
	var key := int(floor(point.y/4.0))
	for bin in [key-1,key,key+1]:
		for entry in protect_bins.get(bin,[]):
			result = minf(result,point.distance_to(entry[0])-float(entry[1]))
	return result

const FIND_CLEARANCE := 1.05

static func grip_clearance(anchor: Dictionary) -> float:
	# Stone reaches past the grip's own polygon on every side, while sky can
	# still open between neighbouring grips.
	return maxf(1.0,float(anchor["dimensions"].x)*.5+.32)

func _add_protected(center: Vector2, radius: float) -> void:
	# Radii never exceed 4 m, so neighbouring bins cover every overlap.
	var key := int(floor(center.y/4.0))
	if not protect_bins.has(key): protect_bins[key] = []
	protect_bins[key].append([center,minf(radius,3.9)])

func surface_normal(point: Vector2) -> Vector3:
	if not normals.has(point):
		var dx := (_depth(point+Vector2(.08,0))-_depth(point-Vector2(.08,0)))/.16
		var dy := (_depth(point+Vector2(0,.08))-_depth(point-Vector2(0,.08)))/.16
		normals[point] = Vector3(-dx,-dy,1).normalized()
	return normals[point]

func _facet_tone(facet: Vector3i) -> Color:
	# One colour per large facet, sampled at its centre: boulder tone, a soft
	# crease shade and a random facet offset. Fine contour triangles inside a
	# facet share it, so the planes read as single low-poly faces.
	if facet_tones.has(facet): return facet_tones[facet]
	var keys := _facet_keys(facet.x,facet.y,facet.z)
	var center := (_lattice_point(keys[0])+_lattice_point(keys[1])+_lattice_point(keys[2]))/3.0
	var sample := _evaluate(center)
	var color := zone_color(center.y if layer==0 else 40.0)
	var shade: float = form_cache.get(center,0.0)
	var offset := (facet_hash(facet.x*2+facet.z,facet.y,11.0)-.5)*(.06 if layer==0 else .06)+(sample.w-.5)*.10+shade*(.05 if shade<0 else .10)
	color = color.lightened(offset) if offset>=0 else color.darkened(-offset)
	# Soft shade in the creases between boulders, never black.
	if layer==0: color = color.darkened(sample.z*.05)
	facet_tones[facet] = color
	return color

func _emit(surface: SurfaceTool, point: Vector3, color: Color) -> void:
	emitted_vertices += 1
	# SurfaceTool colors are already converted by the renderer. Converting them
	# to linear here a second time makes the whole massif look charcoal green.
	surface.set_color(color)
	surface.set_normal(Vector3.BACK)
	surface.add_vertex(point)

func _edge_cut(a: Vector2, b: Vector2, fa: float, steps: int) -> Vector2:
	# The boulder field is linear along each straight boulder edge, so a short
	# bisection lands on the polygonal outline. Endpoints are ordered so both
	# neighbouring triangles find the identical point.
	if a.x>b.x or (a.x==b.x and a.y>b.y):
		var swap := a
		a = b
		b = swap
		fa = _field(a)
	for step in range(steps):
		var middle := (a+b)*.5
		var fm := _field(middle)
		if (fm>=0)==(fa>=0):
			a = middle
			fa = fm
		else: b = middle
	return (a+b)*.5

static func _clip_y(polygon: PackedVector2Array, limit: float, keep_above: bool) -> PackedVector2Array:
	var result := PackedVector2Array()
	for i in range(polygon.size()):
		var a := polygon[i]
		var b := polygon[(i+1)%polygon.size()]
		var a_in := a.y>=limit if keep_above else a.y<=limit
		var b_in := b.y>=limit if keep_above else b.y<=limit
		if a_in: result.append(a)
		if a_in!=b_in:
			var low := a if a.x<b.x or (a.x==b.x and a.y<b.y) else b
			var high := b if low==a else a
			result.append(Vector2(lerpf(low.x,high.x,(limit-low.y)/(high.y-low.y)),limit))
	return result

func _lattice_face(surface: SurfaceTool, facet: Vector3i, low_y: float, high_y: float) -> void:
	# One planar facet of the jittered lattice, clipped to the stone outline
	# and to the band. Every emitted vertex lies on the facet plane, so the
	# flat normal gives one clean value per facet.
	var keys := _facet_keys(facet.x,facet.y,facet.z)
	var a := _lattice_point(keys[0])
	var b := _lattice_point(keys[1])
	var c := _lattice_point(keys[2])
	if maxf(a.y,maxf(b.y,c.y))<=low_y or minf(a.y,minf(b.y,c.y))>=high_y: return
	var fa := _field(a)
	var fb := _field(b)
	var fc := _field(c)
	# The field is 1-Lipschitz, so corners this far out or in decide the
	# whole facet without sampling its interior.
	var margin := _facet_size()*1.3
	if maxf(fa,maxf(fb,fc))<-margin: return
	var depth := Vector3(_facet_depth(keys[0]),_facet_depth(keys[1]),_facet_depth(keys[2]))
	var color := _facet_tone(facet)
	var inside := minf(fa,minf(fb,fc))>margin
	var divisions := 1 if inside else (4 if layer==0 else 2)
	var steps := 3 if layer==0 else 2
	var points: Array[Vector2] = []
	var fields := PackedFloat32Array()
	for u in range(divisions+1):
		for v in range(divisions+1-u):
			var point := a+(b-a)*(float(u)/divisions)+(c-a)*(float(v)/divisions)
			points.append(point)
			fields.append(1.0 if inside else _field(point))
	# Row u of the barycentric grid starts after u rows of shrinking length.
	for u in range(divisions):
		for v in range(divisions-u):
			var i0 := u*(divisions+1)-u*(u-1)/2+v
			var i1 := (u+1)*(divisions+1)-(u+1)*u/2+v
			var i2: int = i0+1
			_clip_emit(surface,[i0,i1,i2],points,fields,steps,a,b,c,depth,color,low_y,high_y)
			if v<divisions-u-1:
				_clip_emit(surface,[i1,i1+1,i2],points,fields,steps,a,b,c,depth,color,low_y,high_y)

func _clip_emit(surface: SurfaceTool, ids: Array, points: Array[Vector2], fields: PackedFloat32Array, steps: int, a: Vector2, b: Vector2, c: Vector2, depth: Vector3, color: Color, low_y: float, high_y: float) -> void:
	var f0 := fields[ids[0]]
	var f1 := fields[ids[1]]
	var f2 := fields[ids[2]]
	if maxf(f0,maxf(f1,f2))<0: return
	var polygon := PackedVector2Array()
	for k in range(3):
		var i: int = ids[k]
		var j: int = ids[(k+1)%3]
		if fields[i]>=0: polygon.append(points[i])
		if (fields[i]>=0)!=(fields[j]>=0): polygon.append(_edge_cut(points[i],points[j],fields[i],steps))
	polygon = _clip_y(polygon,low_y,true)
	if polygon.size()<3: return
	polygon = _clip_y(polygon,high_y,false)
	if polygon.size()<3: return
	var corners: Array[Vector3] = []
	var tints: Array[Color] = []
	for point in polygon:
		var weights := _barycentric(point,a,b,c)
		corners.append(Vector3(point.x,point.y,weights.dot(depth)))
		tints.append(color.darkened(_occlusion(point)) if layer==0 else color)
	for i in range(1,corners.size()-1):
		_emit(surface,corners[0],tints[0])
		_emit(surface,corners[i+1],tints[i+1])
		_emit(surface,corners[i],tints[i])

func _emit_band(surface: SurfaceTool, low_y: float, high_y: float, low_x: float, high_x: float) -> void:
	emitted_vertices = 0
	var size := _facet_size()
	var row := size*.8660254
	for j in range(int(floor(low_y/row))-1,int(ceil(high_y/row))+1):
		for i in range(int(floor((low_x-j*size*.5)/size))-1,int(ceil((high_x-j*size*.5)/size))+1):
			_lattice_face(surface,Vector3i(i,j,0),low_y,high_y)
			_lattice_face(surface,Vector3i(i,j,1),low_y,high_y)

func build_chunk(index: int, parent: Node3D) -> void:
	_build_skin(index,parent)
	_build_flanks(index,parent)
	_build_decor(index,parent)
	_build_landmarks(index,parent)

func _landmark_clear(point: Vector2, height: float) -> bool:
	# The whole set piece, not only its foot, keeps clear of the route and of
	# every grip, find, obstacle and ledge.
	if not _decor_route_clear(point,3.2): return false
	for step in range(4):
		var probe := point+Vector2(0,height*step/3.0)
		if _decor_blocked(probe,1.0) or not _decor_route_clear(probe,3.0): return false
	return true

func _build_landmarks(index: int, parent: Node3D) -> void:
	# One large themed piece on top of a side island, by zone.
	_use_layer(0)
	front_band(index)
	var budget := 1 if quality=="battery" else 2
	var random := layout.rng(index,977)
	var placed := 0
	for members in band_islands.get(index,[]):
		if placed>=budget: break
		var crown := Vector2(0,-INF)
		for boulder in members:
			for corner in boulder["points"]:
				if corner.y>crown.y: crown = corner
		var point := crown-Vector2(0,.45)
		if _field(point)<.1 or _field(point+Vector2(0,.9))>=0: continue
		var zone := clampi(int(point.y/20.0),0,5)
		if not _landmark_clear(point,LandmarkVisuals.height_for(zone)): continue
		var holder := Node3D.new()
		holder.name = "Крупный элемент_%d" % placed
		parent.add_child(holder)
		holder.position = Vector3(point.x,point.y,wall_depth(point)+.05)
		LandmarkVisuals.build(self,zone,holder,random,quality=="high")
		placed += 1

func build_far_band(far: int, band: int, parent: Node3D) -> void:
	# A distant layer band in its own parallax space (see MountainWorld).
	_use_layer(far)
	facet_cells.clear()
	facet_tones.clear()
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	_emit_band(surface,band*BOULDER_BAND,(band+1)*BOULDER_BAND,-48.0,48.0)
	if emitted_vertices==0: return
	surface.index()
	var instance := MeshInstance3D.new()
	instance.name = "Дальние скалы_%d_%d" % [far,band]
	instance.mesh = surface.commit()
	instance.material_override = far_materials[far-1]
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(instance)

func _build_skin(index: int, parent: Node3D) -> void:
	_use_layer(0)
	positions.clear()
	normals.clear()
	eval_cache.clear()
	form_cache.clear()
	facet_cells.clear()
	facet_tones.clear()
	facet_depths.clear()
	occlusion_cache.clear()
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	surface.set_smooth_group(0)
	# The first band also closes the rounded feet of the lowest boulders.
	var low := index*BOULDER_BAND-(8.0 if index==0 else 0.0)
	_emit_band(surface,low,(index+1)*BOULDER_BAND,-36.0,36.0)
	if emitted_vertices==0:
		positions.clear()
		normals.clear()
		return
	var instance := MeshInstance3D.new()
	instance.name = "Скальный массив_%d" % index
	surface.index()
	surface.generate_normals()
	var rock_mesh := surface.commit()
	var arrays := rock_mesh.surface_get_arrays(0)
	var points: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var smooth_normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
	# Interior normals are generated in native code. At chunk seams both sides
	# use the same analytic gradient, including the neighbour not loaded yet.
	for i in range(points.size()):
		if absf(points[i].y-index*24)<.14 or absf(points[i].y-(index+1)*24)<.14:
			smooth_normals[i] = surface_normal(Vector2(points[i].x,points[i].y))
	arrays[Mesh.ARRAY_NORMAL] = smooth_normals
	rock_mesh.clear_surfaces()
	rock_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays)
	instance.mesh = rock_mesh
	instance.material_override = rock_material
	# Keep the surface clean and let anchors, obstacles and loot cast the
	# readable contact shadows instead of self-shadowing every low-poly face.
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(instance)
	positions.clear()

func _decor_blocked(point: Vector2, reach: float = 0.0) -> bool:
	for anchor in layout.nearby_ids(point.y-2.0,point.y+2.0):
		if layout.anchors[anchor]["pos"].distance_to(point)<.95+reach: return true
	for obstacle in layout.obstacles:
		if obstacle["pos"].distance_to(point)<1.15+maxf(obstacle["dimensions"].x,obstacle["dimensions"].y)*.5+reach: return true
	for find in layout.finds:
		if find["pos"].distance_to(point)<.8+reach: return true
	for ledge in layout.ledges:
		if point.x>float(ledge["left"])-.5 and point.x<float(ledge["right"])+.5 and absf(point.y-float(ledge["top"]))<.9+reach: return true
	return false

func _decor_route_clear(point: Vector2, radius: float) -> bool:
	# Keep the line of throws and swings readable: no tall decor on the spine.
	return absf(point.x-_route_x(point.y))>radius

func _build_decor(index: int, parent: Node3D) -> void:
	# Decor follows the boulders: grass on their upper rims and in the creases,
	# crystal clusters on side rims open to the sky, scree at their feet. Each
	# piece takes depth and lean from its SurfaceMount and its look from the
	# place's profile; a cluster grows with the length of open rim it sits on.
	_use_layer(0)
	var budget := 36 if quality=="high" else 22 if quality=="balanced" else 8
	var crystal_budget := 5 if quality=="high" else 3 if quality=="balanced" else 1
	var detail := quality!="battery"
	var random := layout.rng(index,902)
	var candidates: Array = []
	for boulder in front_band(index):
		var points: PackedVector2Array = boulder["points"]
		var edge_normals: PackedVector2Array = boulder["n"]
		for i in range(points.size()):
			var outward := -edge_normals[i]
			var b: Vector2 = points[(i+1)%points.size()]
			var at: Vector2 = points[i].lerp(b,random.randf_range(.2,.8))
			var span: float = points[i].distance_to(b)
			if outward.y>.45: candidates.append([at,"grass",outward,span])
			elif outward.y<-.55: candidates.append([at,"pebbles",outward,span])
			elif outward.y>-.25: candidates.append([at,"crystal",outward,span])
	# Deterministic shuffle so every kind gets its share of the budget.
	for i in range(candidates.size()-1,0,-1):
		var j := random.randi_range(0,i)
		var swap = candidates[i]
		candidates[i] = candidates[j]
		candidates[j] = swap
	var placed := 0
	var crystals := 0
	for candidate in candidates:
		if placed>=budget: break
		var outward: Vector2 = candidate[2]
		var kind: String = candidate[1]
		var point: Vector2 = candidate[0]-outward*(.22 if kind!="crystal" else .32)
		var sample := _evaluate(point)
		if sample.x<.08: continue
		var open := _field(point+outward*.75)<0
		var profile := profile_at(point.y)
		match kind:
			"grass":
				if not open and sample.z<.35: continue
				if not _decor_route_clear(point,.9) or _decor_blocked(point): continue
			"crystal":
				if not open or crystals>=crystal_budget: continue
				if not _decor_route_clear(point,2.4) or _decor_blocked(point,.7): continue
				crystals += 1
			_:
				if _decor_blocked(point): continue
		var mount := mount_at(point,Vector2(.6,.3))
		var holder := Node3D.new()
		holder.name = "Процедурный декор_%d" % placed
		parent.add_child(holder)
		# Sit exactly on the facet plane and lean with the rim.
		holder.position = Vector3(point.x,point.y,mount.wall_z()+.02)
		holder.rotation.x = -clampf(mount.normal.y,-.4,.4)*.6
		var rim := clampf(float(candidate[3])/2.2,.8,1.4)
		match kind:
			"crystal":
				holder.rotation.z = clampf(-outward.x*.3,-.3,.3)
				_build_crystal(holder,random,detail,random.randi_range(3,6) if quality=="high" else random.randi_range(3,4),profile)
			"grass":
				holder.rotation.z = clampf(-outward.x*.5,-.5,.5)
				var plants: Dictionary = profile.vegetation_set
				holder.scale = Vector3.ONE*random.randf_range(1.2,1.5)*rim*(1.0 if plants["grass"] else .7)
				_build_grass(holder,random,quality=="high",rim,profile,detail)
			_:
				# Scree: larger stones at the foot, smaller ones down the slope.
				_build_pebbles(holder,random,zone_color(point.y),quality=="high")
				var below := point+mount.downhill()*.55
				if detail and _field(below)>.08 and not _decor_blocked(below):
					var tail := Node3D.new()
					tail.name = "Осыпь"
					tail.position = Vector3(below.x-point.x,below.y-point.y,wall_depth(below)-holder.position.z)
					tail.scale = Vector3.ONE*.6
					holder.add_child(tail)
					_build_pebbles(tail,random,zone_color(below.y),false)
		placed += 1

func _build_flanks(index: int, parent: Node3D) -> void:
	# Side faces of the macro forms: where a boulder's edge is the outline of
	# the massif against open sky, a wall of the same stone runs from the
	# skin's rim back into the mountain, so a mass reads by its thickness and
	# not only by facet tone. Upper flanks are warmer, lower ones cool and dark.
	# Every preset builds the same silhouette; only high casts its shadows.
	_use_layer(0)
	var low := index*BOULDER_BAND
	var high := low+BOULDER_BAND
	var points := PackedVector3Array()
	var colors := PackedColorArray()
	var cool: Color = profile_at(low+12.0).rock_palette["cool"]
	for boulder in front_band(index):
		var hull: PackedVector2Array = boulder["points"]
		var edge_normals: PackedVector2Array = boulder["n"]
		for i in range(hull.size()):
			var a := hull[i]
			var b := hull[(i+1)%hull.size()]
			var outward := -edge_normals[i]
			var steps := maxi(1,int(ceil(a.distance_to(b)/.6)))
			for step in range(steps):
				var p0 := a.lerp(b,float(step)/steps)
				var p1 := a.lerp(b,float(step+1)/steps)
				var middle := (p0+p1)*.5
				if middle.y<low or middle.y>=high: continue
				if _field(middle+outward*.3)>=0 or _field(middle-outward*.25)<0: continue
				var in0 := p0-outward*.04
				var in1 := p1-outward*.04
				var z0 := _depth(in0)
				var z1 := _depth(in1)
				var flare := outward*.22
				var back := WALL_BACK-1.2
				var tone := zone_color(middle.y)
				if outward.y>.4: tone = tone.lightened(.05)
				elif outward.y<-.3: tone = tone.lerp(cool,.3).darkened(.22)
				else: tone = tone.lerp(cool,.2).darkened(.12)
				var c0 := Vector3(in0.x,in0.y,z0)
				var c1 := Vector3(in1.x,in1.y,z1)
				var d0 := Vector3(in0.x+flare.x,in0.y+flare.y,back)
				var d1 := Vector3(in1.x+flare.x,in1.y+flare.y,back)
				points.append_array(PackedVector3Array([c0,c1,d1]))
				colors.append(tone)
				points.append_array(PackedVector3Array([c0,d1,d0]))
				colors.append(tone.darkened(.05))
	if points.is_empty(): return
	_flat_surface(parent,"Боковые грани_%d" % index,points,colors,flank_material,quality=="high")

func open_at(point: Vector2) -> bool:
	_use_layer(0)
	return _field(point)<0

func support_root_of(object: Dictionary) -> Vector2:
	return massif.support_root(object) if object.has("id") and object.has("pos") else Vector2.INF

func baked_contact() -> bool:
	# The skin already carries the contact shade of every object (_occlusion).
	return true

# --- Gameplay objects ---------------------------------------------------------


func wall_depth(point: Vector2) -> float:
	# Front skin depth at a point, from the same facet planes as the mesh.
	_use_layer(0)
	return _depth(point)
