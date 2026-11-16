class_name WeatherBands
extends RefCounted

# Weather of an expedition: one band in act 1 and one in act 2 of every
# three-act cycle. A band cycles calm -> telegraph -> active; the active gust
# pushes sideways. Pure data, no nodes: the world, HUD and visuals ask it.

const KIND_BY_LOCATION := ["wind","sand_storm","blizzard"]
const TUNING := {
	"wind":[
		{"from":.30,"to":.75,"calm":6.0,"telegraph":2.0,"active":6.0,"force":.35},
		{"from":.15,"to":.92,"calm":6.0,"telegraph":2.0,"active":9.0,"force":.5}],
	"sand_storm":[
		{"from":.30,"to":.75,"calm":5.0,"telegraph":2.5,"active":8.0,"force":.25},
		{"from":.15,"to":.92,"calm":5.0,"telegraph":2.5,"active":11.0,"force":.35}],
	"blizzard":[
		{"from":.30,"to":.75,"calm":6.0,"telegraph":2.0,"active":8.0,"force":.3},
		{"from":.15,"to":.92,"calm":5.0,"telegraph":2.0,"active":11.0,"force":.4}],
}
const EDGE := 4.0
const RAMP_IN := .6
const RAMP_OUT := .8
const GRAVITY := 14.0
# Rows above a band that must exist before its fallback campfire is chosen.
const FALLBACK_MARGIN := 8.0

var layout: MountainLayout
var _enabled := false
var _total := 0.0
# Bands by cycle*4+act: a pure function of the layout, built once each.
var _cache := {}

func _init(source: MountainLayout) -> void:
	layout = source
	if source is ExpeditionLayout:
		var spans: Array = (source as ExpeditionLayout).spans
		if spans.size()>=3:
			_total = float(spans[-1]["y_end"])
			_enabled = _total>0.0

func enabled() -> bool:
	return _enabled

# Height of one three-act cycle (0 without weather).
func cycle_height() -> float:
	return _total

# The band of an act index (1 or 2 within a cycle). Shared: callers only read it.
func _band(local: int, cycle: int) -> Dictionary:
	var key := cycle*4+local
	var known: Variant = _cache.get(key)
	if known!=null: return known
	var built := _build_band(local,cycle)
	_cache[key] = built
	return built

func _build_band(local: int, cycle: int) -> Dictionary:
	var expedition := layout as ExpeditionLayout
	var info := expedition.span(local+cycle*expedition.spans.size())
	var kind: String = KIND_BY_LOCATION[posmod(layout.location,KIND_BY_LOCATION.size())]
	var tuning: Dictionary = TUNING[kind][local-1]
	var start := float(info["y_start"])
	var height := float(info["y_end"])-start
	var band_seed := layout.seed_value*7919+local*104729+cycle*49979687+layout.location*86028121
	var cycle_time := float(tuning["calm"])+float(tuning["telegraph"])+float(tuning["active"])
	return {"kind":kind,"act":local,"cycle":cycle,
		"bottom":start+height*float(tuning["from"]),"top":start+height*float(tuning["to"]),
		"calm":float(tuning["calm"]),"telegraph":float(tuning["telegraph"]),"active":float(tuning["active"]),
		"force":float(tuning["force"]),
		"phase_shift":float(posmod(band_seed,100003))/100003.0*cycle_time,"seed":band_seed}

func bands_of_cycle(cycle: int) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	if not _enabled: return result
	result.append(_band(1,cycle))
	result.append(_band(2,cycle))
	return result

func band_at(y: float, margin: float = 0.0) -> Dictionary:
	if not _enabled: return {}
	var cycle := maxi(0,int(floor(y/_total)))
	for c in range(maxi(0,cycle-1),cycle+2):
		for local in [1,2]:
			var band := _band(local,c)
			if y>=float(band["bottom"])-margin and y<=float(band["top"])+margin: return band
	return {}

func _cycle_time(band: Dictionary) -> float:
	return float(band["calm"])+float(band["telegraph"])+float(band["active"])

func phase(band: Dictionary, time: float) -> Dictionary:
	var cycle_time := _cycle_time(band)
	var shifted := time+float(band["phase_shift"])
	var t := fposmod(shifted,cycle_time)
	var gust := int(floor(shifted/cycle_time))
	var calm := float(band["calm"])
	var telegraph := float(band["telegraph"])
	if t<calm: return {"name":"calm","progress":t/calm,"left":calm-t,"gust":gust}
	if t<calm+telegraph: return {"name":"telegraph","progress":(t-calm)/telegraph,"left":calm+telegraph-t,"gust":gust}
	var active := float(band["active"])
	return {"name":"active","progress":(t-calm-telegraph)/active,"left":cycle_time-t,"gust":gust}

func direction(band: Dictionary, gust: int) -> float:
	var mixed: int = (int(band["seed"])+gust*7919+13)*2654435761
	return 1.0 if (mixed>>13)&1==0 else -1.0

# Gust envelope times the breath; zero outside the active phase.
func strength(band: Dictionary, time: float) -> float:
	var info := phase(band,time)
	if info["name"]!="active": return 0.0
	var elapsed := float(band["active"])*float(info["progress"])
	var envelope := smoothstep(0.0,1.0,minf(elapsed/RAMP_IN,1.0))*smoothstep(0.0,1.0,minf(float(info["left"])/RAMP_OUT,1.0))
	var t := fposmod(time+float(band["phase_shift"]),_cycle_time(band))
	var breath := .975+.175*sin(t*2.3+float(posmod(int(band["seed"]),97)))
	return envelope*breath

func wind_at(point: Vector2, time: float) -> Vector2:
	var band := band_at(point.y)
	if band.is_empty(): return Vector2.ZERO
	var info := phase(band,time)
	var amount := strength(band,time)
	if amount<=0.0: return Vector2.ZERO
	return Vector2(direction(band,int(info["gust"]))*float(band["force"])*GRAVITY*amount,0.0)

func presence(point: Vector2, time: float) -> Dictionary:
	var band := band_at(point.y,EDGE)
	if band.is_empty(): return {"kind":""}
	var info := phase(band,time)
	var inside := point.y>=float(band["bottom"]) and point.y<=float(band["top"])
	var distance := maxf(float(band["bottom"])-point.y,point.y-float(band["top"]))
	var fade := 1.0 if inside else clampf(1.0-distance/EDGE,0.0,1.0)
	var amount := 0.0
	if info["name"]=="telegraph": amount = float(info["progress"])*.4
	elif info["name"]=="active": amount = 1.0
	return {"kind":band["kind"],"amount":amount*fade,"phase":info,
		"direction":direction(band,int(info["gust"])),"inside":inside}

func calm_for(point: Vector2, time: float, need: float) -> bool:
	var band := band_at(point.y)
	if band.is_empty(): return true
	var info := phase(band,time)
	return info["name"]=="calm" and float(info["left"])>=need

# Blizzard warming spots: rest ledges of each band of the cycles asked for,
# or the ledge nearest the middle of the band when it has none. A summit climb
# has one cycle. That nearest ledge is only chosen once the layout is laid out
# past the band (generated_top), so it cannot change later.
func campfires(first_cycle: int = 0, last_cycle: int = 0, generated_top: float = INF) -> Array[Vector2]:
	var result: Array[Vector2] = []
	if not _enabled or layout.location!=2: return result
	if layout.finite: last_cycle = mini(last_cycle,0)
	for cycle in range(maxi(0,first_cycle),last_cycle+1):
		for local in [1,2]:
			_band_fires(_band(local,cycle),generated_top,result)
	return result

func _band_fires(band: Dictionary, generated_top: float, result: Array[Vector2]) -> void:
	var bottom := float(band["bottom"])
	var top := float(band["top"])
	var found := false
	for ledge in layout.ledges:
		var y := float(ledge["top"])
		if str(ledge.get("role",""))=="rest" and y>=bottom-2.0 and y<=top+2.0:
			result.append(Vector2((float(ledge["left"])+float(ledge["right"]))*.5,y))
			found = true
	if found or generated_top<top+FALLBACK_MARGIN: return
	var middle := (bottom+top)*.5
	var best := {}
	for ledge in layout.ledges:
		if best.is_empty() or absf(float(ledge["top"])-middle)<absf(float(best["top"])-middle): best = ledge
	if not best.is_empty(): result.append(Vector2((float(best["left"])+float(best["right"]))*.5,float(best["top"])))
