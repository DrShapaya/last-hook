class_name LegacyMountainVisuals
extends MassifVisuals

# Locations on generator v4 keep their v4 routes, grips and hazards, but the
# stone behind them is the same rock-mass mountain as the first location:
# trunk, body, islands, overhangs, arches, shelves, distant ranges, decor and
# the same mount contract. Only the layout hooks differ: the route line runs
# through the v4 main route, regions take their landform from the seed, and
# the rock and weathering come from the location's single profile.

const REGION_FORMS := ["buttress","shoulder","overhang","arch"]

func _init(owner_world: Node3D, source: MountainLayout) -> void:
	super._init(owner_world,source)
	var profile := profile_at(0)
	var weather: Dictionary = profile.weathering_rules
	# Weathering of the location's profile replaces the height bands of the
	# first location (forest moss low, snow high).
	for material in [rock_material,stone_material,obstacle_material]:
		material.set_shader_parameter("moss_override",clampf(float(weather["moss"])/.6,0,1))
		material.set_shader_parameter("snow_override",float(weather["snow"]))
		material.set_shader_parameter("dust_amount",float(weather["dust"]))
		material.set_shader_parameter("dust_color",profile.rock_palette["warm"])

func route_x_at(y: float) -> float:
	# The v4 route zigzags between alternating grips: follow it linearly.
	var route := layout.main_route
	if route.is_empty(): return 0.0
	var first: Vector2 = layout.anchors[route[0]]["pos"]
	if y<=first.y: return first.x
	var low := 0
	var high := route.size()-1
	var last: Vector2 = layout.anchors[route[high]]["pos"]
	if y>=last.y: return last.x
	while high-low>1:
		var middle := (low+high)/2
		if float(layout.anchors[route[middle]]["pos"].y)<=y: low = middle
		else: high = middle
	var a: Vector2 = layout.anchors[route[low]]["pos"]
	var b: Vector2 = layout.anchors[route[high]]["pos"]
	return lerpf(a.x,b.x,clampf((y-a.y)/maxf(.01,b.y-a.y),0,1))

func region_form(region: int) -> Dictionary:
	# v4 has no landforms of its own: the seed picks one per region.
	var random := layout.rng(region,310)
	var kind := posmod(region*7+layout.seed_value,REGION_FORMS.size())
	return {"kind":[0,4,1,5][kind],"name":REGION_FORMS[kind],"y":region*MassifLayout.REGION_HEIGHT+9.0,"side":-1 if random.randf()<.5 else 1}

func landmark_zone(point: Vector2) -> int:
	# Set pieces follow the location's style, not the first location's zones.
	match profile_at(point.y).id:
		"desert": return 1
		"sky": return 5
		"snow": return 3
		"ruins": return 2
	return 0
