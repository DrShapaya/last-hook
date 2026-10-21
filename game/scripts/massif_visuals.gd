class_name MassifVisuals
extends MountainVisuals

# Visual planes in front of the wall (gameplay is purely XY).
const GRIP_Z := 2.35
const OBSTACLE_Z := 2.3
const LEDGE_Z := 2.15
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
var obstacle_material := ShaderMaterial.new()
var stone_material := ShaderMaterial.new()
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
var quality := "balanced"
# Soft, cool contact shade: darkens the stone without going black and never
# writes depth, so it cannot flicker against the wall.
const CONTACT_SHADER := "shader_type spatial; render_mode unshaded, cull_disabled, blend_mix, depth_draw_never, shadows_disabled; uniform float opacity = .22; void fragment(){ vec2 p=UV*2.0-1.0; float d=length(p); ALBEDO=vec3(.07,.09,.12); ALPHA=smoothstep(1.0,.15,d)*opacity; }"
var far_shader: Shader

func _init(owner_world: Node3D, source: MountainLayout) -> void:
	super._init(owner_world,source)
	massif = source as MassifLayout
	rock_material.shader = preload("res://shaders/massif_rock.gdshader")
	rock_material.set_shader_parameter("facet_strength",1.0)
	obstacle_material.shader = rock_material.shader
	obstacle_material.set_shader_parameter("snow_override",0.0)
	obstacle_material.set_shader_parameter("material_tint",1.0)
	obstacle_material.set_shader_parameter("detail_strength",.6)
	stone_material.shader = rock_material.shader
	stone_material.set_shader_parameter("snow_override",0.0)
	stone_material.set_shader_parameter("facet_strength",1.0)
	stone_material.set_shader_parameter("detail_strength",.45)
	stone_material.set_shader_parameter("material_tint",1.0)
	# Distant cliffs: one flat facet light, no shadow lookups, mixed into
	# the sky colour. Cheap enough for every preset, including phones.
	far_shader = Shader.new()
	far_shader.code = "shader_type spatial; render_mode unshaded, cull_disabled, shadows_disabled; uniform vec3 haze : source_color = vec3(.42,.68,.92); uniform float haze_amount = .7; varying vec3 world_pos; void vertex(){ world_pos=(MODEL_MATRIX*vec4(VERTEX,1.0)).xyz; } void fragment(){ vec3 n=normalize(cross(dFdx(world_pos),dFdy(world_pos))); if(n.z<0.0){ n=-n; } float l=dot(n,normalize(vec3(-.55,.62,.56))); vec3 c=COLOR.rgb*mix(.80,1.10,smoothstep(-.2,.9,l)); ALBEDO=mix(c,haze,haze_amount); }"
	for settings in FAR_LAYERS:
		var material := ShaderMaterial.new()
		material.shader = far_shader
		material.set_shader_parameter("haze_amount",settings["haze"])
		far_materials.append(material)

func set_quality(value: String) -> void:
	quality = value if value in ["high","balanced","battery"] else "balanced"

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

static func facet_hash(i: int, j: int, salt: float) -> float:
	return fposmod(sin(i*127.1+j*311.7+salt)*43758.5453,1.0)

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

func _flat_surface(parent: Node3D, name: String, points: PackedVector3Array, colors: PackedColorArray, material: Material, shadows: bool) -> MeshInstance3D:
	# Faceted mesh with one normal per triangle and per-triangle colours.
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in range(0,points.size(),3):
		var normal := (points[i+2]-points[i]).cross(points[i+1]-points[i]).normalized()
		if normal.z<0: normal = -normal
		for k in range(3):
			surface.set_color(colors[i/3])
			surface.set_normal(normal)
			surface.add_vertex(points[i+k])
	var mesh := MeshInstance3D.new()
	mesh.name = name
	mesh.mesh = surface.commit()
	mesh.material_override = material
	mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if shadows else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mesh)
	return mesh

func _vertex_material(key: String, emission: float = 0.0) -> StandardMaterial3D:
	var material: StandardMaterial3D = world.mat(key,Color.WHITE,false)
	material.vertex_color_use_as_albedo = true
	material.vertex_color_is_srgb = true
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	if emission>0:
		material.emission_enabled = true
		material.emission = Color("2f7fd0")
		material.emission_energy_multiplier = emission
	return material

func _build_grass(holder: Node3D, random: RandomNumberGenerator, shadows: bool, spread: float = 1.0) -> void:
	# A lush tuft: many tapered blades and a few broad leaves fanned from one
	# root, dark green at the base and bright yellow-green at the tips.
	var dark := Color("5a9134")
	var mid := Color("6fae3a")
	var light := Color("9ccc55")
	var points := PackedVector3Array()
	var colors := PackedColorArray()
	var blades := random.randi_range(14,20)
	for blade in range(blades):
		var u := (float(blade)/maxf(1,blades-1)-.5)+random.randf_range(-.06,.06)
		var angle := u*2.4+random.randf_range(-.18,.18)
		var broad := blade%4==0
		var length := random.randf_range(.30,.56)*(1.0-absf(u)*.45)*(.8 if broad else 1.0)
		var w := random.randf_range(.07,.11) if broad else random.randf_range(.03,.05)
		var z := .02+float(blade%3)*.025
		var root := Vector3(u*.40*spread,random.randf_range(-.03,.03),z)
		var direction := Vector3(sin(angle),cos(angle),0)
		var across := Vector3(direction.y,-direction.x,0)*w
		# Blades curl outwards a little towards the tip.
		var bend := Vector3(direction.x*.15,-absf(direction.x)*.12,0)*length
		var middle := root+direction*length*.5
		var tip := root+direction*length+bend+Vector3(0,0,.03)
		var tip_tone := light if blade%3!=1 else mid
		points.append_array(PackedVector3Array([root-across,root+across,middle+across*.8]))
		colors.append(dark)
		points.append_array(PackedVector3Array([root-across,middle+across*.8,middle-across*.8]))
		colors.append(dark.lerp(mid,.35))
		points.append_array(PackedVector3Array([middle-across*.8,middle+across*.8,tip]))
		colors.append(mid.lerp(tip_tone,.6))
	_flat_surface(holder,"Трава",points,colors,_vertex_material("decor_grass_v4"),shadows)

func _build_crystal(holder: Node3D, random: RandomNumberGenerator, shadows: bool, count: int = 4) -> void:
	# A cluster of faceted hexagonal crystals, 1-1.6 m tall in the centre,
	# with pale lit faces on the sun side.
	var points := PackedVector3Array()
	var colors := PackedColorArray()
	var body := Color("2f6fd8")
	var lit := Color("78b6f4")
	var pale := Color("c4e3ff")
	for index in range(count):
		var t := (float(index)/maxf(1,count-1)-.5) if count>1 else 0.0
		var height := random.randf_range(1.0,1.6)*(1.0-absf(t)*.75)
		var radius := random.randf_range(.14,.20)*(1.0-absf(t)*.3)
		var base := Vector3(t*.62,-.05,.06+index*.015)
		var axis := Vector3(sin(t*1.1+random.randf_range(-.12,.12)),cos(t*1.1),0).normalized()
		var side := Vector3(axis.y,-axis.x,0)
		var shaft := base+axis*height*.72
		var tip := base+axis*height
		for corner in range(6):
			var a0 := TAU*corner/6.0
			var a1 := TAU*(corner+1)/6.0
			var o0 := side*cos(a0)*radius+Vector3(0,0,sin(a0)*radius)
			var o1 := side*cos(a1)*radius+Vector3(0,0,sin(a1)*radius)
			var facing := (cos(a0)+cos(a1))*.5
			var face := body.lerp(lit,clampf(-facing*.8+.25,0,1))
			points.append_array(PackedVector3Array([base+o0,shaft+o0,shaft+o1]))
			colors.append(face)
			points.append_array(PackedVector3Array([base+o0,shaft+o1,base+o1]))
			colors.append(face.darkened(.05))
			points.append_array(PackedVector3Array([shaft+o0,tip,shaft+o1]))
			colors.append(face.lerp(pale,.45))
	_flat_surface(holder,"Голубой кристалл",points,colors,_crystal_material(),shadows)

func _build_pebbles(holder: Node3D, random: RandomNumberGenerator, base: Color, shadows: bool) -> void:
	for index in range(random.randi_range(1,3)):
		var r := random.randf_range(.12,.24)
		var outline := PackedVector2Array()
		for corner in range(6):
			var angle := TAU*corner/6.0+random.randf_range(-.3,.3)
			outline.append(Vector2(cos(angle)*r*1.35,sin(angle)*r*.8))
		var pebble := Node3D.new()
		pebble.position = Vector3((index-1.5)*.30+random.randf_range(-.06,.06),r*.5,.0)
		holder.add_child(pebble)
		var tone := base.lightened(random.randf_range(-.02,.06))
		var mesh := _outcrop(pebble,outline,-.12,.06,.26,r*.45,r*.40,.66,tone,stone_material)
		_skirt(pebble,outline,.05,-.06,base,.04,.06).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if shadows else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

func _decor_route_clear(point: Vector2, radius: float) -> bool:
	# Keep the line of throws and swings readable: no tall decor on the spine.
	return absf(point.x-_route_x(point.y))>radius

func _build_decor(index: int, parent: Node3D) -> void:
	# Decor follows the boulders: grass on their upper rims and in the creases,
	# crystal clusters on side rims open to the sky, pebbles at their feet.
	_use_layer(0)
	var budget := 36 if quality=="high" else 22 if quality=="balanced" else 8
	var crystal_budget := 5 if quality=="high" else 3 if quality=="balanced" else 1
	var random := layout.rng(index,902)
	var candidates: Array = []
	for boulder in front_band(index):
		var points: PackedVector2Array = boulder["points"]
		var edge_normals: PackedVector2Array = boulder["n"]
		for i in range(points.size()):
			var outward := -edge_normals[i]
			var at: Vector2 = points[i].lerp(points[(i+1)%points.size()],random.randf_range(.2,.8))
			if outward.y>.45: candidates.append([at,"grass",outward])
			elif outward.y<-.55: candidates.append([at,"pebbles",outward])
			elif outward.y>-.25: candidates.append([at,"crystal",outward])
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
		var holder := Node3D.new()
		holder.name = "Процедурный декор_%d" % placed
		parent.add_child(holder)
		# Sit exactly on the facet plane and lean with the rim.
		holder.position = Vector3(point.x,point.y,wall_depth(point)+.02)
		var normal := surface_normal(point)
		holder.rotation.x = -clampf(normal.y,-.4,.4)*.6
		match kind:
			"crystal":
				holder.rotation.z = clampf(-outward.x*.3,-.3,.3)
				_build_crystal(holder,random,quality!="battery",random.randi_range(3,6) if quality=="high" else random.randi_range(3,4))
			"grass":
				holder.rotation.z = clampf(-outward.x*.5,-.5,.5)
				holder.scale = Vector3.ONE*random.randf_range(1.3,1.8)
				_build_grass(holder,random,quality=="high")
			_:
				_build_pebbles(holder,random,zone_color(point.y),quality=="high")
		placed += 1

# --- Gameplay objects ---------------------------------------------------------

func build_obstacle(object: Dictionary, parent: Node3D) -> void:
	if not object.get("massif",false):
		super.build_obstacle(object,parent)
		return
	var holder := Node3D.new()
	parent.add_child(holder)
	var p: Vector2 = object["pos"]
	var d: Vector2 = object["dimensions"]
	# Hazards are set into the boulder like any other block of the massif: a
	# low profile flush with the wall, a dark seam all round, rubble at the
	# foot. Danger reads from the red-brown stone, ember-lit cracks and a warm
	# glint on the upper edges only, not from a sticker outline.
	holder.position = Vector3(p.x,p.y,minf(OBSTACLE_Z,wall_depth(p)+.32))
	object["visual"] = holder
	var polygon: PackedVector2Array = object["polygon"]
	var variant := int(object.get("variant",0))
	var tints := [Color("7a5040"),Color("6e4a44"),Color("7c5640")]
	var color: Color = zone_color(p.y).darkened(.30).lerp(tints[variant%3],.45)
	var refined := _refine_polygon(polygon)
	var wall := wall_depth(p)-holder.position.z
	var top := _polygon_top(polygon)
	var bottom := -_polygon_top(_mirror_y(polygon))
	var height := top-bottom
	_outcrop(holder,refined,clampf(wall-.3,-2.4,-.5),.18,.56,height*.20,height*.24,.84,color,obstacle_material)
	_skirt(holder,refined,.17,wall-.06,zone_color(p.y).darkened(.05),.18,.32)
	var random := RandomNumberGenerator.new()
	random.seed = int(absf(p.x*733.0+p.y*977.0))+variant
	var width := _polygon_width(polygon)
	for crack in range(2 if width<2.0 else 3):
		var start := Vector2(lerpf(-width*.3,width*.3,(crack+.5)/3.0)+random.randf_range(-.1,.1),top-height*.22)
		var path := PackedVector2Array([start])
		for step in range(3):
			path.append(path[-1]+Vector2(random.randf_range(-.14,.14),-height*random.randf_range(.12,.2)))
		_crack(holder,path,.035,.61,color.darkened(.55))
		if quality!="battery": _crack(holder,path,.012,.62,Color("e07040"),"obstacle_ember")
	_edge_glint(holder,refined,.03,.58,Color("e0925f"))
	for side in [-1.0,1.0]:
		var rubble := Node3D.new()
		rubble.position = Vector3(side*width*.32,bottom-.05,wall+.15)
		holder.add_child(rubble)
		_build_pebbles(rubble,random,color.lightened(.05),quality=="high")

func _edge_glint(parent: Node3D, polygon: PackedVector2Array, width: float, z: float, color: Color) -> void:
	# A thin warm line only on edges facing up, where the sun would catch.
	var center := Vector2.ZERO
	for point in polygon: center += point
	center /= polygon.size()
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	var count := 0
	for i in range(polygon.size()):
		var a: Vector2 = polygon[i]
		var b: Vector2 = polygon[(i+1)%polygon.size()]
		var outward := Vector2(-(b-a).y,(b-a).x).normalized()
		if outward.dot((a+b)*.5-center)<0: outward = -outward
		if outward.y<.35: continue
		var inward := -outward*width
		_triangle(surface,Vector3(a.x,a.y,z),Vector3(b.x,b.y,z),Vector3(b.x+inward.x,b.y+inward.y,z),color)
		_triangle(surface,Vector3(a.x,a.y,z),Vector3(b.x+inward.x,b.y+inward.y,z),Vector3(a.x+inward.x,a.y+inward.y,z),color)
		count += 1
	if count==0: return
	var mesh := MeshInstance3D.new()
	mesh.name = "Тёплая кромка"
	mesh.mesh = surface.commit()
	var material: StandardMaterial3D = world.mat("obstacle_glint",Color.WHITE,false)
	material.vertex_color_use_as_albedo = true
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	mesh.material_override = material
	mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mesh)

const GRIP_MATERIALS := ["известняк","песчаник","мох","лёд","аметист"]

func grip_material_name(object: Dictionary) -> String:
	if bool(object.get("permanent",false)): return "гранит"
	return GRIP_MATERIALS[clampi(int(object.get("kind",0)),0,GRIP_MATERIALS.size()-1)]

func build_anchor(object: Dictionary, parent: Node3D) -> void:
	# Grips are outcrops of the massif with a shape and material per type, so
	# the kind reads before the status strip: chipped limestone (single use),
	# split sandstone (fragile), mossy rounded stone (elastic), glazed ice
	# (slippery), amethyst (crystal) and dark granite with a bracket
	# (permanent). The shell stays inside the gameplay polygon.
	var holder := Node3D.new()
	parent.add_child(holder)
	var p: Vector2 = object["pos"]
	# Grips grow out of the boulder: their plane follows the stone just in
	# front of it, so cast shadows stay short and attached.
	holder.position = Vector3(p.x,p.y,minf(GRIP_Z,wall_depth(p)+.30))
	object["visual"] = holder
	var kind := int(object.get("kind",0))
	var id := int(object.get("id",0))
	var style := posmod(id*7+kind,5)
	var material_name := grip_material_name(object)
	var material: Material = stone_material
	var rock := zone_color(p.y)
	var stone := rock.lightened(.03)
	var top_tint := Color(0,0,0,0)
	var outline := _grip_outline(object["polygon"],id)
	match material_name:
		"известняк":
			if style==1: stone = rock.darkened(.06)
			elif style==3: stone = rock.lerp(Color("b4ad98"),.25)
		"песчаник":
			stone = rock.lerp(Color("a07c5a"),.38)
			outline = _jagged(outline,id)
		"мох":
			stone = zone_color(p.y).darkened(.04)
			top_tint = Color("6a9443")
			outline = _rounded(outline,2)
		"лёд":
			stone = Color("a6d2e6")
			material = _ice_material()
			outline = _rounded(outline,2)
		"аметист":
			stone = Color("8a6ad0")
			material = _amethyst_material()
		"гранит":
			stone = zone_color(p.y).lerp(Color("62676c"),.6)
	# Hook contacts snap to this drawn silhouette, not to the wider assist polygon.
	object["surface"] = outline
	var wall := wall_depth(p)-holder.position.z
	var back := clampf(wall-.25,-2.8,-.45)
	var top := _polygon_top(outline)
	var bottom := -_polygon_top(_mirror_y(outline))
	var height := top-bottom
	var width := _polygon_width(outline)
	var front_top := top-height*.32
	_skirt(holder,outline,.30,wall-.06,rock,.14,.30)
	if material_name=="песчаник" or (material_name=="известняк" and style==2 and width>1.2):
		# Split outcrop: blocks with dark joints between them.
		var cuts := [-width*.18,width*.18] if material_name=="песчаник" else [0.0]
		var edges := [-INF]+cuts+[INF]
		for piece in range(edges.size()-1):
			var part := PackedVector2Array()
			for point in outline: part.append(Vector2(clampf(point.x,float(edges[piece])+.03,float(edges[piece+1])-.03),point.y))
			_outcrop(holder,_dedupe(part),back,.30-piece*.02,.72-piece*.04,height*.32,height*.34,.74,stone.darkened(piece*.04),material,top_tint)
	else:
		_outcrop(holder,outline,back,.32,.76,height*.32,height*.34,.74 if material_name!="аметист" else .66,stone,material,top_tint)
	match material_name:
		"известняк":
			if style in [0,3,4]:
				var start := Vector2(width*(-.16 if style!=3 else .14),front_top-.02)
				_crack(holder,PackedVector2Array([start,start+Vector2(.07,-height*.18),start+Vector2(.02,-height*.36),start+Vector2(.08,-height*.5)]),.026,.77,stone.darkened(.55))
		"песчаник":
			for crack in [-.3,.3]:
				var start := Vector2(width*crack,front_top-.02)
				_crack(holder,PackedVector2Array([start,start+Vector2(.05,-height*.2),start+Vector2(-.02,-height*.42)]),.024,.77,stone.darkened(.55))
			var crumbs := Node3D.new()
			crumbs.position = Vector3(0,bottom-.12,wall+.1)
			crumbs.scale = Vector3.ONE*.55
			holder.add_child(crumbs)
			_build_pebbles(crumbs,layout.rng(id,913),stone,false)
		"мох":
			var tuft := Node3D.new()
			tuft.position = Vector3(width*(.28 if id%2==0 else -.28),top-.06,.36)
			tuft.scale = Vector3.ONE*.6
			holder.add_child(tuft)
			_build_grass(tuft,layout.rng(id,914),false,.7)
		"лёд":
			_icicles(holder,bottom,width,id)
		"аметист":
			var shards := Node3D.new()
			shards.position = Vector3(width*.30,top-.18,.40)
			shards.scale = Vector3.ONE*.38
			holder.add_child(shards)
			_build_crystal(shards,layout.rng(id,915),false,3)
		"гранит":
			# Forged bracket: dark steel plate with brass bolts, reads as fixed.
			var steel: StandardMaterial3D = world.mat("grip_steel",Color("4d555c"),false)
			steel.metallic = .55
			steel.roughness = .38
			var brass: StandardMaterial3D = world.mat("grip_brass",Color("e2b558"),false)
			brass.metallic = .7
			brass.roughness = .3
			for side in [-1,1]:
				var plate: MeshInstance3D = world.box("Металлическое крепление",holder.position+Vector3(side*width*.34,front_top-height*.32,.76),Vector3(.12,height*.5,.05),steel,holder)
				plate.rotation.z = side*.12
				world.box("Золотое крепление",holder.position+Vector3(side*width*.34,front_top-height*.2,.80),Vector3(.06,.06,.04),brass,holder)
	# Short status strip on the top edge of the front face.
	var strip_color: Color = MountainWorld.COLORS[clampi(kind,0,MountainWorld.COLORS.size()-1)]
	var strip_material: StandardMaterial3D = world.mat("grip_strip_%d" % kind,strip_color,false)
	strip_material.emission_enabled = true
	strip_material.emission = strip_color
	strip_material.emission_energy_multiplier = .45
	var strip: MeshInstance3D = world.box("Полоса состояния",holder.position+Vector3(-.04,front_top+height*.13,.62),Vector3(width*.34,.09,.05),strip_material,holder)
	strip.rotation.x = -.7
	strip.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

func _rounded(points: PackedVector2Array, passes: int) -> PackedVector2Array:
	# Chaikin corner cutting: a smoother outline that only shrinks inwards.
	var result := points
	for step in range(passes):
		var next := PackedVector2Array()
		for i in range(result.size()):
			var a := result[i]
			var b := result[(i+1)%result.size()]
			next.append(a.lerp(b,.25))
			next.append(a.lerp(b,.75))
		result = next
	return result

func _jagged(points: PackedVector2Array, seed_value: int) -> PackedVector2Array:
	# Crumbling edge: extra notches pulled inwards between the corners.
	var random := RandomNumberGenerator.new()
	random.seed = seed_value*613+3
	var center := Vector2.ZERO
	for point in points: center += point
	center /= points.size()
	var result := PackedVector2Array()
	for i in range(points.size()):
		var a := points[i]
		var b := points[(i+1)%points.size()]
		result.append(a)
		if a.distance_to(b)>.25:
			var notch := a.lerp(b,random.randf_range(.35,.65))
			result.append(notch+(center-notch)*random.randf_range(.12,.24))
	return result

func _icicles(holder: Node3D, bottom: float, width: float, seed_value: int) -> void:
	var random := layout.rng(seed_value,916)
	var points := PackedVector3Array()
	var colors := PackedColorArray()
	for index in range(3):
		var x := (index-1)*width*.24+random.randf_range(-.05,.05)
		var length := random.randf_range(.18,.32)
		var r := .05
		var base := Vector3(x,bottom+.06,.30)
		var tip := base+Vector3(0,-length,0)
		points.append_array(PackedVector3Array([base+Vector3(-r,0,0),tip,base+Vector3(r,0,0)]))
		colors.append(Color("cfeeff"))
		points.append_array(PackedVector3Array([base+Vector3(r,0,0),tip,base+Vector3(0,0,r)]))
		colors.append(Color("9fd0ea"))
	_flat_surface(holder,"Сосульки",points,colors,_ice_material(),false)

func _ice_material() -> StandardMaterial3D:
	var material := _vertex_material("grip_ice")
	material.roughness = .12
	material.metallic_specular = .9
	material.rim_enabled = true
	material.rim = .45
	material.rim_tint = .2
	return material

func _amethyst_material() -> StandardMaterial3D:
	var material := _vertex_material("grip_amethyst")
	material.roughness = .2
	material.metallic_specular = .8
	material.emission_enabled = true
	material.emission = Color("6a3fc0")
	material.emission_energy_multiplier = .25
	material.rim_enabled = true
	material.rim = .35
	return material

func _grip_outline(polygon: PackedVector2Array, seed_value: int) -> PackedVector2Array:
	# An angular knob of rock inside the gameplay polygon: each corner is
	# pulled in by a deterministic amount and the top edge gets one chipped
	# notch, so grips share the broad facets of the boulders. Only the
	# underside drops slightly, to show the dark lower face.
	var random := RandomNumberGenerator.new()
	random.seed = seed_value*7919+17
	var center := Vector2.ZERO
	for point in polygon: center += point
	center /= polygon.size()
	var bottom := -_polygon_top(_mirror_y(polygon))
	var result := PackedVector2Array()
	var top_edge := 0
	var top_y := -INF
	for i in range(polygon.size()):
		var middle: Vector2 = (polygon[i]+polygon[(i+1)%polygon.size()])*.5
		if middle.y>top_y:
			top_y = middle.y
			top_edge = i
	for i in range(polygon.size()):
		var point: Vector2 = polygon[i]
		point += (center-point)*random.randf_range(.03,.13)
		if point.y<center.y: point.y -= .12*clampf((center.y-point.y)/maxf(.01,center.y-bottom),0,1)
		result.append(point)
		if i==top_edge:
			var next: Vector2 = polygon[(i+1)%polygon.size()]
			var notch := point.lerp(next,random.randf_range(.35,.6))
			result.append(notch+(center-notch)*random.randf_range(.10,.2))
	return _dedupe(result)

func _mirror_y(points: PackedVector2Array) -> PackedVector2Array:
	var result := PackedVector2Array()
	for point in points: result.append(Vector2(point.x,-point.y))
	return result

func _outcrop(parent: Node3D, outline: PackedVector2Array, z_back: float, z_rim: float, z_cap: float, top_band: float, low_band: float, squeeze: float, base: Color, material: Material, top_tint: Color = Color(0,0,0,0)) -> MeshInstance3D:
	# A stone outcrop seen straight on: a lit top bevel tilted towards the sun,
	# a front face, and a broad underside sloping back into shade. The outer
	# rim is the outline itself, so the shell never grows past it.
	var low := INF
	var high := -INF
	var center := Vector2.ZERO
	for point in outline:
		low = minf(low,point.y)
		high = maxf(high,point.y)
		center += point
	center /= maxf(1,outline.size())
	var inner := PackedVector2Array()
	for point in outline:
		var t := (point.y-low)/maxf(.01,high-low)
		inner.append(Vector2(center.x+(point.x-center.x)*squeeze,lerpf(low+low_band,high-top_band,t)))
	var points := PackedVector3Array()
	var colors := PackedColorArray()
	var count := outline.size()
	var apex := Vector3(center.x-(high-low)*.25,lerpf(low+low_band,high-top_band,.62),z_cap+.18)
	for i in range(count):
		var j := (i+1)%count
		var tone := (facet_hash(i,count,base.r*31.0)-.5)*.14
		var face := base.lightened(tone) if tone>=0 else base.darkened(-tone)
		points.append_array(PackedVector3Array([apex,Vector3(inner[i].x,inner[i].y,z_cap),Vector3(inner[j].x,inner[j].y,z_cap)]))
		colors.append(face.lightened(.04))
		# Bevel tone follows its facing: up is lit, down is the dark underside.
		var facing := ((outline[i]+outline[j])*.5-center).normalized().y
		var bevel := face.lightened(.12*facing) if facing>0 else face.darkened(-.08*facing)
		# Moss and similar caps sit on the upward bevels.
		if top_tint.a>0 and facing>.3: bevel = top_tint.lerp(bevel,.45)
		points.append_array(PackedVector3Array([Vector3(outline[i].x,outline[i].y,z_rim),Vector3(outline[j].x,outline[j].y,z_rim),Vector3(inner[j].x,inner[j].y,z_cap)]))
		colors.append(bevel)
		points.append_array(PackedVector3Array([Vector3(outline[i].x,outline[i].y,z_rim),Vector3(inner[j].x,inner[j].y,z_cap),Vector3(inner[i].x,inner[i].y,z_cap)]))
		colors.append(bevel)
		var side := face.darkened(.10)
		var root_a := center+(outline[i]-center)*.94
		var root_b := center+(outline[j]-center)*.94
		points.append_array(PackedVector3Array([Vector3(root_a.x,root_a.y,z_back),Vector3(root_b.x,root_b.y,z_back),Vector3(outline[j].x,outline[j].y,z_rim)]))
		colors.append(side)
		points.append_array(PackedVector3Array([Vector3(root_a.x,root_a.y,z_back),Vector3(outline[j].x,outline[j].y,z_rim),Vector3(outline[i].x,outline[i].y,z_rim)]))
		colors.append(side)
	var mesh := _flat_surface(parent,"Каменный выступ",points,colors,material,true)
	return mesh

func _skirt(parent: Node3D, outline: PackedVector2Array, z_rim: float, z_wall: float, color: Color, side: float, below: float) -> MeshInstance3D:
	# The root of an object: a ring of facets in the massif's own stone and
	# shader, sloping from the object's rim back into the boulder. It is
	# widest under the object, so every grip, hazard and shelf reads as a
	# knob of the rock instead of a plate laid on it.
	var center := Vector2.ZERO
	for point in outline: center += point
	center /= outline.size()
	var points := PackedVector3Array()
	var colors := PackedColorArray()
	var outer := PackedVector2Array()
	for point in outline:
		var direction := (point-center).normalized()
		outer.append(point+direction*(side+below*clampf(-direction.y,0,1))+Vector2(0,-below*.35))
	for i in range(outline.size()):
		var j := (i+1)%outline.size()
		var facing := ((outline[i]+outline[j])*.5-center).normalized()
		var light := facing.dot(Vector2(-.6,.8))
		var tone := color.lightened(.08*light) if light>0 else color.darkened(-.10*light)
		tone = tone.lightened((facet_hash(i,outline.size(),color.g*17.0)-.5)*.06)
		points.append_array(PackedVector3Array([Vector3(outline[i].x,outline[i].y,z_rim),Vector3(outer[j].x,outer[j].y,z_wall),Vector3(outline[j].x,outline[j].y,z_rim)]))
		colors.append(tone)
		points.append_array(PackedVector3Array([Vector3(outline[i].x,outline[i].y,z_rim),Vector3(outer[i].x,outer[i].y,z_wall),Vector3(outer[j].x,outer[j].y,z_wall)]))
		colors.append(tone.darkened(.03))
	# Flush with the wall, so it never casts a shadow of its own.
	var mesh := _flat_surface(parent,"Каменное основание",points,colors,stone_material,false)
	return mesh

func wall_depth(point: Vector2) -> float:
	# Front skin depth at a point, from the same facet planes as the mesh.
	_use_layer(0)
	return _depth(point)

func _dedupe(points: PackedVector2Array) -> PackedVector2Array:
	var result := PackedVector2Array()
	for point in points:
		if result.is_empty() or result[-1].distance_to(point)>.02: result.append(point)
	if result.size()>1 and result[0].distance_to(result[-1])<.02: result.remove_at(result.size()-1)
	return result

func _polygon_top(points: PackedVector2Array) -> float:
	var top := -INF
	for point in points: top = maxf(top,point.y)
	return top

func _polygon_width(points: PackedVector2Array) -> float:
	var low := INF
	var high := -INF
	for point in points:
		low = minf(low,point.x)
		high = maxf(high,point.x)
	return high-low

func _crack(parent: Node3D, points: PackedVector2Array, width: float, z: float, color: Color, glow_key: String = "") -> void:
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in range(points.size()-1):
		var a := points[i]
		var b := points[i+1]
		var taper := 1.0-float(i)/points.size()*.6
		var n := Vector2(-(b-a).y,(b-a).x).normalized()*width*taper
		_triangle(surface,Vector3(a.x+n.x,a.y+n.y,z),Vector3(b.x+n.x*.7,b.y+n.y*.7,z),Vector3(b.x-n.x*.7,b.y-n.y*.7,z),color)
		_triangle(surface,Vector3(a.x+n.x,a.y+n.y,z),Vector3(b.x-n.x*.7,b.y-n.y*.7,z),Vector3(a.x-n.x,a.y-n.y,z),color)
	var mesh := MeshInstance3D.new()
	mesh.name = "Трещина"
	mesh.mesh = surface.commit()
	var material: StandardMaterial3D = world.mat("stone_crack" if glow_key.is_empty() else glow_key,Color.WHITE,false)
	material.vertex_color_use_as_albedo = true
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	if not glow_key.is_empty():
		# Faint ember light deep in the hazard's cracks.
		material.emission_enabled = true
		material.emission = color
		material.emission_energy_multiplier = .6
	mesh.material_override = material
	mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mesh)

func _crystal_material() -> StandardMaterial3D:
	var material: StandardMaterial3D = world.mat("decor_crystal_v3",Color.WHITE,false)
	material.vertex_color_use_as_albedo = true
	material.vertex_color_is_srgb = true
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	material.roughness = .22
	material.metallic_specular = .8
	material.emission_enabled = true
	material.emission = Color("2f7fd0")
	material.emission_energy_multiplier = .16
	material.rim_enabled = true
	material.rim = .25
	material.rim_tint = .5
	return material

func _refine_polygon(polygon: PackedVector2Array) -> PackedVector2Array:
	# Add edge break points without changing the gameplay silhouette. This gives
	# obstacles a denser, more deliberate mesh than the six-point collision
	# contour alone.
	var refined := PackedVector2Array()
	for i in range(polygon.size()):
		var a: Vector2 = polygon[i]
		var b: Vector2 = polygon[(i+1)%polygon.size()]
		refined.append(a)
		refined.append(a.lerp(b,.46))
	return refined

func build_ledge(object: Dictionary, parent: Node3D) -> void:
	var left: float = object["left"]
	var right: float = object["right"]
	var top: float = object["top"]
	var center := Vector2((left+right)*.5,top)
	var width := right-left
	var style := int(object.get("style",posmod(int(absf(center.x*97.0+top*31.0)),3)))
	var polygon := PackedVector2Array()
	if style==0: # broad cantilever with a broken front lip
		polygon = PackedVector2Array([Vector2(-width*.50,0),Vector2(width*.40,0),Vector2(width*.50,-.16),Vector2(width*.34,-.48),Vector2(-width*.44,-.42),Vector2(-width*.54,-.16)])
	elif style==1: # saddle shaped shelf, slightly asymmetric
		polygon = PackedVector2Array([Vector2(-width*.50,0),Vector2(-width*.12,.07),Vector2(width*.46,0),Vector2(width*.50,-.22),Vector2(width*.28,-.5),Vector2(-width*.42,-.38)])
	else: # wedge anchored into the mountain
		polygon = PackedVector2Array([Vector2(-width*.50,0),Vector2(width*.50,.04),Vector2(width*.39,-.30),Vector2(width*.08,-.58),Vector2(-width*.47,-.35)])
	var holder := Node3D.new()
	parent.add_child(holder)
	holder.position = Vector3(center.x,center.y,LEDGE_Z)
	# Rest ledges: broad, light, sunlit top bevel with a grassy lip.
	var rock := zone_color(top).lightened(.02)
	var wall := wall_depth(center)-LEDGE_Z
	_outcrop(holder,polygon,clampf(wall-.3,-2.2,-.5),.30,.62,.16,.20,.84,rock,stone_material)
	_skirt(holder,polygon,.29,wall-.06,zone_color(top),.14,.38)
	var lip := RandomNumberGenerator.new()
	lip.seed = int(absf(center.x*997.0+top*131.0))
	for tuft in range(3 if quality!="battery" else 1):
		var grass := Node3D.new()
		grass.position = Vector3(lerpf(-width*.4,width*.4,lip.randf()),-.02,.62)
		grass.scale = Vector3.ONE*.75
		holder.add_child(grass)
		_build_grass(grass,lip,false)
