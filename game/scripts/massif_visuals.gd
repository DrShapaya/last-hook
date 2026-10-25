class_name MassifVisuals
extends MountainVisuals

# The climbing face as a pile of rock masses (RockMassSpec). Each 24 m band
# lays out its masses from the seed and the gameplay objects in it:
#   trunk     blocks stacked along the route line
#   body      larger blocks behind them, the mountain's depth
#   fill      slabs that keep the route corridor on stone
#   seat      a block for a grip, find or hazard no other mass carries
#   shelf     rest ledges, built out of the face (finds get none)
#   island    side clusters and pillars, with sky between them and the trunk
#   overhang  a block jutting out over open space, deep underside
#   arch      two pillars and a lintel round a real opening
#   rubble    small blocks at the feet of big ones, away from objects
# Every mounted object asks surface_query() for the frontmost mass at its
# gameplay point; nothing here moves a gameplay coordinate.

# Grips stand in front of the stone, never past this plane (gameplay is XY).
const GRIP_Z := 2.35
const BAND := 24.0
const BIN := 4.0
const ROUTE_CLEAR := 2.4
const FIND_CLEARANCE := 1.05
const FRONT_LIMIT := 1.95
# Distant parallax layers: depth, share of camera motion and haze.
const FAR_LAYERS := [{"z":-9.0,"follow":.42,"haze":.42,"cell":1.5},{"z":-15.0,"follow":.68,"haze":.62,"cell":2.0}]
# Bevel width / lift per landform: Vector3(top, side, bottom).
const SHAPES := {
	"buttress":[Vector3(.5,.32,.72),Vector3(.85,.8,1.0)],
	"slab":[Vector3(.46,.3,.58),Vector3(.75,.7,.85)],
	"pillar":[Vector3(.42,.45,.5),Vector3(.9,.95,.9)],
	"island":[Vector3(.55,.45,.85),Vector3(.95,.9,1.1)],
	"overhang":[Vector3(.5,.5,1.35),Vector3(.8,.95,1.7)],
	"arch":[Vector3(.45,.45,.6),Vector3(.85,.95,1.1)],
	"seat":[Vector3(.42,.34,.5),Vector3(.75,.65,.75)],
	"shelf":[Vector3(.4,.26,.32),Vector3(.9,.7,.6)],
	"rubble":[Vector3(.2,.18,.22),Vector3(.32,.3,.3)],
}
var massif: MassifLayout
var rock_material := ShaderMaterial.new()
var far_materials: Array[ShaderMaterial] = []
var far_shader: Shader
var band_masses: Dictionary = {}
var band_islands: Dictionary = {}
var mass_bins: Dictionary = {}
var masses_by_id: Dictionary = {}
var query_cache: Dictionary = {}
var route_cache: Dictionary = {}
var mass_signature := Vector4i(-1,-1,-1,-1)
# Openings of the arches: body and fill masses keep out of them.
var arch_openings: Array[Rect2] = []

func _init(owner_world: Node3D, source: MountainLayout) -> void:
	super._init(owner_world,source)
	massif = source as MassifLayout
	rock_material.shader = preload("res://shaders/massif_rock.gdshader")
	rock_material.set_shader_parameter("facet_strength",1.0)
	_apply_rock_profile(rock_material,profile_at(0))
	# Distant ranges: one flat facet light, no shadow lookups, mixed into the
	# sky colour. Cheap enough for every preset, including phones.
	far_shader = Shader.new()
	far_shader.code = "shader_type spatial; render_mode unshaded, cull_disabled, shadows_disabled; uniform vec3 haze : source_color = vec3(.55,.74,.92); uniform float haze_amount = .7; varying vec3 world_pos; void vertex(){ world_pos=(MODEL_MATRIX*vec4(VERTEX,1.0)).xyz; } void fragment(){ vec3 n=normalize(cross(dFdx(world_pos),dFdy(world_pos))); if(n.z<0.0){ n=-n; } float l=dot(n,normalize(vec3(-.55,.62,.56))); vec3 c=COLOR.rgb*mix(.78,1.12,smoothstep(-.2,.9,l)); ALBEDO=mix(c,haze,haze_amount); }"
	for settings in FAR_LAYERS:
		var material := ShaderMaterial.new()
		material.shader = far_shader
		material.set_shader_parameter("haze_amount",settings["haze"])
		far_materials.append(material)

func _apply_rock_profile(material: ShaderMaterial, profile: GripBiomeProfile) -> void:
	var rock: Dictionary = profile.rock_material
	material.set_shader_parameter("roughness_value",float(rock["roughness"]))
	material.set_shader_parameter("detail_strength",float(rock["normal_strength"]))
	material.set_shader_parameter("strata_scale",float(rock["strata_scale"]))

# The expedition's rock carries its act's weather (moss, snow, dust) instead of
# the first location's height bands; one material per act.
var act_materials: Dictionary = {}

func rock_material_at(height: float) -> ShaderMaterial:
	if not layout is ExpeditionLayout: return rock_material
	var expedition := layout as ExpeditionLayout
	var act := expedition.act_index_at(height)
	var profile_id := str(expedition.span(act)["def"]["biome_profile"])
	if not act_materials.has(profile_id):
		var material := rock_material.duplicate() as ShaderMaterial
		var profile := GripBiomeProfile.named(profile_id)
		_apply_rock_profile(material,profile)
		var weather: Dictionary = profile.weathering_rules
		material.set_shader_parameter("moss_override",clampf(float(weather["moss"])/.6,0,1))
		material.set_shader_parameter("snow_override",float(weather["snow"]))
		material.set_shader_parameter("dust_amount",float(weather["dust"]))
		material.set_shader_parameter("dust_color",profile.rock_palette["warm"])
		act_materials[profile_id] = material
	return act_materials[profile_id]

# Distant ranges are painted by the sky shader now: they stand on the bottom
# of the frame and sink with altitude. The banded 3D peaks (and the pines in
# front of them) floated in mid-air between bands, so none are built.
func far_layer_count() -> int:
	return 0

# --- Layout hooks ---------------------------------------------------------------
# The massif only needs the route line, the landform of a region and an
# optional support root, so any layout can carry it.

func route_x_at(y: float) -> float:
	return massif.route_x(y)

func region_form(region: int) -> Dictionary:
	return massif.landform(region)

func region_of(y: float) -> int:
	return int(floor(y/MassifLayout.REGION_HEIGHT))

func landmark_zone(point: Vector2) -> int:
	return clampi(int(point.y/20.0),0,5)

# Landmark family of a place: the act's own set pieces on v14, otherwise the
# family of the height zone (or the location's style, see Legacy).
func landmark_family(point: Vector2, random: RandomNumberGenerator) -> String:
	if layout is ExpeditionLayout:
		var families: Array = (layout as ExpeditionLayout).span((layout as ExpeditionLayout).act_index_at(point.y))["def"].get("landmarks",[])
		if not families.is_empty(): return str(families[random.randi_range(0,families.size()-1)])
	return LandmarkVisuals.ZONE_FAMILIES[landmark_zone(point)]

func _act_color(height: float) -> Color:
	# Base rock of the act's profile, blended over a few metres at a border.
	var expedition := layout as ExpeditionLayout
	var act := expedition.act_index_at(height)
	var info := expedition.span(act)
	var here: Color = GripBiomeProfile.named(str(info["def"]["biome_profile"])).rock_material["base_color"]
	var above := float(info["y_end"])-height
	if above<3.0:
		var next: Color = GripBiomeProfile.named(str(expedition.span(act+1)["def"]["biome_profile"])).rock_material["base_color"]
		here = here.lerp(next,.5-above/6.0)
	var below := height-float(info["y_start"])
	if below<3.0 and act>0:
		var previous: Color = GripBiomeProfile.named(str(expedition.span(act-1)["def"]["biome_profile"])).rock_material["base_color"]
		here = previous.lerp(here,.5+below/6.0)
	return here

func _route_x(y: float) -> float:
	var key := int(round(y*8.0))
	if not route_cache.has(key): route_cache[key] = route_x_at(key/8.0)
	return route_cache[key]

func zone_color(height: float) -> Color:
	if layout is ExpeditionLayout: return _act_color(height)
	# Base rock of the zone's profile, blended across zone borders.
	var t := clampf(height/20.0,0,5.0)
	var index := mini(int(t),4)
	var here: Color = GripBiomeProfile.for_place(layout.location,index*20.0+1).rock_material["base_color"]
	var next: Color = GripBiomeProfile.for_place(layout.location,(index+1)*20.0+1).rock_material["base_color"]
	return here.lerp(next,smoothstep(.7,1.0,t-index))

# --- Masses ---------------------------------------------------------------------

func _refresh_masses() -> void:
	# Bands depend on the gameplay objects in them; rebuild when any are added.
	var signature := Vector4i(layout.anchors.size(),layout.finds.size(),layout.obstacles.size(),layout.ledges.size())
	if signature==mass_signature: return
	mass_signature = signature
	band_masses.clear()
	band_islands.clear()
	mass_bins.clear()
	masses_by_id.clear()
	arch_openings.clear()
	query_cache.clear()

func _add_mass(list: Array, band: int, role: String, landform: String, contour: PackedVector2Array, z_rim: float, random: RandomNumberGenerator, z_back: float = -3.4, inner_direction: Vector2 = Vector2.ZERO, lifts_override: Vector3 = Vector3.ZERO, host: RockMassSpec = null) -> RockMassSpec:
	var mass := RockMassSpec.new()
	mass.id = band*1000+list.size()
	mass.band = band
	mass.role = role
	mass.landform = landform
	mass.seed_stream = 947
	mass.outer_contour = contour
	mass.z_rim = z_rim
	mass.z_back = minf(z_back,z_rim-.6)
	mass.inner_direction = inner_direction
	# A lobe, seat or shelf of a host joins its body: same group, same tone.
	mass.group = host.group if host!=null else mass.id
	mass.tone = host.tone if host!=null else random.randf()
	var center := Vector2.ZERO
	for point in contour: center += point
	center /= maxf(1,contour.size())
	mass.region = region_of(center.y)
	mass.material_profile = profile_at(center.y).id
	var shape: Array = SHAPES.get(landform,SHAPES["buttress"])
	var lifts: Vector3 = shape[1] if lifts_override==Vector3.ZERO else lifts_override
	var size := Rect2(contour[0],Vector2.ZERO)
	for point in contour: size = size.expand(point)
	var span := sqrt(size.size.x*size.size.y)
	# Sculpted front: facets under a metre over a high rounded dome, smaller
	# on small pieces, so a boulder turns its facets to the light all over.
	mass.facet_size = clampf(span*.12,.5,.95)
	mass.dome = clampf(span*.2,.1,1.5) if landform not in ["shelf","rubble"] else .08
	mass.slope = Vector2(random.randf_range(-.05,.05),random.randf_range(-.06,.03))
	mass.z_limit = FRONT_LIMIT
	# Front of a mass never reaches the plane of the grips and the hero.
	var room := FRONT_LIMIT-z_rim
	var largest := maxf(lifts.x,maxf(lifts.y,lifts.z))*1.15+mass.dome
	if largest>room and room>.2:
		lifts *= room/largest
		mass.dome *= room/largest
	if not mass.build(shape[0],lifts,0,0.0,random): return null
	list.append(mass)
	return mass

func _block(list: Array, band: int, role: String, landform: String, center: Vector2, size: Vector2, z_rim: float, random: RandomNumberGenerator, z_back: float = -3.4, host: RockMassSpec = null, turn_range: float = .34) -> RockMassSpec:
	var turn := random.randf_range(-turn_range,turn_range)
	# Masses of the face are rounded boulders; shelves, arches and overhangs
	# keep their straight block contours (they are built elsewhere).
	# Fill and seats carry gameplay objects to their corners: fuller boulders.
	var fullness := Vector2(3.4,4.2) if role in ["fill","seat"] else Vector2(2.6,3.2) if role=="trunk" else Vector2(2.2,2.9)
	var contour := RockMassSpec.boulder_contour(center,size,random,turn,fullness)
	if role in ["body","island","rubble","lobe"]:
		# Nothing fills an arch opening: the sky shows through it.
		var box := Rect2(contour[0],Vector2.ZERO)
		for point in contour: box = box.expand(point)
		for opening in arch_openings:
			if opening.grow(-.2).intersects(box): return null
	return _add_mass(list,band,role,landform,contour,z_rim,random,z_back,Vector2.ZERO,Vector3.ZERO,host)

func _host(list: Array, band: int, role: String, center: Vector2, size: Vector2, z_rim: float, random: RandomNumberGenerator, z_back: float = -3.4) -> RockMassSpec:
	# A large host mass: one tilted body and one or two lobes fused to it at
	# slightly different depth, so the outline breaks into shoulders and
	# notches instead of one convex block.
	var body := _block(list,band,role,"buttress",center,size,z_rim,random,z_back,null,.45)
	if body==null: return null
	for lobe in range(2 if random.randf()<.3 else 1):
		var angle := random.randf()*TAU
		var at := center+Vector2(cos(angle)*size.x*.42,sin(angle)*size.y*.4)
		var lobe_size := size*random.randf_range(.42,.62)
		lobe_size = lobe_size.max(Vector2(2.2,2.0))
		_block(list,band,"lobe","buttress",at,lobe_size,z_rim+random.randf_range(-.3,.15),random,z_back,body,.3)
	return body

func _covering(list: Array, point: Vector2, margin: float) -> RockMassSpec:
	for mass in list:
		if mass.inside(point)>=margin: return mass
	return null

func _front_z(list: Array, point: Vector2, fallback: float) -> float:
	var best := -INF
	for mass in list:
		var hit: Dictionary = mass.surface_at(point)
		if not hit.is_empty(): best = maxf(best,float(hit["z"]))
	return best if best>-INF else fallback

func _objects_near(point: Vector2, reach: float) -> bool:
	for id in layout.nearby_ids(point.y-reach-1,point.y+reach+1):
		if layout.anchors[id]["pos"].distance_to(point)<reach+.6: return true
	for find in layout.finds:
		if find["pos"].distance_to(point)<reach+.6: return true
	for obstacle in layout.obstacles:
		if obstacle["pos"].distance_to(point)<reach+1.0: return true
	for ledge in layout.ledges:
		if point.x>float(ledge["left"])-reach and point.x<float(ledge["right"])+reach and absf(point.y-float(ledge["top"])+.5)<reach+.6: return true
	return false

func _seat(list: Array, band: int, point: Vector2, half: Vector2, random: RandomNumberGenerator) -> void:
	# A gameplay object always lies on stone, its whole outline with a small
	# margin. When no mass carries it, the nearest host grows a shoulder out
	# to it: a lobe of the same body reaching from the host over the object,
	# never a pedestal block of its own.
	if _carried(list,point,half): return
	var host: RockMassSpec = null
	var best := INF
	for mass in list:
		if mass.role=="rubble": continue
		var distance: float = -mass.inside(point)
		if distance<best:
			best = distance
			host = mass
	var anchor_to := host.centroid() if host!=null else Vector2(_route_x(point.y),point.y)
	var reach := (anchor_to-point).abs()
	var size := Vector2(clampf(maxf(half.x*2.0+1.8,reach.x*.9),3.2,8.0),clampf(maxf(half.y*2.0+1.6,reach.y*.9),2.8,7.0))
	var center := point.lerp(anchor_to,.4)
	var z := host.z_rim+random.randf_range(-.15,.1) if host!=null else -1.6
	for attempt in range(6):
		var mass := _block(list,band,"seat","buttress",center,size,clampf(z,-2.0,-.6),random,-3.4,host,.2)
		if mass!=null and _carried([mass],point,half): return
		if mass!=null: list.erase(mass)
		center = center.lerp(point,.45)
		size *= 1.12

func _carried(list: Array, point: Vector2, half: Vector2) -> bool:
	# Every corner of the object's box is on one mass, .15 m inside.
	for mass in list:
		var ok := true
		for corner in [Vector2(-half.x,-half.y),Vector2(half.x,-half.y),Vector2(half.x,half.y),Vector2(-half.x,half.y),Vector2.ZERO]:
			if mass.inside(point+corner)<.15:
				ok = false
				break
		if ok: return true
	return false

func front_band(band: int) -> Array:
	# Masses whose layout belongs to one 24 m band. A band depends only on the
	# seed and the gameplay objects in it, so build order never matters.
	_refresh_masses()
	if not band_masses.has(band): _generate_band(band)
	return band_masses[band]

# True once the band's masses exist, so front_band returns at once.
func band_ready(band: int) -> bool:
	_refresh_masses()
	return band_masses.has(band)

# Generates a band over several frames for the streaming world: `owner` is
# the job it pauses under (MountainWorld.build_pause).
func warm_band(band: int, owner: Object) -> void:
	_refresh_masses()
	if band_masses.has(band): return
	await _generate_band(band,owner)

func _layout_signature() -> Vector4i:
	return Vector4i(layout.anchors.size(),layout.finds.size(),layout.obstacles.size(),layout.ledges.size())

# A paused band gives up when a direct query built it meanwhile or new
# gameplay objects reset every band; nothing of it is kept then.
func _band_pause(band: int, owner: Object, signature: Vector4i) -> bool:
	if owner==null: return true
	if not await pause(owner): return false
	return not band_masses.has(band) and _layout_signature()==signature and mass_signature==signature

# Builds the band's masses. With an owner it may pause between pieces; the
# band is published (band_masses, islands, bins) only once complete.
func _generate_band(band: int, owner: Object = null) -> void:
	var signature := mass_signature
	var list: Array = []
	var random := layout.rng(band,947)
	var low := band*BAND
	var high := low+BAND
	var top := layout.summit+1.5 if layout.finite else INF
	var region := region_of(low+12.0)
	var form := region_form(region)
	var kind := int(form.get("kind",0))
	# Trunk: a few large host masses along the route, alternating sides and
	# depths, each fused from a tilted body and its lobes.
	var y := low+random.randf_range(-1.0,1.5)
	var side := -1.0 if random.randf()<.5 else 1.0
	while y<high:
		if not await _band_pause(band,owner,signature): return
		if y>-3.0 and y<top:
			var size := Vector2(random.randf_range(5.5,9.0),random.randf_range(4.6,7.0))
			var center := Vector2(_route_x(y)+side*random.randf_range(.4,2.2),y)
			_host(list,band,"trunk",center,size,random.randf_range(-1.75,-1.0),random)
			side = -side
		y += random.randf_range(4.4,6.0)
	# Landform set pieces of the region, before the blocks that must keep
	# out of an arch opening.
	var piece_y := clampf(float(form.get("y",low+12.0)),low+3.0,high-6.0)
	if piece_y<top-6.0 and piece_y>4.0:
		var flank := float(form.get("side",1))
		if kind==1: _overhang(list,band,piece_y,flank,random)
		elif kind in [3,5]: _arch(list,band,piece_y,flank,random)
	# Body: larger, deeper blocks behind the trunk give the mountain depth.
	y = low+random.randf_range(0,3.0)
	while y<high:
		if not await _band_pause(band,owner,signature): return
		if y>-3.0 and y<top-1.0:
			for flank in [-1.0,1.0]:
				if random.randf()<.35:
					var center := Vector2(_route_x(y)+flank*random.randf_range(3.8,5.2),y+random.randf_range(-1.0,1.0))
					var size := Vector2(random.randf_range(6.5,9.0),random.randf_range(5.0,7.0))
					var box := Rect2(center-size*.6,size*1.2)
					var blocked := false
					for opening in arch_openings: blocked = blocked or opening.grow(.5).intersects(box)
					if not blocked: _host(list,band,"body",center,size,random.randf_range(-3.3,-3.0),random,-4.6)
		y += random.randf_range(6.0,8.0)
	# Fill: the route corridor stays on stone.
	for step in range(int(BAND*2)):
		var at := low+step*.5
		if at<-2.0 or at>top-1.0: continue
		if step%4==0 and not await _band_pause(band,owner,signature): return
		for offset in [-ROUTE_CLEAR+.1,0.0,ROUTE_CLEAR-.1]:
			var point := Vector2(_route_x(at)+offset,at)
			if _covering(list,point,.05)!=null: continue
			for attempt in range(3):
				var mass := _block(list,band,"fill","slab",point+Vector2(-offset*.35,.6),Vector2(random.randf_range(3.2,4.0),random.randf_range(2.6,3.2))*(1.0+attempt*.2),random.randf_range(-2.1,-1.7),random)
				if mass!=null and mass.inside(point)>=.05: break
				if mass!=null: list.erase(mass)
	# Seats for every gameplay object, then shelves for ledges.
	for anchor in layout.anchors:
		var p: Vector2 = anchor["pos"]
		# The grip's outcrop drops about a metre below its hitbox (see
		# GripVisualSpec): the stone behind it reaches that far down too.
		var size: Vector2 = anchor["dimensions"]
		if p.y>=low and p.y<high:
			if not await _band_pause(band,owner,signature): return
			_seat(list,band,p-Vector2(0,.5),Vector2(size.x*.68,size.y*.5+.5),random)
	for obstacle in layout.obstacles:
		var p: Vector2 = obstacle["pos"]
		if p.y>=low and p.y<high: _seat(list,band,p,obstacle["dimensions"]*.5+Vector2(.3,.3),random)
	for ledge in layout.ledges:
		var top_y := float(ledge["top"])
		if top_y<low or top_y>=high: continue
		# A sand bridge is its own slab (HazardVisuals): it must be able to fall.
		if ledge.has("bridge"): continue
		var middle := Vector2((float(ledge["left"])+float(ledge["right"]))*.5,top_y-.7)
		# The platform itself is timber (build_ledge); the stone behind it
		# carries its braces.
		_seat(list,band,middle,Vector2((float(ledge["right"])-float(ledge["left"]))*.4,.5),random)
	for find in layout.finds:
		var p: Vector2 = find["pos"]
		if p.y<low or p.y>=high: continue
		if not await _band_pause(band,owner,signature): return
		# A find lies on the host face itself: no shelf or ledge of its own,
		# so loot never reads as a platform of the route.
		_seat(list,band,p,Vector2(.6,.6),random)
	# Side islands: separate clusters off the route, sky between them.
	var islands: Array = []
	for cluster in range(1 if kind in [2,3] else 2):
		if not await _band_pause(band,owner,signature): return
		var cy := low+random.randf_range(3.0,20.0)
		var flank := -1.0 if (cluster==0)==(random.randf()<.5) else 1.0
		if cy<3.0 or cy>top-3.0: continue
		var cx := _route_x(cy)+flank*random.randf_range(7.5,10.5)
		var members: Array = []
		var core := _block(list,band,"island","island",Vector2(cx,cy),Vector2(random.randf_range(4.2,6.2),random.randf_range(3.4,5.0)),random.randf_range(-2.4,-1.6),random,-3.4,null,.4)
		if core!=null:
			members.append(core)
			for member in range(random.randi_range(1,2)):
				var pillar := random.randf()<.4
				var size := Vector2(random.randf_range(1.8,2.6),random.randf_range(3.8,5.4)) if pillar else Vector2(random.randf_range(2.4,3.6),random.randf_range(2.0,3.0))
				var center := Vector2(cx,cy)+Vector2(random.randf_range(-2.6,2.6),random.randf_range(-2.0,2.2))
				var mass := _block(list,band,"island","pillar" if pillar else "island",center,size,core.z_rim+random.randf_range(-.3,.25),random,-3.4,core,.3)
				if mass!=null: members.append(mass)
		islands.append(members)
	# Rubble at the feet of big blocks, away from every gameplay object.
	var bases := list.duplicate()
	for count in range(random.randi_range(2,4) if not bases.is_empty() else 0):
		var parent: RockMassSpec = bases[random.randi_range(0,bases.size()-1)]
		if parent.landform in ["shelf","rubble"]: continue
		var foot := Vector2(INF,INF)
		for point in parent.outer_contour:
			if point.y<foot.y: foot = point
		var at := foot+Vector2(random.randf_range(-.6,.6),random.randf_range(.1,.5))
		if at.y<low or at.y>=high or _objects_near(at,1.2): continue
		_block(list,band,"rubble","rubble",at,Vector2(random.randf_range(.9,1.6),random.randf_range(.7,1.2)),_front_z(list,at,-1.4)-.15,random)
	if not await _band_pause(band,owner,signature): return
	band_masses[band] = list
	band_islands[band] = islands
	for mass in list: _register(mass)
	_link_neighbors(list)

func _overhang(list: Array, band: int, y: float, flank: float, random: RandomNumberGenerator) -> void:
	# A block thrown out of the face over open space: its broad underside and
	# its shadow fall on the masses below.
	var center := Vector2(_route_x(y)+flank*random.randf_range(3.8,5.0),y)
	if _objects_near(center,1.6): center.x += flank*1.6
	if _objects_near(center,1.6): return
	var contour := RockMassSpec.block_contour(center,Vector2(random.randf_range(5.0,6.2),random.randf_range(2.4,3.0)),random,random.randf_range(-.1,.1),.3)
	_add_mass(list,band,"overhang","overhang",contour,random.randf_range(-.7,-.3),random)

func _arch(list: Array, band: int, y: float, flank: float, random: RandomNumberGenerator) -> void:
	# Two pillars and a lintel round an opening onto the sky. The pillars'
	# inner faces and the lintel's underside are the arch's inner surface.
	# The arch looks for a free spot beside the route: both sides, several
	# distances and heights, never over a gameplay object.
	var gap := random.randf_range(1.8,2.6)
	var pillar := random.randf_range(2.1,2.7)
	var height := random.randf_range(4.0,5.0)
	var low := band*BAND
	for attempt in range(12):
		var side := flank if attempt%2==0 else -flank
		var at_y := clampf(y+random.randf_range(-6.0,6.0) if attempt>0 else y,low+1.0,low+BAND-height-2.0)
		# Close enough that the inner pillar leans on the body of the mountain.
		var x := _route_x(at_y)+side*random.randf_range(5.6,7.6)
		var span := Rect2(x-gap*.5-pillar,at_y-2.0,gap+pillar*2.0,height+4.1)
		var free := true
		for probe_x in range(5):
			for probe_y in range(5):
				var probe := span.position+span.size*Vector2(probe_x/4.0,probe_y/4.0)
				if _objects_near(probe,.3): free = false
		if not free: continue
		# A window through the rock: a sill below, two pillars, a lintel
		# above; every face turned to the opening is the arch's inner wall.
		var z := random.randf_range(-1.4,-1.0)
		var outer := gap+pillar*2.0
		# All four pieces are one body (one group): no crease between them.
		var sill := RockMassSpec.block_contour(Vector2(x,at_y-.9),Vector2(outer+.8,2.2),random,random.randf_range(-.05,.05),.25)
		var body := _add_mass(list,band,"arch","arch",sill,z+.1,random,-3.6,Vector2.UP)
		for pillar_side in [-1.0,1.0]:
			var center := Vector2(x+pillar_side*(gap*.5+pillar*.5),at_y+height*.5)
			var contour := RockMassSpec.block_contour(center,Vector2(pillar,height+1.0),random,0.0,.2)
			_add_mass(list,band,"arch","arch",contour,z,random,-3.6,Vector2(-pillar_side,0),Vector3.ZERO,body)
		var lintel := RockMassSpec.block_contour(Vector2(x,at_y+height+.9),Vector2(outer+.6,2.4),random,random.randf_range(-.06,.06),.25)
		_add_mass(list,band,"arch","arch",lintel,z+.15,random,-3.6,Vector2.DOWN,Vector3.ZERO,body)
		arch_openings.append(Rect2(x-gap*.5,at_y,gap,height))
		return

func _register(mass: RockMassSpec) -> void:
	masses_by_id[mass.id] = mass
	for bin in range(int(floor(mass.bounds.position.y/BIN)),int(floor(mass.bounds.end.y/BIN))+1):
		if not mass_bins.has(bin): mass_bins[bin] = []
		mass_bins[bin].append(mass)

func _link_neighbors(list: Array) -> void:
	for mass in list:
		for other in list:
			if other!=mass and mass.bounds.grow(.2).intersects(other.bounds): mass.neighbors.append(other.id)

func _masses_near(point: Vector2) -> Array:
	var band := int(floor(point.y/BAND))
	for neighbour in [band-1,band,band+1]: front_band(neighbour)
	return mass_bins.get(int(floor(point.y/BIN)),[])

# --- Surface query ----------------------------------------------------------------

func surface_query(point: Vector2) -> RockSurfaceHit:
	# The frontmost mass at a gameplay point and the face seen there.
	if query_cache.has(point): return query_cache[point]
	var hit := RockSurfaceHit.new()
	var best := -INF
	for mass in _masses_near(point):
		var surface: Dictionary = mass.surface_at(point)
		if surface.is_empty() or float(surface["z"])<=best: continue
		best = surface["z"]
		hit.mass_id = mass.id
		hit.mass = mass
		hit.position = Vector3(point.x,point.y,surface["z"])
		hit.normal = surface["normal"]
		hit.surface_class = surface["class"]
		hit.depth = mass.inside(point)
		hit.material_profile = mass.material_profile
	if hit.valid():
		var along := Vector3.RIGHT-hit.normal*hit.normal.x
		hit.tangent = along.normalized() if along.length_squared()>.0001 else Vector3.RIGHT
		hit.exposure = 1.0 if _open_above(point,hit.position.z) else 0.0
	query_cache[point] = hit
	return hit

func _open_above(point: Vector2, z: float) -> bool:
	var probe := point+Vector2(0,1.2)
	for mass in _masses_near(probe):
		var surface: Dictionary = mass.surface_at(probe)
		if not surface.is_empty() and float(surface["z"])>z+.3: return false
	return true

func stone_field(point: Vector2) -> float:
	# Signed distance to the nearest silhouette: >= 0 is stone.
	var best := -8.0
	for mass in _masses_near(point): best = maxf(best,mass.inside(point))
	return best

func wall_depth(point: Vector2) -> float:
	var hit := surface_query(point)
	return hit.position.z if hit.valid() else -3.0

func vertex(point: Vector2) -> Vector3:
	return Vector3(point.x,point.y,wall_depth(point))

func surface_normal(point: Vector2) -> Vector3:
	var hit := surface_query(point)
	return hit.normal if hit.valid() else Vector3.BACK

func open_at(point: Vector2) -> bool:
	return not surface_query(point).valid()

func support_root_of(object: Dictionary) -> Vector2:
	return massif.support_root(object) if massif!=null and object.has("id") and object.has("pos") else Vector2.INF

func grip_tint() -> float:
	# A grip is a knob of the host rock: the type shows in its tone, strip
	# and details, not as a pale plate on the face.
	return .38

func baked_contact() -> bool:
	# Contact comes from real shadows and a decal that leaves with its object.
	return false

static func grip_clearance(anchor: Dictionary) -> float:
	# Stone reaches past the grip's own polygon on every side.
	return maxf(1.0,float(anchor["dimensions"].x)*.5+.32)

func mount_at(point: Vector2, footprint: Vector2, object: Dictionary = {}, standoff: float = GRIP_STANDOFF) -> SurfaceMount:
	var mount := super.mount_at(point,footprint,object,standoff)
	var hit := surface_query(point)
	mount.host_mass = hit.mass_id
	mount.surface_class = hit.surface_class
	mount.socket_center = hit.position
	mount.socket_normal = hit.normal
	mount.embed_depth = mount.depth
	mount.contact_bounds = Rect2(point-footprint*.5,footprint)
	mount.material_profile = hit.material_profile
	mount.exposure = hit.exposure
	return mount

# Every mass over the area counts with its full front, bevels and dome
# included, not only the face a gameplay point sees.
func _stone_front(area: Rect2) -> float:
	var front := -INF
	for bin in range(int(floor(area.position.y/BIN)),int(floor(area.end.y/BIN))+1):
		_masses_near(Vector2(area.get_center().x,bin*BIN+BIN*.5))
		for mass in mass_bins.get(bin,[]):
			if mass.bounds.intersects(area): front = maxf(front,mass.front_z)
	return front if front>-INF else super._stone_front(area)

func finds_without_pedestal() -> bool:
	return true

# --- Chunk build --------------------------------------------------------------------

func build_chunk(index: int, parent: Node3D) -> void:
	query_cache.clear()
	decor_rects.erase(index)
	await _build_masses(index,parent)
	if not await pause(parent): return
	# Landmarks claim their place first; small decor fits round them.
	await _build_landmarks(index,parent)
	if not await pause(parent): return
	await _build_decor(index,parent)

func _palette(profile: GripBiomeProfile, height: float, mass: RockMassSpec) -> Dictionary:
	var rock: Dictionary = profile.rock_material
	# Each host body has its own shade of the zone's rock.
	var base := zone_color(height)
	var shift := (mass.tone-.5)*.14
	base = base.lightened(shift) if shift>0 else base.darkened(-shift)
	var facets: Array = []
	for color in rock["facet_palette"]: facets.append(base.lerp(color,.5))
	var under: Color = base.lerp(rock["underside_tint"],.42).darkened(.16)
	return {"base":base,"facets":facets,
		"top":base.lerp(rock["top_light_tint"],.26).lightened(.06),
		"side":base.lerp(rock["underside_tint"],.12).darkened(.04),
		"under":under,
		"inner":under.darkened(.12)}

func _cavity(mass: RockMassSpec, point: Vector3) -> float:
	# Soft shade where another mass stands in front close by: creases, the
	# foot of a block on the one below, the back of an arch opening.
	var strength := float(profile_at(point.y).rock_material["cavity_strength"])
	var shade := 0.0
	var at := Vector2(point.x,point.y)
	for other in mass_bins.get(int(floor(point.y/BIN)),[]):
		if other==mass or other.group==mass.group or other.front_z<point.z+.15: continue
		var distance: float = other.inside(at)
		if distance>-.9 and distance<.3: shade = maxf(shade,1.0-clampf(-distance/.9,0,1))
	if mass.landform=="arch" and mass.inner_edges.size()>0: shade = maxf(shade,.25)
	return shade*strength

func _build_masses(index: int, parent: Node3D) -> void:
	# Neighbouring bands first: their masses shade this band's creases.
	front_band(index-1)
	front_band(index+1)
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	var emitted := 0
	var walls := quality!="battery"
	for mass in front_band(index):
		if not await pause(parent): return
		var center: Vector2 = mass.centroid()
		emitted += RockMassBuilder.emit(surface,mass,_palette(profile_at(center.y),center.y,mass),_cavity,walls)
	if emitted==0: return
	var instance := MeshInstance3D.new()
	instance.name = "Скальный массив_%d" % index
	instance.mesh = surface.commit()
	instance.material_override = rock_material_at(index*BAND+BAND*.5)
	# Masses shade each other: overhangs, lintels and stacked blocks cast on
	# the stone behind them. Battery has no shadow map at all.
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if quality!="battery" else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(instance)

# --- Ledges -------------------------------------------------------------------------

func build_ledge(object: Dictionary, parent: Node3D) -> void:
	# A timber platform model standing on the face: the deck's back edge is
	# the walking line (_place_platform).
	if is_instance_valid(object.get("visual")):
		return
	var left: float = object["left"]
	var right: float = object["right"]
	var top: float = object["top"]
	var center := Vector2((left+right)*.5,top)
	var mount := mount_at(center-Vector2(0,.2),Vector2(right-left,.4),{},.02)
	mount.layout_point = center
	var holder := Node3D.new()
	holder.name = "Площадка отдыха_%d" % int(roundf(top*10))
	parent.add_child(holder)
	holder.position = mount.holder_position()
	object["visual"] = holder
	object["mount"] = mount
	_place_platform(holder,object,mount)

# --- Decor --------------------------------------------------------------------------

func _decor_blocked(point: Vector2, reach: float = 0.0) -> bool:
	for anchor in layout.nearby_ids(point.y-2.0,point.y+2.0):
		var grip: Dictionary = layout.anchors[anchor]
		var grip_size: Vector2 = grip.get("dimensions",Vector2(1.6,.65))
		# Keep a clear halo around the whole visible outcrop, not just its
		# gameplay centre. This stops plants, roots and props reading as extra
		# hookable platforms.
		var grip_clearance := maxf(2.0,maxf(grip_size.x,grip_size.y)*.5+.82)
		if grip["pos"].distance_to(point)<grip_clearance+reach: return true
	for obstacle in layout.obstacles:
		if obstacle["pos"].distance_to(point)<1.15+maxf(obstacle["dimensions"].x,obstacle["dimensions"].y)*.5+reach: return true
	for find in layout.finds:
		if find["pos"].distance_to(point)<.8+reach: return true
	for ledge in layout.ledges:
		# The platform's supports reach well under its deck.
		var below := float(ledge["top"])-point.y
		if point.x>float(ledge["left"])-.5 and point.x<float(ledge["right"])+.5 and below>-.9-reach and below<1.6+reach: return true
	return false

func _decor_route_clear(point: Vector2, radius: float) -> bool:
	# Keep the line of throws and swings readable: no tall decor on the spine.
	return absf(point.x-_route_x(point.y))>radius

func _on_face(mass: RockMassSpec, point: Vector2) -> RockSurfaceHit:
	var hit := surface_query(point)
	return hit if hit.valid() and hit.mass_id==mass.id else null

# Pieces already standing in a band (landmarks first, then decor), so no
# two overlap.
var decor_rects: Dictionary = {}

func _taken(index: int, rect: Rect2) -> bool:
	for band in [index-1,index,index+1]:
		for other: Rect2 in decor_rects.get(band,[]):
			if other.intersects(rect): return true
	return false

func _take(index: int, rect: Rect2) -> void:
	if not decor_rects.has(index): decor_rects[index] = []
	decor_rects[index].append(rect)

# A standing piece needs stone under both sides of its foot, a hanging one
# stone where it hangs from, a climbing one a wall behind it; none may cover
# a grip, find, hazard or rest platform anywhere along its height.
func _decor_fits(rect: Rect2, hanging: bool, climbing: bool = false) -> bool:
	if hanging:
		if stone_field(Vector2(rect.get_center().x,rect.end.y+.1))<0: return false
	else:
		for share in [.2,.5,.8]:
			if stone_field(Vector2(rect.position.x+rect.size.x*share,rect.position.y-.15))<0: return false
	# A climbing vine needs a wall to climb: visible stone behind most of its
	# height, never a stalk standing up into the sky.
	if climbing:
		for share in [.3,.55,.8]:
			if open_at(Vector2(rect.get_center().x,rect.position.y+rect.size.y*share)): return false
	for share in [.1,.5,.9]:
		if _decor_blocked(Vector2(rect.get_center().x,rect.position.y+rect.size.y*share),rect.size.x*.5): return false
	return true

# The lowest point of visible stone straight above `point` (within a metre),
# a few centimetres inside it; INF where there is none.
func _underside_above(point: Vector2) -> Vector2:
	for step in range(34):
		var probe := point+Vector2(0,step*.03)
		if not open_at(probe): return probe+Vector2(0,.06)
	return Vector2.INF

# The sprite a decor spot gets in the place's climate.
func _decor_entry(kind: String, profile: GripBiomeProfile, random: RandomNumberGenerator) -> Array:
	match kind:
		"grass":
			# Where nothing green grows, the tops carry stones instead.
			if not bool(profile.vegetation_set["grass"]) and FloraModels.climate(profile)!="cold": return FloraModels.pick_stone(profile,random)
			return FloraModels.pick_top(profile,random)
		"crystal": return FloraModels.pick_crystal(profile,random)
		"climb": return FloraModels.pick_climber(profile,random)
		"hanging": return FloraModels.pick_hanging(profile,random)
	return FloraModels.pick_stone(profile,random)

func _build_decor(index: int, parent: Node3D) -> void:
	# Decor stands on the lit tops of the masses - plants, stones, now and then
	# a crystal, vines climbing the wall above a top - and hangs from the
	# undersides over open space: ivy, seed pods, icicles. Every piece is a painted sprite (FloraModels) placed so it rests
	# on stone, covers no gameplay object and overlaps no other piece; it sits
	# in front of the stone it covers. Everything is drawn, nothing collides.
	var budget := 40 if quality=="high" else 28 if quality=="balanced" else 10
	var crystal_budget := 3 if quality=="high" else 2 if quality=="balanced" else 1
	# Vines are a green place's: a desert keeps a few dry ones, the snow
	# hangs icicles rather than creepers.
	var climate := FloraModels.climate(profile_at(index*BAND+BAND*.5))
	var vines: float = {"green":1.0,"dry":.4,"cold":.6}[climate]
	var hanging_budget := roundi((6 if quality=="high" else 4 if quality=="balanced" else 1)*(1.0 if climate=="cold" else vines))
	var climb_budget := roundi((5 if quality=="high" else 4 if quality=="balanced" else 1)*vines)
	var detail := quality!="battery"
	var random := layout.rng(index,902)
	var candidates: Array = []
	for mass in front_band(index):
		if mass.role in ["fill","body"]: continue
		if not await pause(parent): return
		var count: int = mass.outer_contour.size()
		for i in range(count):
			var j := (i+1)%count
			var span: float = mass.outer_contour[i].distance_to(mass.outer_contour[j])
			# Longer edges offer a few spots along them.
			var spots := clampi(int(span/1.2),1,3)
			for spot in range(spots):
				var t := (spot+random.randf_range(.25,.75))/spots
				var rim: Vector2 = mass.outer_contour[i].lerp(mass.outer_contour[j],t)
				var ring: Vector2 = mass.inner_contour[i].lerp(mass.inner_contour[j],t)
				if mass.top_edges.has(i):
					var roll := random.randf()
					candidates.append([mass,rim.lerp(ring,.4),"grass" if roll<.6 else "pebbles" if roll<.85 else "crystal",rim,span/spots])
				elif mass.bottom_edges.has(i) and mass.role!="shelf":
					# Over open space an underside carries hanging vines; where the
					# mass rests on another, a climbing vine roots in the seam and
					# goes up its face.
					var below := open_at(rim+(rim-ring).normalized()*.4)
					candidates.append([mass,rim.lerp(ring,.1),"hanging" if below else "climb",rim,span/spots,ring])
	for i in range(candidates.size()-1,0,-1):
		var j := random.randi_range(0,i)
		var swap = candidates[i]
		candidates[i] = candidates[j]
		candidates[j] = swap
	var placed := 0
	var crystals := 0
	var hanging := 0
	var climbing := 0
	var clearance := {"grass":.9,"crystal":2.0,"hanging":1.6,"climb":1.6}
	for candidate in candidates:
		if placed>=budget: break
		if not await pause(parent): return
		var mass: RockMassSpec = candidate[0]
		var point: Vector2 = candidate[1]
		var kind: String = candidate[2]
		var rim: Vector2 = candidate[3]
		var hit := _on_face(mass,point)
		if hit==null: continue
		var outward := (rim-point).normalized()
		if kind!="climb" and not open_at(rim+outward*.4): continue
		if kind=="crystal" and crystals>=crystal_budget: continue
		if kind=="hanging" and hanging>=hanging_budget: continue
		if kind=="climb" and climbing>=climb_budget: continue
		if not _decor_route_clear(point,float(clearance.get(kind,.6))): continue
		var profile := profile_at(point.y)
		# On the expeditions some tops carry the act's own small props.
		var prop := ""
		if kind in ["grass","pebbles"] and layout is ExpeditionLayout and random.randf()<.42:
			var expedition := layout as ExpeditionLayout
			var props: Array = expedition.span(expedition.act_index_at(point.y))["def"].get("props",[])
			if not props.is_empty(): prop = str(props[random.randi_range(0,props.size()-1)])
		var entry: Array = []
		var size := Vector2(.9,.9)
		var scale := 1.0
		if prop.is_empty():
			entry = _decor_entry(kind,profile,random)
			if entry.is_empty(): continue
			# Sizes come from the catalogue; a tuft on a short edge stays a
			# little smaller.
			scale = clampf(float(candidate[4])/1.6,.85,1.0) if kind=="grass" else 1.0
			size = FloraModels.size_of(entry,scale)
		var hangs := not entry.is_empty() and FloraModels.hangs(entry)
		var anchor := point
		if kind=="climb": anchor = (candidate[5] as Vector2)+Vector2(0,-.04)
		if hangs:
			# The underside slopes back from the front face to the rim and faces
			# away from the camera: the visible edge is the front face's, so the
			# piece hangs from there, tucked a little into it.
			anchor = (candidate[5] as Vector2)+Vector2(0,.05) if candidate.size()>5 else _underside_above(rim)
			if not anchor.is_finite(): continue
		var rect := Rect2(anchor.x-size.x*.5,anchor.y-size.y if hangs else anchor.y,size.x,size.y)
		var climbs := not entry.is_empty() and FloraModels.climbs(entry)
		if _taken(index,rect.grow(.06)) or not _decor_fits(rect,hangs,climbs): continue
		if kind=="crystal": crystals += 1
		if kind=="hanging": hanging += 1
		if kind=="climb": climbing += 1
		var holder := Node3D.new()
		holder.name = "Декор_%d" % placed
		parent.add_child(holder)
		# In front of every stone the piece covers, never inside one.
		holder.position = Vector3(anchor.x,anchor.y,maxf(hit.position.z,_front_over(rect))+.03)
		if not prop.is_empty(): ActProps.build(self,prop,holder,random,profile,detail)
		else: FloraModels.plant(holder,entry,quality!="battery",scale)
		_take(index,rect)
		placed += 1

func _build_plant(holder: Node3D, random: RandomNumberGenerator, rim: float, profile: GripBiomeProfile, _detail: bool) -> void:
	# The plant a place grows on a lit top: grass and bushes, desert plants
	# and cacti, or snow plants (FloraModels).
	FloraModels.plant(holder,FloraModels.pick_top(profile,random),quality!="battery",clampf(rim,.85,1.1))

# No stone stands in front of a landmark anywhere over its height: a tree
# never grows behind a boulder that hides its crown. Stone behind it is
# fine; so is the top it stands on.
func _landmark_unhidden(point: Vector2, family: String, z: float) -> bool:
	var rect := _landmark_rect(point,family)
	for row in [.25,.5,.75,.95]:
		for column in [.2,.5,.8]:
			var probe := rect.position+rect.size*Vector2(column,row)
			if not open_at(probe) and wall_depth(probe)>z-.05: return false
	return true

# The space a landmark takes on the face, for the decor round it.
func _landmark_rect(point: Vector2, family: String) -> Rect2:
	var height := LandmarkVisuals.family_height(family)
	return Rect2(point.x-height*.45,point.y-.1,height*.9,height+.1)

func _landmark_clear(point: Vector2, height: float) -> bool:
	# The whole set piece, not only its foot, keeps clear of the route and of
	# every grip, find, obstacle and ledge.
	if not _decor_route_clear(point,3.2): return false
	for step in range(4):
		var probe := point+Vector2(0,height*step/3.0)
		if _decor_blocked(probe,1.0) or not _decor_route_clear(probe,3.0): return false
	return true

# An act landmark marks a place on the route, so it may stand nearer to it
# than an island set piece, still clear of every gameplay object.
func _mark_clear(point: Vector2, height: float) -> bool:
	for step in range(4):
		var probe := point+Vector2(0,height*step/3.0)
		if _decor_blocked(probe,.45) or not _decor_route_clear(probe,2.0): return false
	return true

func _build_landmarks(index: int, parent: Node3D) -> void:
	# One large themed piece standing on the top face of a side island.
	front_band(index)
	var budget := 1 if quality=="battery" else 2
	var random := layout.rng(index,977)
	var placed := 0
	for members in band_islands.get(index,[]):
		if placed>=budget: break
		if not await pause(parent): return
		var best: RockMassSpec = null
		for mass in members:
			if best==null or mass.bounds.end.y>best.bounds.end.y: best = mass
		if best==null or best.top_edges.is_empty(): continue
		# A round island has several short top edges: stand on the crown.
		var edge: int = best.top_edges[0]
		var count: int = best.outer_contour.size()
		for candidate in best.top_edges:
			if best.outer_contour[candidate].y+best.outer_contour[(candidate+1)%count].y>best.outer_contour[edge].y+best.outer_contour[(edge+1)%count].y: edge = candidate
		var rim: Vector2 = best.outer_contour[edge].lerp(best.outer_contour[(edge+1)%best.outer_contour.size()],.5)
		var ring: Vector2 = best.inner_contour[edge].lerp(best.inner_contour[(edge+1)%best.inner_contour.size()],.5)
		var point := rim.lerp(ring,.5)
		var hit := _on_face(best,point)
		if hit==null: continue
		var family := landmark_family(point,random)
		if not _landmark_clear(point,LandmarkVisuals.family_height(family)): continue
		if not _landmark_unhidden(point,family,hit.position.z+.05): continue
		var holder := Node3D.new()
		holder.name = "Крупный элемент_%d" % placed
		parent.add_child(holder)
		holder.position = hit.position+Vector3(0,0,.05)
		LandmarkVisuals.build_family(self,family,holder,random,quality!="battery")
		_take(index,_landmark_rect(point,family))
		placed += 1
	# Act landmarks (v14) mark a fork or the way into the next act; they take
	# the nearest clear spot of the face around their planned point.
	for mark in layout.landmarks:
		var at: Vector2 = mark["pos"]
		if int(floor(at.y/BAND))!=index: continue
		var family := str(mark["family"])
		var outward := signf(at.x-_route_x(at.y)) if absf(at.x-_route_x(at.y))>.3 else 1.0
		var offsets: Array = []
		for dy in [0.0,1.5,-1.5,3.0]:
			for dx in [0.0,1.5,-1.5,3.0,-3.0,4.5,-4.5,6.0]: offsets.append(Vector2(dx,dy))
		offsets.sort_custom(func(a: Vector2, b: Vector2) -> bool: return a.length_squared()<b.length_squared())
		for offset in offsets:
			var point: Vector2 = at+Vector2(offset.x*outward,offset.y)
			var hit := surface_query(point)
			if not hit.valid() or not _mark_clear(point,LandmarkVisuals.family_height(family)): continue
			if not _landmark_unhidden(point,family,hit.position.z+.05): continue
			var holder := Node3D.new()
			holder.name = "Ориентир акта_%s" % family
			parent.add_child(holder)
			holder.position = hit.position+Vector3(0,0,.05)
			LandmarkVisuals.build_family(self,family,holder,layout.rng(int(roundf(at.y*10)),978),quality!="battery")
			_take(index,_landmark_rect(point,family))
			mark["built_at"] = point
			break

# --- Distant ranges -----------------------------------------------------------------

func build_far_band(far: int, band: int, parent: Node3D) -> void:
	# Mountain ranges in the haze, in their own parallax space (see
	# MountainWorld): peaks with a lit and a shaded flank, a snow crown where
	# the profile has snow, and a line of pines in front on the near layer.
	var random := layout.rng(band*7+far,951)
	var profile := profile_at(band*BAND*(1.0-float(FAR_LAYERS[far-1]["follow"]))+12.0)
	var rock: Color = profile.rock_material["base_color"]
	# Blue ranges of the reference: the near layer a deep slate blue, the
	# far one paler in the haze, both clearly bluer than the climbing rock.
	var tone := rock.lerp(Color("4f6f92"),.6 if far==1 else .7)
	var snow := float(profile.weathering_rules["snow"])>.1 or profile.id=="sky"
	var points := PackedVector3Array()
	var colors := PackedColorArray()
	# Narrow, steep peaks, several per band, so an opening shows a range of
	# summits instead of one pale slope filling it.
	var count := random.randi_range(5,8)
	for peak in range(count):
		var x := lerpf(-46.0,46.0,(peak+random.randf_range(.15,.85))/count)
		var base := band*BAND+random.randf_range(-8.0,10.0)
		var width := random.randf_range(6.5,12.0)*(1.0+.3*(far-1))
		var height := random.randf_range(9.0,15.0)*(1.0+.35*(far-1))
		var z := -random.randf_range(0,3.0)-peak*.15
		var apex := Vector3(x+random.randf_range(-2,2),base+height,z+2.0)
		var left := Vector3(x-width*.5,base,z)
		var right := Vector3(x+width*.5,base,z)
		var left_shoulder := Vector3(x-width*random.randf_range(.22,.3),base+height*random.randf_range(.5,.62),z+1.0)
		var right_shoulder := Vector3(x+width*random.randf_range(.18,.28),base+height*random.randf_range(.45,.6),z+1.0)
		var foot := Vector3(x+random.randf_range(-1.5,1.5),base,z+1.4)
		var crease := Vector3(apex.x+random.randf_range(-1,1),base+height*.45,z+1.8)
		for triangle in [[left,left_shoulder,foot],[left_shoulder,crease,foot],[left_shoulder,apex,crease],[foot,crease,right_shoulder],[crease,apex,right_shoulder],[foot,right_shoulder,right]]:
			var lit: bool = (triangle[0] as Vector3).x+(triangle[1] as Vector3).x+(triangle[2] as Vector3).x<apex.x*3.0
			var color := tone.lightened(.08) if lit else tone.darkened(.1)
			if snow and minf((triangle[0] as Vector3).y,minf((triangle[1] as Vector3).y,(triangle[2] as Vector3).y))>base+height*.44: color = Color("e8eef2") if lit else Color("bccbd8")
			points.append_array(PackedVector3Array(triangle))
			colors.append(color)
	if far==1 and bool(profile.vegetation_set["grass"]) and not bool(profile.vegetation_set.get("dry",false)):
		var pine := Color("2f4a3c").lerp(tone,.25)
		for tree in range(random.randi_range(6,11)):
			var foot := Vector3(random.randf_range(-40,40),band*BAND+random.randf_range(0,BAND),2.5)
			var height := random.randf_range(2.2,3.6)
			for tier in range(3):
				var y := foot.y+height*tier*.28
				var half := height*(.34-tier*.08)
				points.append_array(PackedVector3Array([Vector3(foot.x-half,y,foot.z),Vector3(foot.x,y+height*.45,foot.z+.2),Vector3(foot.x+half,y,foot.z)]))
				colors.append(pine.lightened(tier*.03))
	if points.is_empty(): return
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in range(0,points.size(),3):
		for k in range(3):
			surface.set_color(colors[i/3])
			surface.add_vertex(points[i+k])
	var instance := MeshInstance3D.new()
	instance.name = "Дальние скалы_%d_%d" % [far,band]
	instance.mesh = surface.commit()
	instance.material_override = far_materials[far-1]
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(instance)
