class_name ActHazards
extends RefCounted

# Runtime of the act hazards a v14 layout placed (see LevelCatalog.HAZARDS).
# Phases come from the run clock only, so a resumed attempt sees the same
# storm window; the one-time collapse is the only stored state.
#   field     wind, storm, gust: drift while the hero is airborne in the zone;
#             a branch pocket only moves the hero who took its branch (held
#             or just left), a main-path storm moves everyone in it
#   contact   cactus, scorpion: a knock while the hazard is active
#   falling   icicle: the hero's weight on its branch grip cracks it ->
#             crack and shadow -> fall on a fixed line
#   collapse  sand bridge: telegraph under the hero, then gone once
# Hazards never touch grip mechanics; a knock releases the hook through the
# ordinary release path in main.

const BODY_RADIUS := .38
var world: Node3D
var layout: MountainLayout
var list: Array[Dictionary] = []
var states: Dictionary = {}

func _init(owner_world: Node3D, source: MountainLayout) -> void:
	world = owner_world
	layout = source
	list = source.hazards

static func cycle(hazard: Dictionary) -> float:
	return float(hazard["calm_time"])+float(hazard["telegraph_time"])+float(hazard["active_time"])

func _state(hazard: Dictionary) -> Dictionary:
	var id: int = hazard["id"]
	if not states.has(id): states[id] = {"triggered":-1.0,"collapsed":false}
	return states[id]

# calm | telegraph | active (| collapsed for a bridge), and how far along.
func phase(hazard: Dictionary, time: float) -> Dictionary:
	var telegraph := float(hazard["telegraph_time"])
	var active := float(hazard["active_time"])
	match str(hazard["kind"]):
		"field", "contact":
			if is_inf(active): return {"name":"active","progress":0.0,"left":INF}
			var t := fposmod(time+float(hazard["phase"]),cycle(hazard))
			var calm := float(hazard["calm_time"])
			if t<calm: return {"name":"calm","progress":t/calm,"left":calm-t}
			if t<calm+telegraph: return {"name":"telegraph","progress":(t-calm)/telegraph,"left":calm+telegraph-t}
			return {"name":"active","progress":(t-calm-telegraph)/active,"left":cycle(hazard)-t}
		"falling":
			var triggered := float(_state(hazard)["triggered"])
			if triggered<0 or time<triggered: return {"name":"calm","progress":0.0,"left":INF}
			var t := time-triggered
			if t<telegraph: return {"name":"telegraph","progress":t/telegraph,"left":telegraph-t}
			if t<telegraph+active: return {"name":"active","progress":(t-telegraph)/active,"left":telegraph+active-t}
			return {"name":"regrow","progress":clampf((t-telegraph-active)/float(hazard["calm_time"]),0,1),"left":telegraph+active+float(hazard["calm_time"])-t}
		"collapse":
			var state := _state(hazard)
			if bool(state["collapsed"]): return {"name":"collapsed","progress":1.0,"left":INF}
			var triggered := float(state["triggered"])
			if triggered<0: return {"name":"calm","progress":0.0,"left":INF}
			return {"name":"telegraph","progress":clampf((time-triggered)/telegraph,0,1),"left":maxf(0,triggered+telegraph-time)}
	return {"name":"calm","progress":0.0,"left":INF}

func _near(hazard: Dictionary, point: Vector2, reach: float) -> bool:
	if hazard.has("rect"): return (hazard["rect"] as Rect2).grow(reach).has_point(point)
	if hazard.has("pos"): return (hazard["pos"] as Vector2).distance_to(point)<reach+float(hazard.get("radius",0))
	if hazard.has("trigger"): return (hazard["trigger"] as Rect2).grow(reach).has_point(point)
	if hazard["kind"]=="collapse":
		var ledge: Dictionary = layout.ledges[int(hazard["ledge"])]
		return point.x>float(ledge["left"])-reach and point.x<float(ledge["right"])+reach and absf(point.y-float(ledge["top"]))<reach+1.0
	return false

# Height of a falling icicle's tip while active.
func icicle_tip(hazard: Dictionary, time: float) -> float:
	var now := phase(hazard,time)
	if now["name"]!="active": return float(hazard["top"])
	return lerpf(float(hazard["top"])-.4,float(hazard["bottom"]),float(now["progress"]))

# One physics step. Returns the drift to add, a knock (empty when none) and
# the bridges that collapsed now.
func step(time: float, hero: Vector2, grounded: bool, held_anchor: int = -1, last_anchor: int = -1) -> Dictionary:
	var result := {"force":Vector2.ZERO,"knock":{},"collapsed":[],"haze":0.0}
	for hazard in list:
		var now := phase(hazard,time)
		match str(hazard["kind"]):
			"field":
				var rect: Rect2 = hazard["rect"]
				var branch := int(hazard.get("branch_anchor",-1))
				var takes := bool(hazard.get("affects_main",false)) or (branch>=0 and (held_anchor==branch or last_anchor==branch))
				if now["name"]=="active" and takes and rect.has_point(hero) and not grounded:
					result["force"] += hazard["force"]
				if bool(hazard.get("haze",false)) and rect.grow(4.0).has_point(hero):
					var amount := 1.0 if now["name"]=="active" else float(now["progress"]) if now["name"]=="telegraph" else 0.0
					result["haze"] = maxf(float(result["haze"]),amount)
			"contact":
				if now["name"]=="active" and hero.distance_to(hazard["pos"])<float(hazard["radius"])+BODY_RADIUS and result["knock"].is_empty():
					result["knock"] = {"hazard":hazard["id"],"push":(hero-hazard["pos"]).normalized()*3.2+Vector2(0,-1.0)}
			"falling":
				var state := _state(hazard)
				if now["name"]=="calm" and held_anchor>=0 and held_anchor==int(hazard.get("branch_anchor",-2)):
					state["triggered"] = time
				elif now["name"]=="regrow" and float(now["left"])<=0.0:
					state["triggered"] = -1.0
				if now["name"]=="active" and absf(hero.x-float(hazard["x"]))<float(hazard["radius"])+BODY_RADIUS:
					var tip := icicle_tip(hazard,time)
					if hero.y<tip+.9 and hero.y>tip-1.2 and result["knock"].is_empty():
						result["knock"] = {"hazard":hazard["id"],"push":Vector2(signf(hero.x-float(hazard["x"])) if absf(hero.x-float(hazard["x"]))>.05 else 1.0,-1.6)*2.4}
			"collapse":
				var state := _state(hazard)
				if bool(state["collapsed"]): continue
				var ledge: Dictionary = layout.ledges[int(hazard["ledge"])]
				var on_bridge := grounded and hero.x>float(ledge["left"])-.25 and hero.x<float(ledge["right"])+.25 and absf(hero.y-SolidGeometry.BODY_HALF.y-float(ledge["top"]))<.2
				if float(state["triggered"])<0 and on_bridge: state["triggered"] = time
				elif float(state["triggered"])>=0 and time-float(state["triggered"])>=float(hazard["telegraph_time"]):
					state["collapsed"] = true
					result["collapsed"].append(hazard["id"])
	return result

# A careful player waits on a grip until every cyclic storm covering it is
# calm for `need` seconds. Constant pockets never block waiting.
func calm_for(point: Vector2, time: float, need: float) -> bool:
	for hazard in list:
		if hazard["kind"]!="field" or is_inf(float(hazard["active_time"])): continue
		# A storm over the main path is waited out near it; a branch storm only
		# matters inside its own sector.
		var zone: Rect2 = (hazard["rect"] as Rect2).grow(1.0 if bool(hazard.get("affects_main",false)) else 0.0)
		if not zone.has_point(point): continue
		var now := phase(hazard,time)
		if now["name"]!="calm" or float(now["left"])<need: return false
	return true

func hint(point: Vector2, time: float) -> String:
	for hazard in list:
		if not _near(hazard,point,2.5): continue
		var now := phase(hazard,time)
		match str(hazard["def"]):
			"sand_storm", "storm_cycle":
				if now["name"]=="telegraph": return "Идёт буря — держись за камень"
				if now["name"]=="active": return "Буря сносит в сторону — жди затишья"
			"blizzard_gust":
				if now["name"]=="telegraph": return "Порыв метели!"
			"icicle":
				if now["name"]=="telegraph": return "Сосулька треснула — уйди с линии"
			"sand_bridge":
				if now["name"]=="telegraph": return "Перемычка осыпается — цепляйся выше"
			"wind_pocket":
				return "Ветровой карман: флаги показывают снос"
	return ""

func knock_message(id: int) -> String:
	if id<0 or id>=list.size(): return ""
	match str(list[id]["def"]):
		"cactus": return "Кактус уколол — крюк сорвался"
		"scorpion": return "Скорпион ужалил — крюк сорвался"
		"icicle": return "Сосулька сбила с опоры"
	return "Опасность сбила с опоры"

func collapsed_ids() -> Array:
	var result: Array = []
	for id in states.keys():
		if bool(states[id].get("collapsed",false)): result.append(id)
	result.sort()
	return result

func restore_collapsed(ids: Array) -> void:
	for id in ids:
		if int(id)<0 or int(id)>=list.size(): continue
		_state(list[int(id)])["collapsed"] = true

func debug_near(point: Vector2, time: float) -> Array:
	var result: Array = []
	for hazard in list:
		if _near(hazard,point,6.0): result.append({"id":hazard["id"],"def":hazard["def"],"phase":phase(hazard,time)["name"]})
	return result
