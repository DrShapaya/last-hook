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
var seen_rock: RockSurface
var seen_rock_asked := false
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
	if rock.has("strata_fine"):
		material.set_shader_parameter("strata_contrast",float(rock["strata_contrast"]))
		material.set_shader_parameter("strata_fine",float(rock["strata_fine"]))
	if rock.has("grain_strength"):
		material.set_shader_parameter("grain_texture",load("res://assets/art/sandstone_grain.png"))
		material.set_shader_parameter("grain_strength",float(rock["grain_strength"]))

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
	# A level drawn as masks plans its relief itself (MaskLayout.relief): its
	# masses fill the painted silhouette and replace the route trunk, set
	# pieces, body, islands and rubble below.
	var planned := layout is MaskLayout and not (layout as MaskLayout).relief.is_empty()
	var planned_islands: Array = []
	if planned:
		for entry in (layout as MaskLayout).relief:
			var at := Vector2(float(entry[0]),float(entry[1]))
			if at.y<low or at.y>=high or at.y>top: continue
			if not await _band_pause(band,owner,signature): return
			var radius := float(entry[2])
			var depth := float(entry[3])
			# Corners of a full boulder reach about 1.3 half-sizes out: this keeps
			# them within the planned circle.
			var size := Vector2(radius*1.55,radius*1.4)
			if str(entry[4])=="bridge":
				# A flat stone of a loop's bridge: wide, low, a little forward,
				# its top level (MaskLayout._bridge_stones).
				size = Vector2(radius*1.55,radius*1.55/MaskLayout.BRIDGE_SQUASH)
				_block(list,band,"bridge","slab",at,size,random.randf_range(-.75,-.55),random,-3.4,null,.04)
				continue
			# Single boulders that keep inside their planned circle: a host's
			# lobes would grow over the painted sky windows.
			var role := "body" if str(entry[4])=="body" else "trunk" if radius>=2.4 else "island"
			var z_rim := lerpf(-2.8,-1.2,depth) if radius>=2.4 else lerpf(-2.2,-1.0,depth)
			# Summer boulders stand out by different amounts, so the joints
			# between them fall into shadow (summerClose.png); the large ones
			# lead, the small ones in the joints sit back.
			if _summer_boulders(): z_rim += random.randf_range(-.4,.2)+clampf((radius-2.0)*.12,-.25,.3)
			var mass := _block(list,band,role,"island",at,size,z_rim,random,-4.4 if radius>=2.4 else -3.4)
			if mass!=null and role=="island": planned_islands.append([mass])
	if not planned:
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
	# Fill: the route corridor stays on stone. A planned relief already
	# covers its whole silhouette; slabs here would spill over its edges.
	for step in range(int(BAND*2) if not planned else 0):
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
	var islands: Array = planned_islands
	if not planned:
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
	_refresh_masses()
	if not (band_masses.has(band) and band_masses.has(band-1) and band_masses.has(band+1)):
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
		hit.exposure = 1.0 if _open_above(point,hit.position.z) else 0.0
		var rock := _seen_rock()
		if rock!=null:
			hit.position.z = rock.height(point)
			hit.normal = rock.normal_at(point)
		var along := Vector3.RIGHT-hit.normal*hit.normal.x
		hit.tangent = along.normalized() if along.length_squared()>.0001 else Vector3.RIGHT
	query_cache[point] = hit
	return hit

# The location's own rock, where objects stand on what the player sees and the
# masses only say where stone is.
func _seen_rock() -> RockSurface:
	if not seen_rock_asked and layout is MaskLayout and not (layout as MaskLayout).rock_grid.is_empty():
		seen_rock_asked = true
		var rock := RockSurface.make(layout as MaskLayout)
		if rock!=null and rock.holds_objects(): seen_rock = rock
	return seen_rock

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
	if hit.valid(): return hit.position.z
	var rock := _seen_rock()
	return rock.height(point) if rock!=null else -3.0

func vertex(point: Vector2) -> Vector3:
	return Vector3(point.x,point.y,wall_depth(point))

func surface_normal(point: Vector2) -> Vector3:
	var hit := surface_query(point)
	return hit.normal if hit.valid() else Vector3.BACK

func open_at(point: Vector2) -> bool:
	# On a location's own rock the edge the player sees is that rock's.
	var rock := _seen_rock()
	if rock!=null: return rock.distance(point)<=0.0
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
	if _seen_rock()!=null: return super._stone_front(area)
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
	decor_clumps.erase(index)
	decor_kin.erase(index)
	await _build_masses(index,parent)
	if not await pause(parent): return
	# Landmarks claim their place first; small decor fits round them.
	await _build_landmarks(index,parent)
	if not await pause(parent): return
	if layout is MaskLayout and (layout as MaskLayout).rock_form=="winter":
		await _build_crystals(index,parent)
		if not await pause(parent): return
	if layout is MaskLayout and (layout as MaskLayout).rock_form=="desert" and _seats_on_view():
		await _build_desert_life(index,parent)
		if not await pause(parent): return
	await _build_decor(index,parent)
	if layout is MaskLayout and (layout as MaskLayout).rock_form!="boulder":
		if not await pause(parent): return
		await _build_ledge_plants(index,parent)

func _in_cave(point: Vector2, reach: float = 0.0) -> bool:
	if not layout is MaskLayout: return false
	for cave in (layout as MaskLayout).rock_caves:
		if ((point-Vector2(float(cave[0]),float(cave[1])))/(Vector2(float(cave[2]),float(cave[3]))+Vector2(reach,reach))).length()<1.0: return true
	return false

# --- Desert life (docs/DESERT_LEVEL_PLAN.md, stage 4) --------------------------------

# Plants of a desert group, larger than the scattered decor: as tall against
# a ledge as on desertClose.png. The painted atlas variants first, where the
# catalogue has them, the older ones otherwise.
const DESERT_SCALE := {"cactus":1.45,"dry_plant":1.6,"tree_dead":.8,"skull":1.0,"vine_dry":1.4,"stone_desert":.9}
const DESERT_PREFERRED := {"cactus":[6,7,8],"dry_plant":[5,7,8],"vine_dry":[6,7,8]}
# Groups keep this far apart.
const DESERT_GROUP_GAP := 3.5

func _desert_entry(kind: String, random: RandomNumberGenerator, mode: String = "") -> Array:
	var entry := FloraModels.pick(kind,random,mode,DESERT_PREFERRED.get(kind,[]))
	return entry if not entry.is_empty() else FloraModels.pick(kind,random,mode)

# Every open ledge carries a group as on desertClose.png: a tall cactus with a
# smaller one beside it, a flowering bush, now and then a dry shrub or a
# skull; big dry roots hang from the ends of the ledges. They claim their
# places before the scattered decor, which fits round them.
func _build_desert_life(index: int, parent: Node3D) -> void:
	var rock := RockSurface.make(layout as MaskLayout)
	var random := layout.rng(index,931)
	var groups := 0
	var group_budget := 2 if quality=="battery" else 6
	var anchors: Array = []
	# The benches seen on the face: tops of the ledges, inside the outline, in
	# front of the wall over them.
	for spot: Vector3 in rock.perches(index*BAND,(index+1)*BAND,random,group_budget*120):
		if groups>=group_budget: break
		if not await pause(parent): return
		var at := Vector2(spot.x,spot.y)
		if not _on_bench(rock,at): continue
		var far := true
		for other: Vector2 in anchors: far = far and other.distance_to(at)>=DESERT_GROUP_GAP
		if not far: continue
		if await _desert_group(index,parent,rock,at,random,groups)>=2:
			anchors.append(at)
			groups += 1
	if not is_instance_valid(parent): return
	# Roots under each ledge, most of them near its ends, over the air beside it.
	var roots := 0
	var root_budget := 2 if quality=="battery" else 8
	for ledge: Array in (layout as MaskLayout).rock_marks:
		if int(floor(float(ledge[0])/BAND))!=index: continue
		for end: float in [-1.0,1.0,-1.0,1.0]:
			if roots>=root_budget: break
			var entry := _desert_entry("vine_dry",random,"hang")
			if entry.is_empty(): continue
			var scale := float(DESERT_SCALE["vine_dry"])*random.randf_range(.85,1.1)
			var size := FloraModels.size_of(entry,scale)
			for attempt in range(8):
				var rx := float(ledge[3])+end*(float(ledge[2])-random.randf_range(1.0,float(ledge[2])*.8))
				var under := _ceiling_over(rx,float(ledge[0])-5.0,8.0)
				if under==INF: continue
				var seat := _hang_seat(Vector2(rx,under-.3),size)
				if not seat.is_finite(): continue
				var rect := Rect2(seat.x-size.x*.5,seat.y-size.y,size.x,size.y)
				if not _decor_route_clear(seat,1.2) or _taken(index,rect.grow(.2)) or _would_crowd(index,rect.get_center()) or not _decor_fits(rect,true): continue
				_plant_desert(index,parent,"Подвес_корень_%d" % roots,entry,seat,rect,scale,0.0)
				roots += 1
				break

# A point on the top of a ledge seen inside the face: stone that looks up, a
# step in from the outline, out of the caves.
func _on_bench(rock: RockSurface, at: Vector2) -> bool:
	return rock.distance(at)>1.0 and rock.normal_at(at).y>.4 and not _in_cave(at,.4)

# One group on a bench at `at`, a clump as on desertClose.png: how many of
# its pieces found a place. The first piece, the tall cactus, decides whether
# the group stands at all; the rest gather round it, one behind another.
func _desert_group(index: int, parent: Node3D, rock: RockSurface, at: Vector2, random: RandomNumberGenerator, number: int) -> int:
	var side := -1.0 if random.randf()<.5 else 1.0
	var pieces: Array = [["cactus",0.0],["cactus",side*random.randf_range(.7,1.0)],["dry_plant",-side*random.randf_range(.9,1.4)]]
	if random.randf()<.6: pieces.append(["cactus",-side*random.randf_range(1.6,2.1)])
	if random.randf()<.5: pieces.append(["stone_desert",side*random.randf_range(1.6,2.2)])
	var roll := random.randf()
	if roll<.35: pieces.append(["dry_plant_tree",side*random.randf_range(2.6,3.2)])
	elif roll<.55: pieces.append(["skull",-side*random.randf_range(2.4,2.9)])
	var clump := "Растение_группа_%d_%d" % [index,number]
	var placed := 0
	for piece: Array in pieces:
		if not await pause(parent): return placed
		var kind: String = piece[0]
		var entry: Array
		var scale: float
		if kind=="dry_plant_tree":
			# A dry shrub on the bench, or the dead tree where none is painted.
			entry = FloraModels.pick("dry_plant",random,"stand",[6])
			scale = float(DESERT_SCALE["dry_plant"])*1.4
			if entry.is_empty():
				entry = FloraModels.pick("tree_dead",random)
				scale = float(DESERT_SCALE["tree_dead"])
		else:
			entry = _desert_entry(kind,random,"stand")
			scale = float(DESERT_SCALE[kind])*random.randf_range(.85,1.1)
			# The other cacti are smaller than the first.
			if kind=="cactus" and placed>0: scale *= random.randf_range(.55,.75)
		if entry.is_empty():
			if placed==0: return 0
			continue
		var size := FloraModels.size_of(entry,scale)
		var seat := at+Vector2(float(piece[1]),-.05)
		var rect := Rect2(seat.x-size.x*.5,seat.y,size.x,size.y)
		if not _bench_holds(rock,rect) or not _decor_route_clear(seat,1.0+size.x*.3) or _taken_by_others(index,rect.grow(.08),clump) or _would_crowd(index,rect.get_center(),2.6,clump) or not _decor_fits(rect,false):
			if placed==0: return 0
			continue
		# The first piece stands at the back, the later ones in front of it.
		_plant_desert(index,parent,"%s_%d" % [clump,placed],entry,seat,rect,scale,placed*.03,clump)
		placed += 1
	return placed

# A piece stands on the bench: its foot on the same top, and nothing over
# it stands out of the face further than the bench it grows from, so no
# ledge above cuts across it.
func _bench_holds(rock: RockSurface, rect: Rect2) -> bool:
	var foot := rock.height(Vector2(rect.get_center().x,rect.position.y))
	for share in [.15,.5,.85]:
		if not _on_bench(rock,Vector2(rect.position.x+rect.size.x*share,rect.position.y+.05)): return false
	for row in [.35,.65,1.0]:
		for column in [.2,.5,.8]:
			if rock.height(rect.position+rect.size*Vector2(column,row))>foot+.4: return false
	return true

# Whether a piece would overlap one that is not of its own clump.
func _taken_by_others(index: int, rect: Rect2, clump: String) -> bool:
	for band in [index-1,index,index+1]:
		var rects: Array = decor_rects.get(band,[])
		var owners: Array = decor_clumps.get(band,[])
		for k in range(rects.size()):
			if k<owners.size() and owners[k]==clump: continue
			if (rects[k] as Rect2).intersects(rect): return true
	return false

func _plant_desert(index: int, parent: Node3D, name: String, entry: Array, seat: Vector2, rect: Rect2, scale: float, lift: float, clump: String = "") -> void:
	var holder := Node3D.new()
	holder.name = name
	parent.add_child(holder)
	# In front of all the stone the piece covers; pieces of one group a hair
	# apart, so none flickers through the next.
	holder.position = Vector3(seat.x,seat.y,_front_over(rect)+.05+lift)
	FloraModels.plant(holder,entry,quality!="battery",scale)
	_take(index,rect,clump)

# Plants and stones along the ledges of a location's own rock.
func _build_ledge_plants(index: int, parent: Node3D) -> void:
	var rock := RockSurface.make(layout as MaskLayout)
	var random := layout.rng(index,905)
	var budget := 46 if quality=="high" else 30 if quality=="balanced" else 12
	# Seated on the outline the player sees, the pieces keep clear air round
	# them; the ordinary decor already fills the tops, so these add fewer.
	var seated := _seats_on_view()
	if seated: budget = roundi(budget*1.2)
	var gap := _decor_gap() if seated else .06
	var placed := 0
	for spot: Vector3 in rock.perches(index*BAND,(index+1)*BAND,random,budget*8):
		if placed>=budget: break
		if not await pause(parent): return
		var point := Vector2(spot.x,spot.y)
		if not _decor_route_clear(point,.9) or _in_cave(point,.4): continue
		var entry := _decor_entry("grass" if random.randf()<.6 else "pebbles",profile_at(point.y),random)
		if entry.is_empty(): continue
		var scale := random.randf_range(.95,1.4)
		var size := FloraModels.size_of(entry,scale)
		var on_lens := false
		if seated:
			# On the top of a bed's lens inside the face, or on the top of the
			# outline: climb from the perch to the air over it.
			if rock.normal_at(point).y>.4 and open_at(point) == false and rock.distance(point)>1.0: on_lens = true
			else:
				var rise := 0
				while not open_at(point) and rise<25:
					point.y += .1
					rise += 1
				if rise>=25: continue
				point = _top_seat(point+Vector2(0,.2),size.x*.6,size.x,.6,.3)
				if not point.is_finite(): continue
		var rect := Rect2(point.x-size.x*.5,point.y,size.x,size.y)
		if _taken(index,rect.grow(gap)) or (seated and not on_lens and not _decor_fits(rect,false)): continue
		# On the snow peak the ice comes later and needs its room too; in the
		# desert the groups stand first and keep theirs.
		if (layout as MaskLayout).rock_form in ["winter","desert"] and _would_crowd(index,rect.get_center()): continue
		var holder := Node3D.new()
		holder.name = "Растение_%d" % placed
		parent.add_child(holder)
		# In front of all the stone the piece covers, never inside it.
		holder.position = Vector3(point.x,point.y,(_front_over(rect) if seated else spot.z)+.05)
		FloraModels.plant(holder,entry,quality!="battery",scale)
		_take(index,rect)
		placed += 1
	var cold := (layout as MaskLayout).rock_form=="winter"
	# Ice hangs in rows from the front of every snow shelf, over the hollow
	# under it.
	var hanging := 0
	if cold and seated: hanging = await _shelf_icicles(index,parent,random)
	if not is_instance_valid(parent): return
	# Roots and ice hang under the overhangs.
	var hanging_budget := budget if cold else budget/3
	for spot: Vector3 in rock.hangs(index*BAND,(index+1)*BAND,random,budget*40):
		if hanging>=hanging_budget: break
		if not await pause(parent): return
		var point := Vector2(spot.x,spot.y)
		if not _decor_route_clear(point,.9) or _in_cave(point,.4): continue
		var entry := _decor_entry("hanging",profile_at(point.y),random)
		if entry.is_empty(): continue
		var size := FloraModels.size_of(entry,1.0)
		if seated:
			point = _hang_seat(point,size)
			if not point.is_finite(): continue
			spot.z = _front_over(Rect2(point.x-.2,point.y,.4,.3))
		var rect := Rect2(point.x-size.x*.5,point.y-size.y,size.x,size.y)
		if _taken(index,rect.grow(gap*.5 if cold and seated else .04)) or (cold and seated and (_would_crowd(index,rect.get_center()) or not _decor_fits(rect,true))): continue
		var holder := Node3D.new()
		holder.name = "Подвес_%d_0" % hanging
		parent.add_child(holder)
		holder.position = Vector3(point.x,point.y,spot.z+.05)
		FloraModels.plant(holder,entry,quality!="battery",random.randf_range(.8,1.1) if cold else random.randf_range(.7,1.1))
		_take(index,rect)
		hanging += 1

# Crystals stand on the crests of the cold rock, the ends of its shelves
# first, where they stand out of the tower. They claim their place before the
# small decor, which fits round them.
func _build_crystals(index: int, parent: Node3D) -> void:
	var rock := RockSurface.make(layout as MaskLayout)
	var random := layout.rng(index,906)
	var seated := _seats_on_view()
	var gap := _decor_gap() if seated else .2
	var grown := 0
	var spots: Array = []
	for shelf in (layout as MaskLayout).rock_marks:
		for end: float in [-1.0,1.0]:
			var x: float = float(shelf[0])+end*(float(shelf[2])-random.randf_range(.8,1.6))
			var y: float = float(shelf[1])+float(shelf[3])*(x-float(shelf[0]))-.3
			if y>=index*BAND and y<(index+1)*BAND: spots.append(Vector3(x,y,0))
	spots.append_array(rock.crests(index*BAND,(index+1)*BAND,random,1500 if seated else 600))
	for spot: Vector3 in spots:
		if grown>=3: break
		if not await pause(parent): return
		var point := Vector2(spot.x,spot.y)
		if not _decor_route_clear(point,1.4): continue
		var entry := _decor_entry("crystal",profile_at(point.y),random)
		if entry.is_empty(): continue
		var size := FloraModels.size_of(entry,1.3)
		if seated:
			var rise := 0
			while not open_at(point) and rise<12:
				point.y += .1
				rise += 1
			# A crystal grows from a small top: a narrow footing will do.
			point = _top_seat(point+Vector2(0,.2),.5,.9,.6,.35)
			if not point.is_finite() or _kin_near(index,"crystal",point): continue
		var rect := Rect2(point.x-size.x*.5,point.y,size.x,size.y)
		if _taken(index,rect.grow(gap)) or (seated and not _decor_fits(rect,false)): continue
		var holder := Node3D.new()
		holder.name = "Кристалл_%d" % grown
		parent.add_child(holder)
		holder.position = Vector3(point.x,point.y,(_front_over(rect) if seated else spot.z)+.05)
		FloraModels.plant(holder,entry,quality!="battery",1.3)
		_take(index,rect)
		if seated: _take_kin(index,"crystal",point)
		grown += 1

# Icicles along the foot of each snow shelf's front in a band, a piece every
# metre and a half, hanging in front of the hollow under the shelf.
func _shelf_icicles(index: int, parent: Node3D, random: RandomNumberGenerator) -> int:
	var placed := 0
	var spacing := 1.5 if quality!="battery" else 2.6
	for shelf in (layout as MaskLayout).rock_marks:
		var x0 := float(shelf[0])
		var half := float(shelf[2])
		var slope := float(shelf[3])
		var thick := float(shelf[4])
		var foot_y := float(shelf[1])-thick
		if foot_y<index*BAND or foot_y>=(index+1)*BAND: continue
		var x := x0-half+.7+random.randf_range(0,.5)
		while x<x0+half-.7:
			if not await pause(parent): return placed
			var root := Vector2(x,foot_y+slope*(x-x0)+.12)
			x += spacing*random.randf_range(.85,1.15)
			# The shelf has stone where the ice hangs from; the ice must not
			# cover the route or a grip.
			if open_at(root+Vector2(0,.15)) or not _decor_route_clear(root,.9): continue
			var entry := FloraModels.pick("icicle",random,"hang")
			if entry.is_empty(): continue
			var scale := random.randf_range(.8,1.15)
			var size := FloraModels.size_of(entry,scale)
			var rect := Rect2(root.x-size.x*.5,root.y-size.y,size.x,size.y)
			if _taken(index,rect.grow(.45)) or _would_crowd(index,rect.get_center()) or not _decor_fits(rect,true): continue
			var holder := Node3D.new()
			holder.name = "Подвес_полки_%d" % placed
			parent.add_child(holder)
			holder.position = Vector3(root.x,root.y,_front_over(Rect2(root.x-.3,root.y,.6,.35))+.05)
			FloraModels.plant(holder,entry,quality!="battery",scale)
			_take(index,rect)
			placed += 1
	return placed

const SUMMER_STONE := Color("7d776c")
const SUMMER_SHADE := Color("4a4850")

const MOSS_TOP := Color("6b843a")
const MOSS_DARK := Color("43562b")

func _summer_boulders() -> bool:
	return layout is MaskLayout and (layout as MaskLayout).rock_form=="boulder"

# How much moss summer stone carries at a point (docs/SUMMER_LEVEL_PLAN.md,
# stage 2): all the way up, thickest at the foot and by the rest ledges,
# thinning towards the summit.
func summer_moss(at: Vector2) -> float:
	var top := maxf(layout.summit,40.0) if layout.finite else 120.0
	var moss := lerpf(.8,.38,clampf(at.y/top,0,1))
	moss += .2*(1.0-smoothstep(4.0,14.0,at.y))
	for ledge in layout.ledges:
		var deck := Vector2(clampf(at.x,float(ledge["left"]),float(ledge["right"])),float(ledge["top"]))
		if deck.distance_to(at)<4.0: moss += .25*(1.0-deck.distance_to(at)/4.0)
	# Thickest of all by the water (owner, 2026-11-05).
	if layout is MaskLayout:
		for place: Dictionary in (layout as MaskLayout).summer_places:
			if str(place["kind"])!="waterfall": continue
			var spring := Vector2(float(place["at"][0]),float(place["at"][1]))
			if spring.distance_to(at)<6.0: moss += .45*(1.0-spring.distance_to(at)/6.0)
	return clampf(moss,0,1.4)

# A boulder whose foot hangs over open air: its underside gets a band of moss,
# as under the shelves and islands on summerClose.png.
func _hangs_over_air(mass: RockMassSpec) -> bool:
	var foot := Vector2(INF,INF)
	for point in mass.outer_contour:
		if point.y<foot.y: foot = point
	return open_at(foot-Vector2(0,.45)) and open_at(foot-Vector2(0,1.2))

# Grass tufts along the top edges of summer boulders, mostly in the joints
# where the next boulder rests above, never on a gameplay object or the
# route spine. Built into the chunk's rock mesh.
func _summer_tufts(index: int, surface: SurfaceTool) -> int:
	var random := layout.rng(index,913)
	var budget := 150 if quality=="high" else 110 if quality=="balanced" else 50
	var emitted := 0
	var placed := 0
	var masses: Array = front_band(index).duplicate()
	for mass: RockMassSpec in masses:
		if placed>=budget: break
		if mass.bounds.size.x<1.4: continue
		var moss := summer_moss(mass.centroid())
		var center := mass.centroid()
		for edge in mass.top_edges:
			var a: Vector2 = mass.outer_contour[edge]
			var b: Vector2 = mass.outer_contour[(edge+1)%mass.outer_contour.size()]
			var spots := clampi(int(a.distance_to(b)/.8),1,3)
			for spot in range(spots):
				if placed>=budget or random.randf()>.55*moss: continue
				var rim := a.lerp(b,(spot+random.randf_range(.25,.75))/spots)
				var at := rim.lerp(center,.12/maxf(rim.distance_to(center),.12))
				# Joint: stone of another boulder just above the rim. An open top
				# keeps some tufts too, fewer (the outline has its own decor).
				var joint := not open_at(rim+Vector2(0,.35))
				if not joint and random.randf()<.6: continue
				var hit := surface_query(at)
				if not hit.valid() or hit.mass!=mass: continue
				if _objects_near(at,.55) or not _decor_route_clear(at,.5): continue
				var height := random.randf_range(.3,.52)*(1.1 if joint else .9)
				# In front of the stone its blades cover: in a joint they rise over
				# the foot of the boulder above, which stands further forward.
				var front := maxf(hit.position.z,_front_over(Rect2(at.x-.3,at.y,.6,height)))
				emitted += RockMassBuilder.emit_tuft(surface,Vector3(at.x,at.y,front+.04),height,random.randf_range(.45,.75),MOSS_TOP.lightened(.12),MOSS_DARK,random.randi_range(0,9999))
				placed += 1
	return emitted

func _palette(profile: GripBiomeProfile, height: float, mass: RockMassSpec) -> Dictionary:
	var rock: Dictionary = profile.rock_material
	# Each host body has its own shade of the zone's rock.
	var base := zone_color(height)
	var shift := (mass.tone-.5)*.14
	base = base.lightened(shift) if shift>0 else base.darkened(-shift)
	var facets: Array = []
	for color in rock["facet_palette"]: facets.append(base.lerp(color,.5))
	var under: Color = base.lerp(rock["underside_tint"],.42).darkened(.16)
	if _summer_boulders():
		# Summer stone is light warm grey (summerClose.png), not the dark cold
		# grey of the shared profiles; each boulder lit from above.
		base = base.lerp(SUMMER_STONE,.7)
		facets.clear()
		for color in rock["facet_palette"]: facets.append(base.lerp(color.lerp(SUMMER_STONE,.6),.45))
		under = base.lerp(SUMMER_SHADE,.5)
		return {"base":base,"facets":facets,"rise":.36,
			"top":base.lerp(rock["top_light_tint"],.3).lightened(.03),
			"side":base.darkened(.06),
			"under":under,
			"inner":under.darkened(.12),
			"moss":summer_moss(mass.centroid())+(.45 if mass.role=="bridge" else 0.0),"moss_top":MOSS_TOP,"moss_dark":MOSS_DARK,
			"hang_moss":_hangs_over_air(mass)}
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
	if layout is MaskLayout and (layout as MaskLayout).rock_form!="boulder":
		# The masses stay an unseen frame behind the location's own rock.
		front_band(index)
		_build_rock_surface(index,parent)
		return
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	var emitted := 0
	var walls := quality!="battery"
	for mass in front_band(index):
		if not await pause(parent): return
		var center: Vector2 = mass.centroid()
		emitted += RockMassBuilder.emit(surface,mass,_palette(profile_at(center.y),center.y,mass),_cavity,walls)
	if emitted>0 and _summer_boulders(): emitted += _summer_tufts(index,surface)
	if emitted==0: return
	var instance := MeshInstance3D.new()
	instance.name = "Скальный массив_%d" % index
	instance.mesh = surface.commit()
	instance.material_override = rock_material_at(index*BAND+BAND*.5)
	# Masses shade each other: overhangs, lintels and stacked blocks cast on
	# the stone behind them. Battery has no shadow map at all.
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if quality!="battery" else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(instance)
	if _summer_boulders(): _add_summer_air(index,parent)

func _build_rock_surface(index: int, parent: Node3D) -> void:
	var rock := RockSurface.make(layout as MaskLayout)
	if rock==null: return
	var cell := .42 if quality=="high" else .6 if quality=="balanced" else 1.0
	var mesh := rock.build(index*BAND,(index+1)*BAND,cell)
	if mesh.get_surface_count()==0: return
	var instance := MeshInstance3D.new()
	instance.name = "Скальный массив_%d" % index
	instance.mesh = mesh
	instance.material_override = rock_material_at(index*BAND+BAND*.5)
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if quality!="battery" else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(instance)
	if (layout as MaskLayout).rock_form=="desert" and quality!="battery":
		_add_dust(index,parent)
		_add_heat_haze(index,parent)
		_add_tumbleweed(index,parent)
	if (layout as MaskLayout).rock_form=="winter" and quality!="battery":
		_add_snowfall(index,parent)
		_add_blown_snow(index,parent,rock)

# Fine sand blowing across the desert face in the wind, a few grains per band.
func _add_dust(index: int, parent: Node3D) -> void:
	var dust := GPUParticles3D.new()
	dust.name = "Пыль_%d" % index
	dust.amount = 48 if quality=="high" else 24
	dust.lifetime = 6.0
	dust.preprocess = 6.0
	dust.position = Vector3(0,index*BAND+BAND*.5,-.4)
	dust.visibility_aabb = AABB(Vector3(-24,-BAND*.6,-2),Vector3(48,BAND*1.2,4))
	dust.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var process := ParticleProcessMaterial.new()
	process.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	process.emission_box_extents = Vector3(22,BAND*.5,.6)
	process.direction = Vector3(1,.12,0)
	process.spread = 12.0
	process.initial_velocity_min = .5
	process.initial_velocity_max = 1.4
	process.gravity = Vector3(0,-.05,0)
	process.scale_min = .5
	process.scale_max = 1.2
	dust.process_material = process
	var grain := QuadMesh.new()
	grain.size = Vector2(.07,.07)
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	material.albedo_color = Color(.96,.82,.58,.55)
	grain.material = material
	dust.draw_pass_1 = grain
	parent.add_child(dust)

# --- Desert air (docs/DESERT_LEVEL_PLAN.md, stage 5) --------------------------------

# Hot air shimmers over the foot of the canyon and over its widest benches:
# the picture behind wavers a little, never tinted. Not on battery.
const HEAT_CODE := """shader_type spatial; render_mode unshaded, cull_disabled, shadows_disabled, depth_draw_never;
uniform sampler2D screen : hint_screen_texture, filter_linear_mipmap;
uniform float strength = .0035;
void fragment(){
	float rise = 1.0-UV.y;
	float body = smoothstep(0.0,.25,rise)*(1.0-smoothstep(.55,1.0,rise))*smoothstep(0.0,.12,UV.x)*smoothstep(1.0,.88,UV.x);
	vec2 wobble = vec2(sin(rise*38.0-TIME*3.1+UV.x*9.0),cos(UV.x*27.0+rise*12.0-TIME*2.2))*strength*body;
	ALBEDO = texture(screen,SCREEN_UV+wobble).rgb;
	ALPHA = body;
}"""
static var heat_shader: Shader

func _heat_strip(parent: Node3D, name: String, at: Vector3, size: Vector2) -> void:
	if heat_shader==null:
		heat_shader = Shader.new()
		heat_shader.code = HEAT_CODE
	var material := ShaderMaterial.new()
	material.shader = heat_shader
	var plane := QuadMesh.new()
	plane.size = size
	var strip := MeshInstance3D.new()
	strip.name = name
	strip.mesh = plane
	strip.material_override = material
	strip.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	strip.position = at
	parent.add_child(strip)

func _add_heat_haze(index: int, parent: Node3D) -> void:
	if index==0: _heat_strip(parent,"Марево подножия",Vector3(0,3.0,2.2),Vector2(44,6.0))
	# Over the two widest benches of the band, in front of the face.
	var benches: Array = (layout as MaskLayout).rock_marks.filter(func(ledge: Array) -> bool: return int(floor(float(ledge[1])/BAND))==index)
	benches.sort_custom(func(a: Array, b: Array) -> bool: return float(a[2])>float(b[2]))
	for k in range(mini(2,benches.size())):
		var ledge: Array = benches[k]
		_heat_strip(parent,"Марево_%d" % k,Vector3(float(ledge[3]),float(ledge[1])+1.6,2.0),Vector2(float(ledge[2])*1.6,3.2))

# Now and then a tumbleweed bowls along on the wind, across the band and
# off the face: one at a time, most of the time none. Not on battery.
func _add_tumbleweed(index: int, parent: Node3D) -> void:
	var weed := GPUParticles3D.new()
	weed.name = "Перекати-поле_%d" % index
	weed.amount = 1
	weed.lifetime = 14.0
	weed.preprocess = layout.rng(index,941).randf_range(0.0,14.0)
	weed.position = Vector3(-26,index*BAND+BAND*.5,1.8)
	weed.visibility_aabb = AABB(Vector3(-4,-BAND*.6,-2),Vector3(60,BAND*1.2,4))
	weed.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var process := ParticleProcessMaterial.new()
	process.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	process.emission_box_extents = Vector3(.5,BAND*.4,.1)
	process.direction = Vector3(1,.05,0)
	process.spread = 6.0
	# Most of its life it waits off the face: it crosses in a few seconds.
	process.initial_velocity_min = 11.0
	process.initial_velocity_max = 14.0
	process.gravity = Vector3(0,-.6,0)
	process.angle_min = -180.0
	process.angle_max = 180.0
	process.angular_velocity_min = -420.0
	process.angular_velocity_max = -300.0
	process.turbulence_enabled = true
	process.turbulence_noise_strength = 1.4
	process.turbulence_influence_min = .05
	process.turbulence_influence_max = .12
	weed.process_material = process
	var ball := QuadMesh.new()
	ball.size = Vector2(.9,.9)
	var material := StandardMaterial3D.new()
	material.albedo_texture = load(FloraModels.sprite_path("dry_plant",4))
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
	material.alpha_scissor_threshold = .5
	material.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	material.albedo_color = Color(.92,.8,.62)
	ball.material = material
	weed.draw_pass_1 = ball
	parent.add_child(weed)

# --- Summer air (docs/SUMMER_LEVEL_PLAN.md, stage 5) --------------------------------

# Light summer weather of a chunk: a few leaves drifting on the breeze (none
# on battery) and a pale haze round the foot, behind the stone.
const SUMMER_BREEZE := Vector3(1.0,-.18,0)

func _add_summer_air(index: int, parent: Node3D) -> void:
	if quality!="battery":
		var leaves := summer_leaves(10 if quality=="high" else 6,Vector3(22,BAND*.5,.4),SUMMER_BREEZE,Vector2(.5,1.1),8.0)
		leaves.name = "Листья_%d" % index
		leaves.position = Vector3(0,index*BAND+BAND*.5,2.6)
		parent.add_child(leaves)
	if index==0:
		var haze := MeshInstance3D.new()
		haze.name = "Дымка подножия"
		var plane := QuadMesh.new()
		plane.size = Vector2(56,11)
		haze.mesh = plane
		var material := ShaderMaterial.new()
		var shader := Shader.new()
		shader.code = HAZE_CODE
		material.shader = shader
		haze.material_override = material
		haze.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		haze.position = Vector3(0,2.5,-5.6)
		parent.add_child(haze)

const HAZE_CODE := """shader_type spatial; render_mode unshaded, cull_disabled, shadows_disabled, depth_draw_never;
void fragment(){
	float low = 1.0-smoothstep(0.0,1.0,1.0-UV.y);
	float sides = smoothstep(0.0,.12,UV.x)*smoothstep(1.0,.88,UV.x);
	ALBEDO = vec3(.86,.93,.95);
	ALPHA = low*low*sides*.5;
}"""

# Leaves on the wind: soft green and gold flecks turning as they go. `drift`
# is the wind's way, `speed` its range; shared by the breeze, the wind
# pockets (HazardVisuals) and nothing else.
static var leaf_mesh: QuadMesh

static func summer_leaves(amount: int, extents: Vector3, drift: Vector3, speed: Vector2, lifetime: float) -> GPUParticles3D:
	var leaves := GPUParticles3D.new()
	leaves.amount = maxi(1,amount)
	leaves.lifetime = lifetime
	leaves.preprocess = lifetime
	leaves.visibility_aabb = AABB(-extents-Vector3(6,6,1),extents*2.0+Vector3(12,12,2))
	leaves.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var process := ParticleProcessMaterial.new()
	process.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	process.emission_box_extents = extents
	process.direction = drift.normalized()
	process.spread = 14.0
	process.initial_velocity_min = speed.x
	process.initial_velocity_max = speed.y
	process.gravity = Vector3(0,-.12,0)
	process.angle_min = -180.0
	process.angle_max = 180.0
	process.angular_velocity_min = -160.0
	process.angular_velocity_max = 160.0
	process.turbulence_enabled = true
	process.turbulence_noise_strength = .6
	process.turbulence_noise_scale = 4.0
	process.scale_min = .7
	process.scale_max = 1.25
	var colors := Gradient.new()
	# Greens only: a gold fleck would read as a coin.
	colors.set_color(0,Color("6f9a3c"))
	colors.set_color(1,Color("a3bb52"))
	var ramp := GradientTexture1D.new()
	ramp.gradient = colors
	process.color_initial_ramp = ramp
	var fade := Gradient.new()
	fade.offsets = PackedFloat32Array([0.0,.12,.85,1.0])
	fade.colors = PackedColorArray([Color(1,1,1,0),Color.WHITE,Color.WHITE,Color(1,1,1,0)])
	var alpha := GradientTexture1D.new()
	alpha.gradient = fade
	process.color_ramp = alpha
	leaves.process_material = process
	if leaf_mesh==null:
		leaf_mesh = QuadMesh.new()
		leaf_mesh.size = Vector2(.36,.2)
		var material := StandardMaterial3D.new()
		material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		material.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
		material.vertex_color_use_as_albedo = true
		var shape := GradientTexture2D.new()
		shape.fill = GradientTexture2D.FILL_RADIAL
		shape.fill_from = Vector2(.5,.5)
		shape.fill_to = Vector2(.5,0.0)
		var edge := Gradient.new()
		edge.offsets = PackedFloat32Array([0.0,.75,1.0])
		edge.colors = PackedColorArray([Color.WHITE,Color.WHITE,Color(1,1,1,0)])
		shape.gradient = edge
		shape.width = 32
		shape.height = 32
		material.albedo_texture = shape
		leaf_mesh.material = material
	leaves.draw_pass_1 = leaf_mesh
	return leaves

# A few butterflies wandering round a tree's crown.
func _summer_butterflies(parent: Node3D, crown: Vector3) -> void:
	if quality=="battery": return
	var flight := GPUParticles3D.new()
	flight.name = "Бабочки_%d" % roundi(crown.x*10.0+crown.y*1000.0)
	flight.amount = 3
	flight.lifetime = 9.0
	flight.preprocess = 9.0
	flight.position = crown
	flight.visibility_aabb = AABB(Vector3(-4,-4,-1),Vector3(8,8,2))
	flight.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var process := ParticleProcessMaterial.new()
	process.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	process.emission_box_extents = Vector3(1.4,1.0,.2)
	process.direction = Vector3(1,.3,0)
	process.spread = 180.0
	process.initial_velocity_min = .2
	process.initial_velocity_max = .5
	process.gravity = Vector3.ZERO
	process.turbulence_enabled = true
	process.turbulence_noise_strength = 1.4
	process.turbulence_noise_scale = 2.2
	process.turbulence_noise_speed = Vector3(.3,.3,0)
	process.scale_min = .8
	process.scale_max = 1.1
	var colors := Gradient.new()
	colors.set_color(0,Color("fff6d8"))
	colors.set_color(1,Color("f2b53c"))
	var ramp := GradientTexture1D.new()
	ramp.gradient = colors
	process.color_initial_ramp = ramp
	flight.process_material = process
	var wing := QuadMesh.new()
	wing.size = Vector2(.26,.18)
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	material.vertex_color_use_as_albedo = true
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.albedo_texture = leaf_mesh.material.albedo_texture if leaf_mesh!=null else null
	wing.material = material
	flight.draw_pass_1 = wing
	parent.add_child(flight)

# A soft round flake, shared by all snow of the peak.
static var flake_material: StandardMaterial3D

static func snow_flake(size: float) -> QuadMesh:
	if flake_material==null:
		var gradient := Gradient.new()
		gradient.set_color(0,Color(1,1,1,1))
		gradient.set_color(1,Color(1,1,1,0))
		var texture := GradientTexture2D.new()
		texture.gradient = gradient
		texture.fill = GradientTexture2D.FILL_RADIAL
		texture.fill_from = Vector2(.5,.5)
		texture.fill_to = Vector2(.5,0)
		texture.width = 32
		texture.height = 32
		flake_material = StandardMaterial3D.new()
		flake_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		flake_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		flake_material.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
		flake_material.albedo_texture = texture
		flake_material.albedo_color = Color(.96,.98,1.0,1.0)
		flake_material.vertex_color_use_as_albedo = true
	var flake := QuadMesh.new()
	flake.size = Vector2(size,size)
	flake.material = flake_material
	return flake

# A streak of snow torn along the wind, for gusts: the flake stretched out
# and turned along `angle` (radians).
static func snow_streak(length: float, angle: float) -> QuadMesh:
	snow_flake(.1)
	var material: StandardMaterial3D = flake_material.duplicate()
	material.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	material.albedo_color = Color(.97,.99,1.0,.9)
	var streak := QuadMesh.new()
	streak.size = Vector2(length,length*.22)
	streak.material = material
	return streak

# Snow falling over the whole climb, in front of the rock and the hero, as on
# the screen: big slow flakes near the viewer, small ones behind them.
func _add_snowfall(index: int, parent: Node3D) -> void:
	for layer in range(2):
		var near := layer==0
		var snow := GPUParticles3D.new()
		snow.name = "Снегопад_%d_%d" % [index,layer]
		snow.amount = (130 if near else 120) if quality=="high" else (85 if near else 75)
		snow.lifetime = 14.0
		snow.preprocess = 14.0
		snow.position = Vector3(0,index*BAND+BAND*.5,3.2 if near else 1.6)
		snow.visibility_aabb = AABB(Vector3(-26,-BAND,-1),Vector3(52,BAND*2.0,2))
		snow.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var process := ParticleProcessMaterial.new()
		process.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
		process.emission_box_extents = Vector3(24,BAND*.5,.4)
		# Down and a little with the wind; each flake drifts at its own pace.
		process.direction = Vector3(.35,-1,0)
		process.spread = 14.0
		process.initial_velocity_min = .7 if near else .45
		process.initial_velocity_max = 1.3 if near else .8
		process.gravity = Vector3.ZERO
		process.scale_min = .7
		process.scale_max = 1.3
		var fade := Gradient.new()
		fade.set_color(0,Color(1,1,1,0))
		fade.add_point(.12,Color(1,1,1,1))
		fade.add_point(.85,Color(1,1,1,1))
		fade.set_color(fade.get_point_count()-1,Color(1,1,1,0))
		var ramp := GradientTexture1D.new()
		ramp.gradient = fade
		process.color_ramp = ramp
		snow.process_material = process
		snow.draw_pass_1 = snow_flake(.42 if near else .2)
		parent.add_child(snow)

# Wind lifts snow off the tops of the rock in puffs, along the wind.
func _add_blown_snow(index: int, parent: Node3D, rock: RockSurface) -> void:
	var random := layout.rng(index,907)
	var puffs := 0
	for spot: Vector3 in rock.crests(index*BAND,(index+1)*BAND,random,400):
		if puffs>=(4 if quality=="high" else 3): break
		if rock.distance(Vector2(spot.x,spot.y))>.6: continue
		var blown := GPUParticles3D.new()
		blown.name = "Сдув_%d_%d" % [index,puffs]
		blown.amount = 24 if quality=="high" else 14
		blown.lifetime = 1.8
		blown.preprocess = 2.0
		blown.explosiveness = .1
		blown.randomness = .5
		blown.position = Vector3(spot.x,spot.y+.1,spot.z+.3)
		blown.visibility_aabb = AABB(Vector3(-2,-2,-1),Vector3(10,5,2))
		blown.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var process := ParticleProcessMaterial.new()
		process.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
		process.emission_box_extents = Vector3(.8,.1,.2)
		process.direction = Vector3(1,.35,0)
		process.spread = 18.0
		process.initial_velocity_min = 1.6
		process.initial_velocity_max = 3.2
		process.gravity = Vector3(0,-.6,0)
		process.damping_min = .6
		process.damping_max = 1.2
		process.scale_min = .6
		process.scale_max = 1.4
		var fade := Gradient.new()
		fade.set_color(0,Color(1,1,1,.9))
		fade.set_color(1,Color(1,1,1,0))
		var ramp := GradientTexture1D.new()
		ramp.gradient = fade
		process.color_ramp = ramp
		blown.process_material = process
		blown.draw_pass_1 = snow_flake(.2)
		parent.add_child(blown)
		puffs += 1

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

# On the snow peak a rest is a slab of its own rock: a snow top on the walking
# line, a dark stone front and ice hanging under it, as the shelves of the
# face are. Other places keep their timber platforms.
func _place_platform(holder: Node3D, object: Dictionary, mount: SurfaceMount) -> Node3D:
	if not (layout is MaskLayout and (layout as MaskLayout).rock_form=="winter"): return super._place_platform(holder,object,mount)
	var left: float = object["left"]
	var right: float = object["right"]
	var top: float = object["top"]
	var width := right-left+.5
	var thick := .7
	var back := _front_over(Rect2(left-.25,top-thick,width,thick))+PLATFORM_GAP
	var front := maxf(PLATFORM_FRONT,back+.6)
	var model := Node3D.new()
	model.name = "Снежная плита"
	holder.add_child(model)
	model.position = Vector3((left+right)*.5,top,(back+front)*.5)-holder.position
	var depth := front-back
	var stone := StandardMaterial3D.new()
	stone.albedo_color = Color("5f6d86")
	stone.roughness = .9
	var snow := StandardMaterial3D.new()
	snow.albedo_color = Color("e6edf6")
	snow.roughness = .8
	for part in [["Камень плиты",Vector3(0,-thick*.5-.06,0),Vector3(width,thick-.12,depth),stone],["Снег плиты",Vector3(0,-.07,.02),Vector3(width+.14,.14,depth+.06),snow]]:
		var mesh := BoxMesh.new()
		mesh.size = part[2]
		var piece := MeshInstance3D.new()
		piece.name = part[0]
		piece.mesh = mesh
		piece.material_override = part[3]
		piece.position = part[1]
		piece.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if quality!="battery" else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		model.add_child(piece)
	# Ice along the front edge, short enough to stay clear of what is below.
	var random := layout.rng(int(roundf(top*10)),908)
	var room := _room_under_ledge(object)
	var count := int(width/.7)
	for k in range(count):
		var entry := FloraModels.pick("icicle",random,"hang")
		if entry.is_empty() or room<1.0: break
		var scale := clampf(random.randf_range(.6,.9),.4,room*.5)
		var hang := Node3D.new()
		hang.name = "Сосульки плиты_%d" % k
		hang.position = Vector3(-width*.5+(k+.5)*width/count,-thick,depth*.5-.02)
		model.add_child(hang)
		FloraModels.plant(hang,entry,quality!="battery",scale)
	object["platform_style"] = "snow"
	return model

# --- Decor --------------------------------------------------------------------------

func _decor_blocked(point: Vector2, reach: float = 0.0) -> bool:
	if _in_cave(point,reach+.4): return true
	for anchor in layout.nearby_ids(point.y-2.0,point.y+2.0):
		var grip: Dictionary = layout.anchors[anchor]
		var grip_size: Vector2 = grip.get("dimensions",Vector2(1.6,.65))
		# Keep a clear halo around the whole visible outcrop, not just its
		# gameplay centre. This stops plants, roots and props reading as extra
		# hookable platforms.
		var grip_clearance := maxf(2.0,maxf(grip_size.x,grip_size.y)*.5+.82)
		if grip["pos"].distance_to(point)<grip_clearance+reach: return true
	# Obstacles, finds and ledges come from height bins (see _blocker_bins):
	# each stands in every bin its own clearance reaches.
	var bins := _blocker_bins()
	var span := maxf(reach,0.0)
	for bin in range(int(floor((point.y-span)/BLOCKER_BIN)),int(floor((point.y+span)/BLOCKER_BIN))+1):
		for entry: Array in bins.get(bin,[]):
			var object: Dictionary = entry[1]
			match int(entry[0]):
				0:
					if object["pos"].distance_to(point)<1.15+maxf(object["dimensions"].x,object["dimensions"].y)*.5+reach: return true
				1:
					if object["pos"].distance_to(point)<.8+reach: return true
				_:
					# The platform's supports reach well under its deck.
					var below := float(object["top"])-point.y
					if point.x>float(object["left"])-.5 and point.x<float(object["right"])+.5 and below>-.9-reach and below<1.6+reach: return true
	return false

const BLOCKER_BIN := 4.0
var blocker_bins: Dictionary = {}
var blocker_signature := Vector4i(-1,-1,-1,-1)

# [kind, object] by height bin: obstacles (0), finds (1) and ledges (2),
# each in the bins its clearance covers at zero reach. Rebuilt when objects
# are added; their positions never change.
func _blocker_bins() -> Dictionary:
	var signature := _layout_signature()
	if signature==blocker_signature: return blocker_bins
	blocker_signature = signature
	blocker_bins = {}
	for obstacle in layout.obstacles:
		var extent: float = 1.15+maxf(obstacle["dimensions"].x,obstacle["dimensions"].y)*.5
		_bin_blocker(0,obstacle,obstacle["pos"].y-extent,obstacle["pos"].y+extent)
	for find in layout.finds: _bin_blocker(1,find,find["pos"].y-.8,find["pos"].y+.8)
	for ledge in layout.ledges: _bin_blocker(2,ledge,float(ledge["top"])-1.6,float(ledge["top"])+.9)
	return blocker_bins

func _bin_blocker(kind: int, object: Dictionary, low: float, high: float) -> void:
	for bin in range(int(floor(low/BLOCKER_BIN)),int(floor(high/BLOCKER_BIN))+1):
		if not blocker_bins.has(bin): blocker_bins[bin] = []
		blocker_bins[bin].append([kind,object])

func _decor_route_clear(point: Vector2, radius: float) -> bool:
	# Keep the line of throws and swings readable: no tall decor on the spine.
	return absf(point.x-_route_x(point.y))>radius

func _on_face(mass: RockMassSpec, point: Vector2) -> RockSurfaceHit:
	var hit := surface_query(point)
	return hit if hit.valid() and hit.mass_id==mass.id else null

# Pieces already standing in a band (landmarks first, then decor), so no
# two overlap.
var decor_rects: Dictionary = {}
# The clump of each of decor_rects, "" for a piece on its own.
var decor_clumps: Dictionary = {}

func _taken(index: int, rect: Rect2) -> bool:
	for band in [index-1,index,index+1]:
		for other: Rect2 in decor_rects.get(band,[]):
			if other.intersects(rect): return true
	return false

# How many pieces already stand within `reach` of a point.
# A clump (a desert group, planted piece by piece) is one neighbour to what
# stands round it, and its own pieces do not crowd each other; `clump` is the
# clump of the piece asking, "" for none. As decor_audit.gd judges it.
func _crowd_near(index: int, point: Vector2, reach: float = 2.6, clump: String = "") -> int:
	var count := 0
	var clumps := {}
	for band in [index-1,index,index+1]:
		var rects: Array = decor_rects.get(band,[])
		var owners: Array = decor_clumps.get(band,[])
		for k in range(rects.size()):
			if (rects[k] as Rect2).get_center().distance_to(point)>=reach: continue
			var owner: String = owners[k] if k<owners.size() else ""
			if owner.is_empty(): count += 1
			elif owner!=clump and not clumps.has(owner):
				clumps[owner] = true
				count += 1
	return count

# Whether a piece at `point` would stand among more than three others, or
# put one of its neighbours among more than three.
func _would_crowd(index: int, point: Vector2, reach: float = 2.6, clump: String = "") -> bool:
	if _crowd_near(index,point,reach,clump)>=3: return true
	for band in [index-1,index,index+1]:
		var rects: Array = decor_rects.get(band,[])
		var owners: Array = decor_clumps.get(band,[])
		for k in range(rects.size()):
			var owner: String = owners[k] if k<owners.size() else ""
			if not clump.is_empty() and owner==clump: continue
			# A neighbour gains this piece only if it is not of the same clump.
			if (rects[k] as Rect2).get_center().distance_to(point)<reach and _crowd_near(index,(rects[k] as Rect2).get_center(),reach,owner)>=4: return true
	return false

func _take(index: int, rect: Rect2, clump: String = "") -> void:
	if not decor_rects.has(index): decor_rects[index] = []
	if not decor_clumps.has(index): decor_clumps[index] = []
	# Keep the clumps in step with the rects, whoever took them before.
	while (decor_clumps[index] as Array).size()<(decor_rects[index] as Array).size(): decor_clumps[index].append("")
	decor_rects[index].append(rect)
	decor_clumps[index].append(clump)

# The same thing never stands twice in one place: how far apart pieces of a
# family keep, in metres.
const KIN_GAPS := {"crystal":9.0,"flag":9.0,"ribbon":9.0,"pebbles":4.5,"stones":4.5,"block":4.5,"crate":4.5,"mechanism":4.5,"tracks":4.5,"hanging":3.5,"climb":3.5,"insects":6.0}
var decor_kin: Dictionary = {}

func _kin_near(index: int, family: String, point: Vector2) -> bool:
	var reach := float(KIN_GAPS.get(family,2.2))
	for band in [index-1,index,index+1]:
		for other: Array in decor_kin.get(band,[]):
			if other[0]==family and (other[1] as Vector2).distance_to(point)<reach: return true
	return false

func _take_kin(index: int, family: String, point: Vector2) -> void:
	if not decor_kin.has(index): decor_kin[index] = []
	decor_kin[index].append([family,point])

# A standing piece needs stone under both sides of its foot, a hanging one
# stone where it hangs from, a climbing one a wall behind it; none may cover
# a grip, find, hazard or rest platform anywhere along its height.
func _decor_fits(rect: Rect2, hanging: bool, climbing: bool = false) -> bool:
	# On the boulder mountain the seat has already settled what holds the piece.
	if not _seats_on_view():
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

# --- Seats ---------------------------------------------------------------------------

# Decor sits by the outline the player sees, not by the contour of a mass: a
# contour's rim runs round a side or a pebble as well as over a top. That is
# the boulder mountain's outline, or a location's own rock where it holds
# objects (the desert); other rock still places its plants by its masks.
func _seats_on_view() -> bool:
	if not (layout is MaskLayout and (layout as MaskLayout).rock_form!="boulder"): return true
	return _seen_rock()!=null

# Clear air kept round a piece, thinner decor on the lighter presets.
func _decor_gap() -> float:
	return {"high":.75,"balanced":.95}.get(quality,1.5)

# The top of the stone seen in a column, walking down from open air: -INF where
# the column starts in stone or meets none within `reach`.
func _ground_under(x: float, from: float, reach: float) -> float:
	if not open_at(Vector2(x,from)): return -INF
	var y := from
	while y>from-reach:
		y -= .1
		if open_at(Vector2(x,y)): continue
		for step in range(3):
			if not open_at(Vector2(x,y+.03)): y += .03
		return y
	return -INF

# The underside of the stone seen in a column, walking up from open air.
func _ceiling_over(x: float, from: float, reach: float) -> float:
	if not open_at(Vector2(x,from)): return INF
	var y := from
	while y<from+reach:
		y += .1
		if open_at(Vector2(x,y)): continue
		for step in range(3):
			if not open_at(Vector2(x,y-.03)): y -= .03
		return y
	return INF

# The foot of a piece standing on the top near `at`, or INF. Its `foot` wide
# footing lies on stone with open air over it and no step in it; the rock it
# stands on is `host` wide just under the foot and `thick` deep, so a large
# piece never perches on a pebble. The foot sits a little into the stone.
func _top_seat(at: Vector2, foot: float, host: float, thick: float, rise: float) -> Vector2:
	var low := INF
	var high := -INF
	for column in range(7):
		var top := _ground_under(at.x+foot*(column/6.0-.5),at.y+.3,.9)
		if top==-INF: return Vector2.INF
		low = minf(low,top)
		high = maxf(high,top)
	if high-low>rise: return Vector2.INF
	for side in [-.5,.5]:
		if open_at(Vector2(at.x+host*side,low-.35)): return Vector2.INF
	for share in [.25,.6,1.0]:
		if open_at(Vector2(at.x,low-thick*share)): return Vector2.INF
	return Vector2(at.x,low-.06)

# The root of a piece hanging under the stone near `at`, or INF: a real
# overhang over it, open air all down its length.
func _hang_seat(at: Vector2, size: Vector2) -> Vector2:
	var root := -INF
	var lowest := INF
	for offset in [-.2,0.0,.2]:
		var ceiling := _ceiling_over(at.x+offset,at.y-.4,1.0)
		if ceiling==INF: return Vector2.INF
		root = maxf(root,ceiling)
		lowest = minf(lowest,ceiling)
	if root-lowest>.3: return Vector2.INF
	for side in [-.6,.6]:
		if open_at(Vector2(at.x+side,root+.3)): return Vector2.INF
	if open_at(Vector2(at.x,root+.7)): return Vector2.INF
	for share in [.25,.5,.75,1.0]:
		for side in [-.3,.3]:
			if not open_at(Vector2(at.x+size.x*side,lowest-size.y*share)): return Vector2.INF
	return Vector2(at.x,root+.06)

# A vine climbs from the crack where its stone rests on another, and all of it
# lies on the wall: none hangs its foot in the air.
func _climb_seat(foot: Vector2, size: Vector2) -> Vector2:
	if open_at(foot-Vector2(0,.3)): return Vector2.INF
	for share in [.1,.4,.7,1.0]:
		for side in [-.3,.3]:
			if open_at(foot+Vector2(size.x*side,size.y*share)): return Vector2.INF
	return foot

# Every top and underside of the outline in a band, as decor candidates: the
# whole face offers its spots, whatever mass makes them.
func _outline_spots(index: int, random: RandomNumberGenerator, parent: Node3D, candidates: Array) -> void:
	var x := -24.0
	while x<24.0:
		if not await pause(parent): return
		var column := x+random.randf_range(0,.45)
		var open := open_at(Vector2(column,index*BAND))
		var y := float(index*BAND)
		while y<(index+1)*BAND:
			y += .2
			var here := open_at(Vector2(column,y))
			if here!=open:
				var edge := Vector2(column,y-.1)
				if here:
					var roll := random.randf()
					candidates.append([null,edge,"grass" if roll<.6 else "pebbles" if roll<.85 else "crystal",edge,1.6])
				else:
					candidates.append([null,edge,"hanging",edge,1.6,edge])
			open = here
		x += .6

# Where a piece of decor goes near a rim of its mass.
func _decor_seat(kind: String, rim: Vector2, foot: Vector2, size: Vector2, hangs: bool) -> Vector2:
	if hangs: return _hang_seat(rim,size)
	if kind=="climb": return _climb_seat(foot,size)
	var width := clampf(size.x*.45,.25,.8)
	return _top_seat(rim,width,maxf(size.x*.8,minf(size.y*.5,2.2)),clampf(size.y*.6,.6,2.4),maxf(.25,width*.35))

# A landmark's seat: under its main piece, or under both poles of a gate, which
# may stand on two stones at different heights.
func _landmark_seat(top: Vector2, family: String) -> Vector2:
	var legs := LandmarkVisuals.family_legs(family)
	if legs.is_empty():
		var height := LandmarkVisuals.family_height(family)
		return _top_seat(top,.7,1.4,clampf(height*.4,1.0,2.0),.4)
	var low := INF
	var high := -INF
	for leg: float in legs:
		var ground := _ground_under(top.x+leg,top.y+1.0,2.0)
		if ground==-INF: return Vector2.INF
		var seat := _top_seat(Vector2(top.x+leg,ground),.3,.6,.7,.35)
		if not seat.is_finite(): return Vector2.INF
		low = minf(low,seat.y)
		high = maxf(high,seat.y)
	return Vector2(top.x,low) if high-low<.9 else Vector2.INF

# The height, on a landmark's holder, of the stone `offset` metres from its
# centre: what stands beside the main piece stands on real stone. `fallback`
# on a location's own rock; NAN where no stone takes it.
func ground_beside(holder: Node3D, offset: float, fallback: float) -> float:
	if not _seats_on_view(): return fallback
	var at := Vector2(holder.position.x+offset,holder.position.y)
	var seat := _top_seat(at+Vector2(0,.6),.3,.6,.6,.3)
	return seat.y-at.y if seat.is_finite() else NAN

# The nearest top round `at` that takes a landmark and passes `clear`.
func _landmark_spot(at: Vector2, family: String, reach: float, clear: Callable, index: int) -> Vector2:
	var height := LandmarkVisuals.family_height(family)
	var tops: Array = []
	for column in range(-int(reach/.4),int(reach/.4)+1):
		var x := at.x+column*.4
		var y := at.y+reach*.8
		while y>at.y-reach*.8:
			var top := _ground_under(x,y,reach*1.2)
			if top==-INF:
				y -= .4
				continue
			tops.append(Vector2(x,top))
			y = top-.4
	tops.sort_custom(func(a: Vector2, b: Vector2) -> bool: return a.distance_squared_to(at)<b.distance_squared_to(at))
	for top: Vector2 in tops:
		var seat := _landmark_seat(top,family)
		if not seat.is_finite() or _taken(index,_landmark_rect(seat,family).grow(1.6)): continue
		if clear.call(seat,height): return seat
	return Vector2.INF

# Stands a landmark on its seat, in front of every stone it covers. A tree's
# root flare is wider than a boulder's crown: it grows from behind the stone at
# its foot, which hides the roots.
func _stand_landmark(index: int, holder: Node3D, family: String, seat: Vector2, random: RandomNumberGenerator) -> void:
	var rect := _landmark_rect(seat,family)
	var rooted: bool = family in LandmarkVisuals.TREES
	holder.position = Vector3(seat.x,seat.y-(.28 if rooted else 0.0),_front_over(rect.grow_individual(0,0,0,-.5) if rooted else rect)+.05)
	LandmarkVisuals.build_family(self,family,holder,random,quality!="battery")
	_take(index,rect.grow(.8))

# Where the summit mast stands: on the top nearest its place by the last grip.
func summit_foot(near: Vector2) -> Vector2:
	if not _seats_on_view(): return near
	var seat := _landmark_spot(near,"signal_flags",4.0,func(_a: Vector2, _b: float) -> bool: return true,int(floor(near.y/BAND)))
	return seat if seat.is_finite() else near

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
	var seated := _seats_on_view()
	var gap := _decor_gap() if seated else .06
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
			var spots := clampi(int(span/.7),1,4) if seated else clampi(int(span/1.2),1,3)
			for spot in range(spots):
				var t := (spot+random.randf_range(.25,.75))/spots
				var rim: Vector2 = mass.outer_contour[i].lerp(mass.outer_contour[j],t)
				var ring: Vector2 = mass.inner_contour[i].lerp(mass.inner_contour[j],t)
				if mass.top_edges.has(i):
					if seated: continue
					var roll := random.randf()
					candidates.append([mass,rim.lerp(ring,.4),"grass" if roll<.6 else "pebbles" if roll<.85 else "crystal",rim,span/spots])
				elif mass.bottom_edges.has(i) and mass.role!="shelf":
					# Over open space an underside carries hanging vines; where the
					# mass rests on another, a climbing vine roots in the seam and
					# goes up its face.
					var below := open_at(rim+(rim-ring).normalized()*.4)
					if seated and below: continue
					candidates.append([mass,rim.lerp(ring,.1),"hanging" if below else "climb",rim,span/spots,ring])
	if seated:
		await _outline_spots(index,random,parent,candidates)
		if not is_instance_valid(parent): return
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
		var hit := _on_face(mass,point) if mass!=null else surface_query(point+Vector2(0,.3 if kind=="hanging" else -.3))
		if hit==null or not hit.valid(): continue
		var outward := (rim-point).normalized()
		if mass!=null and kind!="climb" and not open_at(rim+outward*.4): continue
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
		else:
			# Act props choose their final sprite inside ActProps.build(). Reserve
			# the full visual envelope here, before the prop is instantiated, so a
			# bush/leaf cluster cannot overlap a nearby find or another plant.
			size = Vector2(1.4,1.7)
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
		var family := prop if not prop.is_empty() else kind
		if seated:
			if _taken(index,rect.grow(gap)) or _kin_near(index,family,rim): continue
			anchor = _decor_seat(kind,rim,anchor,size,hangs)
			if not anchor.is_finite(): continue
			rect.position = Vector2(anchor.x-size.x*.5,anchor.y-size.y if hangs else anchor.y)
		if _taken(index,rect.grow(gap)) or not _decor_fits(rect,hangs,climbs): continue
		# The desert's groups are clumps of several plants: what stands round
		# them keeps the room the audit asks for.
		if layout is MaskLayout and (layout as MaskLayout).rock_form=="desert" and _would_crowd(index,rect.get_center()): continue
		if kind=="crystal": crystals += 1
		if kind=="hanging": hanging += 1
		if kind=="climb": climbing += 1
		var holder := Node3D.new()
		holder.name = "Декор_%d" % placed
		parent.add_child(holder)
		# In front of every stone the piece covers, never inside one. A vine
		# stays behind the stone at its foot.
		var covered := rect.grow_individual(0,0,0,-.35) if seated and climbs else rect
		holder.position = Vector3(anchor.x,anchor.y,maxf(hit.position.z,_front_over(covered))+.03)
		if not prop.is_empty(): ActProps.build(self,prop,holder,random,profile,detail)
		else: FloraModels.plant(holder,entry,quality!="battery",scale)
		_take(index,rect)
		if seated: _take_kin(index,family,anchor)
		placed += 1

# --- Summer places (docs/SUMMER_LEVEL_PLAN.md, stage 4) -----------------------------

# Every summer island is a place: a tree, flags, bushes or a waterfall on top
# and a vine under it; big trees also stand on the hills of the foot
# (MaskLayout.summer_places).
func _build_summer_places(index: int, parent: Node3D) -> void:
	var random := layout.rng(index,979)
	var count := 0
	for place: Dictionary in (layout as MaskLayout).summer_places:
		var at := Vector2(float(place["at"][0]),float(place["at"][1]))
		if int(floor(at.y/BAND))!=index: continue
		if not await pause(parent): return
		var island: Array = place["island"]
		match str(place["kind"]):
			"tree": _summer_piece(index,parent,"pine",at,count,random,island.is_empty())
			"flags": _summer_piece(index,parent,"flag_line",at,count,random,false)
			"bush": _summer_bushes(index,parent,at,count,random)
			"waterfall":
				_summer_waterfall(index,parent,at,island)
				_summer_bushes(index,parent,at,count,random)
		if not island.is_empty(): _summer_vine(index,parent,island,count,random)
		count += 1

func _summer_piece(index: int, parent: Node3D, family: String, at: Vector2, count: int, random: RandomNumberGenerator, roomy: bool) -> void:
	var seat := _landmark_spot(at,family,4.0,_landmark_clear,index)
	# A crowded hill of the foot: the nearest top that keeps an act landmark's
	# clearance. An island keeps its piece on itself or goes without.
	if not seat.is_finite() and roomy: seat = _landmark_spot(at,family,5.5,_mark_clear,index)
	if not seat.is_finite(): return
	var stand := Node3D.new()
	stand.name = "Крупный элемент_место_%d" % count
	parent.add_child(stand)
	_stand_landmark(index,stand,family,seat,random)
	if family in LandmarkVisuals.TREES: _summer_butterflies(parent,Vector3(seat.x,seat.y+3.2,stand.position.z+.6))

func _summer_bushes(index: int, parent: Node3D, at: Vector2, count: int, random: RandomNumberGenerator) -> void:
	var profile := profile_at(at.y)
	for bush in range(3):
		var entry := FloraModels.pick("bush",random) if bush==0 else FloraModels.pick_top(profile,random)
		if entry.is_empty(): continue
		var size := FloraModels.size_of(entry,1.0)
		var rim := at+Vector2((bush-1)*1.1+random.randf_range(-.3,.3),.6)
		var seat := _decor_seat("grass",rim,rim,size,false)
		if not seat.is_finite() or not _decor_route_clear(seat,1.2) or _decor_blocked(seat,.4): continue
		var rect := Rect2(seat.x-size.x*.5,seat.y,size.x,size.y)
		if _taken(index,rect.grow(.1)) or not _decor_fits(rect,false,false): continue
		var holder := Node3D.new()
		holder.name = "Декор_место_%d_%d" % [count,bush]
		parent.add_child(holder)
		holder.position = Vector3(seat.x,seat.y,_front_over(rect)+.03)
		FloraModels.plant(holder,entry,quality!="battery",1.0)
		_take(index,rect)

# A vine hanging from the island's underside, over open air.
func _summer_vine(index: int, parent: Node3D, island: Array, count: int, random: RandomNumberGenerator) -> void:
	var entry := FloraModels.pick_hanging(profile_at(float(island[2])),random)
	if entry.is_empty(): return
	var size := FloraModels.size_of(entry,1.0)
	var middle := (float(island[0])+float(island[1]))*.5
	for attempt in range(5):
		var x := middle+random.randf_range(-1.2,1.2)
		var under := _ceiling_over(x,float(island[2])-1.5,3.0)
		if under==INF: continue
		var anchor := _hang_seat(Vector2(x,under-.5),size)
		if not anchor.is_finite(): continue
		var rect := Rect2(anchor.x-size.x*.5,anchor.y-size.y,size.x,size.y)
		if _taken(index,rect.grow(.1)) or not _decor_fits(rect,true,false): continue
		var holder := Node3D.new()
		holder.name = "Декор_лоза_%d" % count
		parent.add_child(holder)
		holder.position = Vector3(anchor.x,anchor.y,_front_over(rect)+.03)
		FloraModels.plant(holder,entry,quality!="battery",1.0)
		_take(index,rect)
		return

# A root grip is a root of the mountain (docs/SUMMER_LEVEL_PLAN.md, stage 6):
# a hanging root trails down from under it, behind the grip and on the stone,
# so what holds the hero and what grows there look the same.
func _summer_root_vines(index: int, parent: Node3D) -> void:
	var random := layout.rng(index,981)
	for id in layout.nearby_ids(index*BAND,(index+1)*BAND):
		var grip: Dictionary = layout.anchors[id]
		if GripSpec.kind_of(grip)!=GripSpec.ROOT: continue
		var at: Vector2 = grip["pos"]
		if int(floor(at.y/BAND))!=index: continue
		var entry := FloraModels.pick("vine_root",random,"hang")
		if entry.is_empty(): continue
		var size := FloraModels.size_of(entry,.85)
		var dims: Vector2 = grip.get("dimensions",Vector2(1.6,.65))
		var anchor := Vector2(at.x+random.randf_range(-.2,.2),at.y-dims.y*.35)
		var rect := Rect2(anchor.x-size.x*.5,anchor.y-size.y,size.x,size.y)
		# All of it on stone: a root does not dangle into the sky.
		var on_stone := true
		for share in [.3,.6,.95]:
			if open_at(Vector2(anchor.x,anchor.y-size.y*share)): on_stone = false
		if not on_stone or _taken(index,rect): continue
		var holder := Node3D.new()
		holder.name = "Декор_корень_%d" % id
		parent.add_child(holder)
		holder.position = Vector3(anchor.x,anchor.y,_front_over(rect)+.03)
		FloraModels.plant(holder,entry,quality!="battery",.85)
		_take(index,rect)

# Water pours over the outer edge of an island and falls into the haze below.
const WATERFALL_FALL := 9.0
static var waterfall_shader: Shader

func _summer_waterfall(index: int, parent: Node3D, at: Vector2, island: Array) -> void:
	var middle := (float(island[0])+float(island[1]))*.5
	var side := signf(middle-_route_x(at.y)) if absf(middle-_route_x(at.y))>.5 else 1.0
	var edge := at.x
	while not open_at(Vector2(edge+side*.25,at.y-.4)) and absf(edge-at.x)<6.0: edge += side*.25
	var x := edge-side*.45
	var top := _ground_under(x,at.y+1.5,3.0)
	if top==-INF: return
	var bottom := float(island[2])-WATERFALL_FALL
	var rect := Rect2(x-.45,bottom,.9,top-bottom)
	var shape := QuadMesh.new()
	shape.size = Vector2(.9,top-bottom)
	if waterfall_shader==null:
		waterfall_shader = Shader.new()
		waterfall_shader.code = WATERFALL_CODE
	var material := ShaderMaterial.new()
	material.shader = waterfall_shader
	material.set_shader_parameter("length_units",top-bottom)
	var water := MeshInstance3D.new()
	water.name = "Водопад"
	water.mesh = shape
	water.material_override = material
	water.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	water.position = Vector3(x,(top+bottom)*.5,_front_over(Rect2(x-.45,top-3.0,.9,3.0))+.06)
	parent.add_child(water)
	_take(index,rect.grow(.2))

const WATERFALL_CODE := """shader_type spatial; render_mode unshaded, cull_disabled, shadows_disabled, depth_draw_never;
uniform float length_units = 10.0;
void fragment(){
	float y = UV.y*length_units;
	float side = abs(UV.x-.5)*2.0;
	float body = 1.0-smoothstep(.55,1.0,side);
	float flow = fract(y*.42-TIME*1.4+sin(UV.x*19.0)*.25);
	float streak = smoothstep(.0,.12,flow)*(1.0-smoothstep(.35,.7,flow));
	float lip = 1.0-smoothstep(.0,.6,y);
	vec3 water = mix(vec3(.42,.68,.88),vec3(.9,.96,1.0),clamp(streak*.65+lip*.8,0.0,1.0));
	float fade = 1.0-smoothstep(length_units*.5,length_units,y);
	ALBEDO = water;
	ALPHA = body*fade*(.72+.25*streak);
}"""

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

# Act landmarks take the best tops: they carry the climb's story, the pieces on
# the islands only fill the view.
func _build_act_marks(index: int, parent: Node3D) -> void:
	for mark in layout.landmarks:
		var at: Vector2 = mark["pos"]
		if int(floor(at.y/BAND))!=index: continue
		var family := str(mark["family"])
		var seat := _landmark_spot(at,family,12.0,_mark_clear,index)
		# A place with no top for its gate still gets its mast.
		if not seat.is_finite() and family in LandmarkVisuals.GATES:
			family = "signal_flags"
			seat = _landmark_spot(at,family,12.0,_mark_clear,index)
		if not seat.is_finite(): continue
		var stand := Node3D.new()
		stand.name = "Ориентир акта_%s_%d" % [family,roundi(at.y)]
		parent.add_child(stand)
		_stand_landmark(index,stand,family,seat,layout.rng(int(roundf(at.y*10)),978))
		mark["built_at"] = seat

func _build_landmarks(index: int, parent: Node3D) -> void:
	# One large themed piece standing on the top face of a side island.
	front_band(index)
	var budget := 1 if quality=="battery" else 2
	var random := layout.rng(index,977)
	var placed := 0
	if _seats_on_view() and layout.summit_added and absi(int(floor(layout.summit/BAND))-index)<=1:
		var foot := summit_foot(world.summit_flag_point())
		_take(index,Rect2(foot.x-.6,foot.y,3.0,3.4).grow(1.0))
	if _seats_on_view(): _build_act_marks(index,parent)
	if _summer_boulders() and not (layout as MaskLayout).summer_places.is_empty():
		# Summer: the places planned from the mask take the island pieces' part.
		await _build_summer_places(index,parent)
		_summer_root_vines(index,parent)
		return
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
		if _seats_on_view():
			var seat := _landmark_spot(rim,family,5.0,_landmark_clear,index)
			if not seat.is_finite(): continue
			var stand := Node3D.new()
			stand.name = "Крупный элемент_%d" % placed
			parent.add_child(stand)
			_stand_landmark(index,stand,family,seat,random)
			placed += 1
			continue
		if not _landmark_clear(point,LandmarkVisuals.family_height(family)): continue
		if not _landmark_unhidden(point,family,hit.position.z+.05): continue
		var holder := Node3D.new()
		holder.name = "Крупный элемент_%d" % placed
		parent.add_child(holder)
		holder.position = hit.position+Vector3(0,0,.05)
		LandmarkVisuals.build_family(self,family,holder,random,quality!="battery")
		_take(index,_landmark_rect(point,family))
		placed += 1
	if _seats_on_view(): return
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
