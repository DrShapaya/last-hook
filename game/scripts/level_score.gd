class_name LevelScore
extends RefCounted

# How good a generated level is, as numbers the designer can compare
# (docs/LEVEL_PIPELINE.md, «Что считать интересным»). Hard checks decide
# whether a level may be used at all; the score ranks the ones that may.
#
# Terms, each 0..1 with its weight:
#   level hops   share of hops that travel more across than up (target 25-50%)
#   long hops    mean main-route hop length (4.2+ units reads as a swing, not a step)
#   sparse       visible grips per 10 units of height (6 or fewer)
#   splits       ways that really part (one per act)
#   variety      different landforms per section
#   sky          sky in view round the route (19-40%)
#   rhythm       how much the main route's rises differ from hop to hop

const WEIGHTS := {"level_hops":2.0,"long_hops":1.5,"sparse":1.5,"splits":2.0,"variety":1.0,"sky":1.0,"rhythm":1.5}

static func evaluate(layout: MaskLayout, source: LevelSource, sections: Array = []) -> Dictionary:
	var metrics := {}
	var problems: Array = RouteGraph.audit(layout)["problems"]
	var hops: Array[Vector2] = []
	var main_lengths := 0.0
	var rises: Array[float] = []
	for row in range(1,layout.main_route.size()):
		var hop: Vector2 = layout.anchors[layout.main_route[row]]["pos"]-layout.anchors[layout.main_route[row-1]]["pos"]
		hops.append(hop)
		main_lengths += hop.length()
		rises.append(hop.y)
	for split in layout.splits_built:
		var chain: Array = [split["entry"]]+split["grips"]+[split["exit"]]
		for k in range(1,chain.size()): hops.append(layout.anchors[chain[k]]["pos"]-layout.anchors[chain[k-1]]["pos"])
	var level := 0
	for hop in hops:
		if absf(hop.x)>absf(hop.y): level += 1
	metrics["level_hops"] = float(level)/maxi(1,hops.size())
	metrics["mean_hop"] = main_lengths/maxi(1,layout.main_route.size()-1)
	var visible := 0
	for anchor in layout.anchors:
		if not anchor.get("reserve",false): visible += 1
	metrics["grips_per_10"] = visible*10.0/maxf(1.0,layout.summit)
	metrics["splits"] = layout.splits_built.size()
	metrics["splits_planned"] = source.brief.get("splits",[]).size()
	var forms := {}
	for section in sections: forms[section["form"]] = true
	metrics["variety"] = float(forms.size())/maxi(1,mini(sections.size(),9))
	metrics["sky"] = _sky_share(layout,source)
	var mean_rise := 0.0
	for rise in rises: mean_rise += rise/maxi(1,rises.size())
	var spread := 0.0
	for rise in rises: spread += pow(rise-mean_rise,2)/maxi(1,rises.size())
	metrics["rhythm"] = sqrt(spread)
	var terms := {
		"level_hops":_band(metrics["level_hops"],.25,.5,.15),
		"long_hops":clampf((float(metrics["mean_hop"])-3.6)/.8,0,1),
		"sparse":clampf((8.5-float(metrics["grips_per_10"]))/2.5,0,1),
		"splits":float(metrics["splits"])/maxi(1,int(metrics["splits_planned"])) if int(metrics["splits_planned"])>0 else 0.0,
		"variety":clampf(float(metrics["variety"]),0,1),
		"sky":_band(metrics["sky"],.19,.4,.1),
		"rhythm":clampf((float(metrics["rhythm"])-.3)/.5,0,1)}
	var score := 0.0
	var total := 0.0
	for key in WEIGHTS:
		score += float(terms[key])*float(WEIGHTS[key])
		total += float(WEIGHTS[key])
	var usable: bool = problems.is_empty() and layout.sky_objects==0 and int(metrics["splits"])==int(metrics["splits_planned"])
	return {"usable":usable,"score":snappedf(score/total,.001),"metrics":metrics,"terms":terms,"problems":problems}

# 1 inside [low, high], falling to 0 over `soft` outside it.
static func _band(value: float, low: float, high: float, soft: float) -> float:
	if value<low: return clampf(1.0-(low-value)/soft,0,1)
	if value>high: return clampf(1.0-(value-high)/soft,0,1)
	return 1.0

# Sky in a view-wide window (14 units) round the route, sampled every unit.
static func _sky_share(layout: MaskLayout, source: LevelSource) -> float:
	var sky := 0
	var total := 0
	var y := 6.0
	while y<layout.summit-4.0:
		var center := layout.corridor_at(y).x
		for dx in range(-7,8):
			total += 1
			if source.sample("silhouette",Vector2(center+dx,y))<.5: sky += 1
		y += 1.0
	return float(sky)/maxi(1,total)
