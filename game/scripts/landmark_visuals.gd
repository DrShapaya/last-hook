class_name LandmarkVisuals
extends RefCounted

const FloraModels := preload("res://scripts/flora_models.gd")

# Large themed set pieces on the side islands of the massif, one family per
# zone and the act markers of the expeditions. Every piece is composed of the
# painted sprites and the flag models (FloraModels) in the place's climate:
# trees, big boulders and scree, crystal clusters, bones and cacti, masts and
# strings of flags. Purely visual: they are placed away from the route and
# every gameplay object, under open sky, by MassifVisuals.

const HEIGHTS := [4.8,2.4,2.4,3.4,2.4,2.8]
const ZONE_FAMILIES := ["pine","spire","column","ice_needles","basalt","stele"]
# Acts of v14 bring their own families (LevelCatalog.ACTS[...]["landmarks"]).
const FAMILY_HEIGHTS := {"pine":4.8,"spire":2.4,"column":2.4,"ice_needles":3.4,"basalt":2.4,"stele":2.8,
	"root_bridge":4.8,"root_arch":4.8,"flag_line":2.8,"hanging_frame":3.4,"post_gate":2.8,"signal_flags":3.2,
	"bones":3.3,"cactus_grove":2.0,"wagon":3.3,"sail":3.4,"mirror_mast":3.4,"lens_ring":3.4,
	"snow_pines":4.8,"ice_columns":3.8,"chains":3.4,"tower_ring":2.4,"signal_light":3.4}

static func height_for(zone: int) -> float:
	return HEIGHTS[clampi(zone,0,5)]

static func family_height(family: String) -> float:
	return float(FAMILY_HEIGHTS.get(family,3.0))

static func build(visuals: MassifVisuals, zone: int, holder: Node3D, random: RandomNumberGenerator, shadows: bool) -> void:
	build_family(visuals,ZONE_FAMILIES[clampi(zone,0,5)],holder,random,shadows)

static func build_family(visuals: MassifVisuals, family: String, holder: Node3D, random: RandomNumberGenerator, shadows: bool) -> void:
	var profile := visuals.profile_at(holder.position.y)
	match family:
		"pine", "root_bridge", "root_arch": _tree(holder,random,profile,shadows)
		"snow_pines": _snow_pines(holder,random,shadows)
		"spire", "column", "basalt", "tower_ring": _outcrop(visuals,holder,random,profile,shadows)
		"ice_needles", "ice_columns", "chains", "lens_ring": _crystals(holder,random,profile,shadows)
		"stele", "flag_line", "post_gate": _flag_gate(holder,random,shadows)
		"hanging_frame", "mirror_mast", "sail", "signal_light": _signal_mast(holder,random,shadows,family)
		"signal_flags": _signal_flags(holder,random,profile,shadows)
		"bones", "wagon": _bones(holder,random,shadows)
		"cactus_grove": _cactus_grove(holder,random,shadows)
		_: _flag_gate(holder,random,shadows)

# A sprite on a child of the holder at `at`, its foot there.
static func _sprite(holder: Node3D, item: Array, at: Vector3, shadows: bool, scale: float = 1.0) -> void:
	if item.is_empty(): return
	var node := Node3D.new()
	node.position = at
	holder.add_child(node)
	FloraModels.plant(node,item,shadows,scale)

static func _side(random: RandomNumberGenerator) -> float:
	return 1.0 if random.randf()<.5 else -1.0

# --- Families -----------------------------------------------------------------------

# The place's own tree - leafy, snowy or dead - with a plant at its foot.
static func _tree(holder: Node3D, random: RandomNumberGenerator, profile: GripBiomeProfile, shadows: bool) -> void:
	_sprite(holder,FloraModels.pick_tree(profile,random),Vector3.ZERO,shadows)
	_sprite(holder,FloraModels.pick_top(profile,random),Vector3(random.randf_range(.5,.7)*_side(random),-.04,.1),shadows)

# A snowy fir, now and then with a younger one beside it.
static func _snow_pines(holder: Node3D, random: RandomNumberGenerator, shadows: bool) -> void:
	_sprite(holder,FloraModels.pick("tree_snow",random),Vector3.ZERO,shadows)
	if random.randf()<.5: _sprite(holder,FloraModels.pick("tree_snow",random),Vector3(random.randf_range(.55,.75)*_side(random),-.04,.08),shadows,.55)

# A big boulder of the place with scree at its foot and, on the cliffs, a
# crystal grown beside it.
static func _outcrop(visuals: MassifVisuals, holder: Node3D, random: RandomNumberGenerator, profile: GripBiomeProfile, shadows: bool) -> void:
	var kinds: Array = FloraModels.STONES[FloraModels.climate(profile)]
	_sprite(holder,FloraModels.pick(kinds[0],random),Vector3.ZERO,shadows,2.3)
	var side := _side(random)
	_sprite(holder,FloraModels.pick(kinds[1],random),Vector3(side*random.randf_range(.75,.95),-.04,.12),shadows,1.1)
	if random.randf()<.6:
		var crystal := Node3D.new()
		crystal.position = Vector3(-side*random.randf_range(.8,1.0),-.04,.1)
		holder.add_child(crystal)
		visuals._crystal_sprite(crystal,random,profile,shadows,1.0)

# A large crystal cluster of the place's kind - ice, quartz or amber - and a
# smaller one in front of it.
static func _crystals(holder: Node3D, random: RandomNumberGenerator, profile: GripBiomeProfile, shadows: bool) -> void:
	_sprite(holder,FloraModels.pick_crystal(profile,random),Vector3.ZERO,shadows,2.4)
	_sprite(holder,FloraModels.pick_crystal(profile,random),Vector3(random.randf_range(.65,.85)*_side(random),-.04,.12),shadows,1.05)

# Two masts with a string of flags between their tops: a gate of the post, a
# wind line or the flags of a stele.
static func _flag_gate(holder: Node3D, random: RandomNumberGenerator, shadows: bool) -> void:
	var span := random.randf_range(1.0,1.25)
	var colours := FloraModels.COLORS
	for side in [-1.0,1.0]:
		FloraModels.flag(holder,"mast",colours[random.randi_range(0,colours.size()-1)],Vector3(side*span,-.05,.05),2.4,side,shadows)
	FloraModels.flag_string(holder,Vector3(-span,2.25,.12),Vector3(span,2.25,.12),5,.3,random.randi(),shadows)

# A high mast with its pennant and a short flag beside it, a string of flags
# between them: a wind gauge, a mirror mast, a sail or a signal.
static func _signal_mast(holder: Node3D, random: RandomNumberGenerator, shadows: bool, family: String) -> void:
	var colour: String = {"sail":"white","signal_light":"orange","mirror_mast":"yellow"}.get(family,"red")
	var side := _side(random)
	FloraModels.flag(holder,FloraModels.HIGH_MASTS[random.randi_range(0,1)],colour,Vector3(0,-.05,.05),3.2,side,shadows)
	var short := Vector3(-side*random.randf_range(1.2,1.5),-.05,.1)
	FloraModels.flag(holder,FloraModels.SMALL_FLAGS[random.randi_range(0,2)],FloraModels.COLORS[random.randi_range(0,FloraModels.COLORS.size()-1)],short,1.0,-side,shadows)
	FloraModels.flag_string(holder,Vector3(0,2.6,.12),short+Vector3(0,.9,.02),4,.15,random.randi(),shadows)

# A tall signal mast in a cairn of the place's stones, a small flag beside it.
static func _signal_flags(holder: Node3D, random: RandomNumberGenerator, profile: GripBiomeProfile, shadows: bool) -> void:
	var side := _side(random)
	FloraModels.flag(holder,FloraModels.HIGH_MASTS[random.randi_range(0,1)],["red","yellow","orange"][random.randi_range(0,2)],Vector3(0,-.05,.05),2.9,side,shadows)
	var kinds: Array = FloraModels.STONES[FloraModels.climate(profile)]
	_sprite(holder,FloraModels.pick(kinds[1],random),Vector3(0,-.06,.14),shadows,.9)
	FloraModels.flag(holder,FloraModels.SMALL_FLAGS[random.randi_range(0,2)],"white",Vector3(-side*.6,-.05,.18),1.0,-side,shadows)

# A dead tree over the bleached skulls of large animals.
static func _bones(holder: Node3D, random: RandomNumberGenerator, shadows: bool) -> void:
	_sprite(holder,FloraModels.pick("tree_dead",random),Vector3(random.randf_range(-.2,.2),-.05,.02),shadows,.78)
	for index in range(2):
		_sprite(holder,FloraModels.pick("skull",random),Vector3((index*2-1)*random.randf_range(.45,.6),-.05,.12+index*.04),shadows)

# Three cacti of different kinds, the tallest in the middle.
static func _cactus_grove(holder: Node3D, random: RandomNumberGenerator, shadows: bool) -> void:
	for index in range(3):
		_sprite(holder,FloraModels.pick_cactus(random),Vector3((index-1)*.55+random.randf_range(-.08,.08),-.05,.05+(1-absi(index-1))*.06),shadows,1.25 if index==1 else 1.0)

# --- Shared faceted helper (hazard posts) -------------------------------------------

static func _shade(color: Color, facing: float) -> Color:
	# Faceted art light: faces turned to the upper-left sun are lighter.
	return color.lightened(.16*facing) if facing>0 else color.darkened(-.24*facing)

static func _prism(points: PackedVector3Array, colors: PackedColorArray, base: Vector3, axis: Vector3, bottom: float, top: float, height: float, sides: int, color: Color, cap: bool = true, turn: float = 0.0) -> void:
	# A tapered faceted prism along axis; top radius 0 makes a cone.
	var side := Vector3(axis.y,-axis.x,0).normalized()
	var depth := Vector3(0,0,1)
	var tip := base+axis*height
	for i in range(sides):
		var a0 := turn+TAU*i/sides
		var a1 := turn+TAU*(i+1)/sides
		var d0 := side*cos(a0)+depth*sin(a0)
		var d1 := side*cos(a1)+depth*sin(a1)
		var facing := -(cos(a0)+cos(a1))*.5*.8+(sin(a0)+sin(a1))*.5*.3
		var face := _shade(color,facing)
		var b0 := base+d0*bottom
		var b1 := base+d1*bottom
		if top<=.001:
			points.append_array(PackedVector3Array([b0,tip,b1]))
			colors.append(face)
			continue
		var t0 := tip+d0*top
		var t1 := tip+d1*top
		points.append_array(PackedVector3Array([b0,t0,t1]))
		colors.append(face)
		points.append_array(PackedVector3Array([b0,t1,b1]))
		colors.append(face.darkened(.03))
		if cap:
			points.append_array(PackedVector3Array([t0,tip,t1]))
			colors.append(color.lightened(.12))
