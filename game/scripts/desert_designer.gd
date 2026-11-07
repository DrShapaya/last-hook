class_name DesertDesigner
extends LevelDesigner

# The canyon's level masks, after references/location/desert_4k.png: wide
# rounded ledges stacked over pinched walls, arches and windows through them,
# pillars with caps, lenses of rock hanging off the sides. Each act sweeps
# from side to side across its benches.

const LEDGE_HALF := Vector2(13.0,17.0)
const WALL_HALF := Vector2(6.0,9.0)
# Share of a tier that melts into its neighbour, and the units a split takes
# to grow out of the ordinary canyon.
const TIER_MELT := .3
# A ledge's top meets the wall above it in a short round, not a long slope,
# so it reads as a flat bench.
const TOP_MELT := .1
# Thickness of a ledge: two to three heights of the hero, as on desertClose.png.
const LEDGE_THICK := Vector2(3.2,5.2)
const SPLIT_MELT := 5.0
# How deep a split's sky counts when it grows out of the canyon.
const SPLIT_SKY := 3.0
# How far a border between tiers leans: a unit up over this many across.
const BORDER_TILT := .14
# Height of the broad tumble of rock the canyon stands on.
const FOOT_TOP := 10.0
# Half width of a split's main ridge, and the height of the blocks it is built of.
const SPLIT_RIDGE := 3.6
const SPLIT_BLOCK := 4.0
# Pixels of the mask the outline is worn over: eight make a unit.
const OUTLINE_WEAR := 6
# Rock left at each side of a window or gate, so the wall above never hangs
# on a thin strip.
const JAMB := 4.5
# How far in a wall narrows at its waist (see _tier_outline), how far its
# blocks pinch where they meet, and how far one stands off the next.
const WAIST := 2.4
const BLOCK_PINCH := 1.8
const BLOCK_SHIFT := 2.2
# The gap of sky between a wall and a leg standing beside it.
const LEG_GAP := Vector2(2.0,3.2)
# The summit: a flat mesa this many units deep, a spire on one side of it.
const MESA_DEPTH := 9.0
const MESA_HALF := Vector2(5.5,7.0)
const SPIRE_RISE := 4.2
# Gates stand above the broad foot of the canyon.
const GATE_FLOOR := 16.0
# A gate's foot and lintel, in shares of its wall from the wall's foot.
const GATE_SPAN := Vector2(.1,.82)
# A great gate: half its width and height, its sill over its wall's foot, and
# the rock over it. It is at least GATE_HALF wide (half), unlike a window.
const GATE_WIDE := Vector2(2.6,3.4)
const GATE_TALL := Vector2(5.0,6.5)
const GATE_FOOT := 1.0
const GATE_HALF := 2.5
const LINTEL := 2.5

# Bottom-up: [y0, y1, half, center, kind, skew, blocks]; kind 0 a wall, 1 a
# ledge. A positive skew moves both edges right, so no tier sits square on the
# last. A tall wall is built of blocks set one on another, each a little off
# the one under it, pinched where they meet.
var tiers: Array = []
# Rocks hanging under the ledges: [x, y, half, tall].
var drops: Array = []
# Standing pillars: [x, y0, y1, half, phase].
var pillars: Array = []
# Windows and gates of sky, arches with a flat lintel and straight sides:
# [center, half sizes].
var windows: Array = []
# Round stones on the benches, alone or one on another: [x, y, radius].
var boulders: Array = []
# Slots of sky between a leg and its wall, so the leg stands apart: Rect2.
var slits: Array = []

func _forms_of(beat: String) -> Array:
	if beat=="teach": return ["wall","islands"]
	if beat=="combo": return ["traverse","islands"]
	return super._forms_of(beat)

func _split_shapes() -> Array:
	return ["butte","ledge","stones"]

func _sway_scale() -> float:
	return 1.2

func _split_risk() -> String:
	return "sand_storm"

func _finish_of(form: String, center: float, finish: float, _span: float) -> float:
	if form=="neck": return finish
	return (-signf(center) if absf(center)>.5 else 1.0)*random.randf_range(3.5,7.5)

func _after_plan() -> void:
	tiers.clear()
	pillars.clear()
	windows.clear()
	drops.clear()
	# A split's main ridge is a narrow column, so sky shows round it.
	for split in splits: split["ridge"] = SPLIT_RIDGE
	var stretches := _plain_stretches()
	var gated := {}
	var y := -2.0
	var ledge := false
	while y<height+8.0:
		var thick := random.randf_range(LEDGE_THICK.x,LEDGE_THICK.y) if ledge else random.randf_range(7.0,14.0)
		if not ledge:
			# The first wall of each stretch of plain canyon that has room is
			# tall enough to hold its gate.
			for stretch in range(0,stretches.size(),2):
				var tall := minf(random.randf_range(10.5,13.0),(float(stretches[stretch+1])-y)/GATE_SPAN.y)
				if gated.has(stretch) or tall<9.5 or y+tall*GATE_SPAN.x<float(stretches[stretch]): continue
				thick = maxf(thick,tall)
				gated[stretch] = true
		var range_half := LEDGE_HALF if ledge else WALL_HALF
		var half := random.randf_range(range_half.x,range_half.y)
		if y>height-14.0: half = minf(half,8.0)
		var center := clampf(corridor_center(minf(y+thick*.5,height))*.6+random.randf_range(-2.5,2.5),half-18.0,18.0-half)
		var skew := random.randf_range(-3.0,3.0)
		var blocks := 2 if not ledge and thick>=9.0 and random.randf()<.75 else 1
		tiers.append([y,y+thick,half,center,1 if ledge else 0,skew,blocks])
		if ledge and random.randf()<.45:
			var flank := -1.0 if random.randf()<.5 else 1.0
			drops.append([center+flank*half*random.randf_range(.55,.8),y-1.5,random.randf_range(1.8,2.8),random.randf_range(3.0,5.0)])
		if not ledge and y<height-MESA_DEPTH-2.0:
			var flank := -1.0 if random.randf()<.5 else 1.0
			if thick>9.0 and random.randf()<.6:
				# A window, with a full jamb at either side of it.
				var wide := random.randf_range(1.6,2.4)
				var room := half-WAIST-JAMB-wide
				if room>=0.0: windows.append([Vector2(center+skew+flank*room*random.randf_range(.3,1.0),y+thick*.48),Vector2(wide,thick*.32)])
		y += thick
		ledge = not ledge
	_add_gates()
	_add_legs()
	_add_boulders()

# Legs stand on a ledge beside the wall over it, sky between them, under the
# ledge above, which most of them carry; now and then a pair, one each side.
# None deep in a split, whose own rock takes the place of the canyon's.
func _add_legs() -> void:
	pillars.clear()
	slits.clear()
	for index in range(0,tiers.size()-1):
		var wall: Array = tiers[index]
		# The lowest wall stands on the broad foot, which reaches far out.
		var lower: Array = tiers[index-1] if index>0 else [0.0,0.0,17.5,0.0,0,0.0,1]
		var upper: Array = tiers[index+1]
		var y0 := float(wall[0])
		var y1 := float(wall[1])
		if int(wall[4])!=0 or y1>_mesa_floor()-2.0 or _split_share(y1-1.0)>=.7 or _split_share((y0+y1)*.5)>=.5: continue
		var gated := false
		for window in windows:
			if (window[1] as Vector2).x>=GATE_HALF and (window[0] as Vector2).y>y0 and (window[0] as Vector2).y<y1+GATE_TALL.y: gated = true
		var flank := -1.0 if random.randf()<.5 else 1.0
		var wanted := 2 if random.randf()<.45 else 1
		for side: float in [flank,-flank]:
			if wanted==0: break
			var leg_half := random.randf_range(1.3,2.0)
			var gap := random.randf_range(LEG_GAP.x,LEG_GAP.y)
			var reach_lower := float(lower[3])+float(lower[5])+side*(float(lower[2])-leg_half-.5)
			var reach_upper := float(upper[3])+float(upper[5])+side*(float(upper[2])-leg_half-.5)
			var outer := minf(reach_lower,reach_upper) if side>0.0 else maxf(reach_lower,reach_upper)
			outer = clampf(outer,-17.5,17.5)
			# The wall gives way to the leg: it narrows, never below its least.
			var margin := (BLOCK_SHIFT if int(wall[6])>1 else 0.0)+.5+gap+leg_half
			var widest := (outer-float(wall[3])-float(wall[5]))*side-margin
			# A wall holding a gate keeps its jambs: a leg stands by it only
			# where there is room already.
			if widest<(float(wall[2]) if gated else WALL_HALF.x): continue
			wall[2] = minf(float(wall[2]),widest)
			var inner := float(wall[3])+float(wall[5])+side*(float(wall[2])+margin)
			var x := lerpf(inner,outer,random.randf()*.5)
			var top := y1+.6 if random.randf()<.8 else lerpf(y0,y1,random.randf_range(.55,.8))
			var foot := maxf(y0,_foot_top(x))
			pillars.append([x,foot-1.0,top,leg_half,random.randf()*TAU])
			var gap_x := x-side*(leg_half+gap*.5)
			if top>y1 and y1-.4-foot>2.0: slits.append(Rect2(gap_x-gap*.5,foot,gap,y1-.4-foot))
			wanted -= 1

# One great gate in every stretch of plain canyon between the splits, the
# place that stretch is remembered by.
func _add_gates() -> void:
	var stretches := _plain_stretches()
	for stretch in range(0,stretches.size(),2):
		var best: Array = []
		for tier in tiers:
			# A wall the gate's tall opening rises from, all of it in the stretch.
			var thick := float(tier[1])-float(tier[0])
			if int(tier[4])!=0 or thick<8.5 or float(tier[0])+GATE_FOOT<float(stretches[stretch]) or float(tier[0])+GATE_FOOT+GATE_TALL.y*2.0+LINTEL>float(stretches[stretch+1]): continue
			if best.is_empty() or float(tier[1])-float(tier[0])>float(best[1])-float(best[0]): best = tier
		if best.is_empty(): continue
		# The gate is the wall's one opening: no window beside it, and a full
		# jamb on either side.
		windows = windows.filter(func(window: Array) -> bool: return (window[0] as Vector2).y<float(best[0]) or (window[0] as Vector2).y>float(best[1]))
		# A tall slot of sky as on desert_4k.png, through the wall and on up
		# through the ledge over it; the wall swells to hold it.
		var wide := random.randf_range(GATE_WIDE.x,GATE_WIDE.y)
		var tall := random.randf_range(GATE_TALL.x,GATE_TALL.y)
		best[2] = maxf(float(best[2]),wide+WAIST+JAMB+.5)
		best[6] = 1
		best[3] = clampf(float(best[3]),float(best[2])-18.5-float(best[5]),18.5-float(best[2])-float(best[5]))
		var room := float(best[2])-WAIST-JAMB
		var at := Vector2(float(best[3])+float(best[5])+random.randf_range(-.5,.5)*(room-wide),float(best[0])+GATE_FOOT+tall)
		windows.append([at,Vector2(wide,tall)])

# Stretches of plain canyon where a gate may open, bottom-up: pairs of from
# and to heights between the foot, the splits and the mesa.
func _plain_stretches() -> Array:
	var stretches: Array = [GATE_FLOOR]
	for split in splits: stretches.append_array([float(split["y0"])-1.0,float(split["y1"])+1.0])
	stretches.append(_mesa_floor()-3.0)
	return stretches

# Round stones on the open part of a bench, beside the wall standing on it;
# now and then a second one set on the first.
func _add_boulders() -> void:
	boulders.clear()
	for index in range(1,tiers.size()-1):
		var bench: Array = tiers[index]
		if int(bench[4])!=1 or float(bench[1])>height-MESA_DEPTH-3.0 or random.randf()>.55: continue
		var above: Array = tiers[index+1]
		var flank := -1.0 if random.randf()<.5 else 1.0
		var radius := random.randf_range(1.0,1.7)
		var wall_edge := float(above[3])+float(above[5])+flank*(float(above[2])+1.0+radius)
		var bench_end := float(bench[3])+float(bench[5])+flank*(float(bench[2])-2.5-radius)
		if (bench_end-wall_edge)*flank<0.0: continue
		var x := lerpf(wall_edge,bench_end,random.randf())
		if absf(x)>17.0: continue
		var floor_y := float(bench[1])
		boulders.append([x,floor_y+radius*.7,radius])
		if random.randf()<.4:
			var upper := radius*random.randf_range(.6,.8)
			boulders.append([x+random.randf_range(-.4,.4),floor_y+radius*1.6+upper*.7,upper])

func _tier_index(y: float) -> int:
	for index in range(tiers.size()):
		if y<float(tiers[index][1]): return index
	return tiers.size()-1

# One tier's outline, carried past its ends so that neighbours can melt; `y`
# is the point's height in the leaning stack (see _tiers_outline).
func _tier_outline(point: Vector2, tier: Array, y: float) -> float:
	var wobble := noise.get_noise_2d(point.x*.3,point.y*.45)*2.0
	var rise := clampf((y-float(tier[0]))/(float(tier[1])-float(tier[0])),0,1)
	var edge: float = float(tier[2])
	var shift := 0.0
	# A wall curves in to a waist, or is a stack of blocks pinched where they
	# meet; a ledge is a slab with a flat top and blunt round ends, its nose a
	# little below the middle, as if worn from beneath.
	if int(tier[4])==0:
		var blocks := int(tier[6])
		if blocks<=1: edge -= sin(PI*rise)*WAIST
		else:
			var part := minf(floorf(rise*blocks),blocks-1.0)
			var local := rise*blocks-part
			edge -= pow(1.0-sin(PI*local),2.0)*BLOCK_PINCH+sin(PI*rise)*WAIST*.4
			shift = (fposmod(sin(float(tier[0])*12.9+part*78.2)*437.5,1.0)-.5)*2.0*BLOCK_SHIFT
	else:
		var thick := float(tier[1])-float(tier[0])
		var across := (rise-.45)/.55 if rise>.45 else (rise-.45)/.45
		edge -= (1.0-sqrt(1.0-minf(across*across,1.0)))*thick*.5
		wobble *= .3
	return edge+wobble-absf(point.x-float(tier[3])-float(tier[5])-shift)

# The lean of the borders between tiers (and of a split's seam), one way or
# the other.
func _border_tilt(index: int) -> float:
	return BORDER_TILT*(1.0 if fposmod(sin(index*91.7+seed_value*.001)*437.5,1.0)>.5 else -1.0)

func _melt(y: float, lower: Array, upper: Array) -> float:
	var border := float(lower[1])
	var melt := TOP_MELT if int(lower[4])==1 else TIER_MELT
	return smoothstep(border-(border-float(lower[0]))*melt,border+(float(upper[1])-border)*melt,y)

# The stack of tiers: no tier ends in a level cut, each runs into the next.
func _tiers_outline(point: Vector2) -> float:
	# Borders between tiers lean a little and wave along x: a bench is flat to
	# the eye, never ruled. One shift for every border, and the tier is found
	# by it too, so the stack stays whole across each border.
	# The wave never leans further than the tilt, so no border runs level.
	var y := point.y+noise.get_noise_2d(point.x*.12,90.0)*.5+point.x*_border_tilt(0)
	var index := _tier_index(y)
	var amount := _tier_outline(point,tiers[index],y)
	if index>0: amount = lerpf(_tier_outline(point,tiers[index-1],y),amount,_melt(y,tiers[index-1],tiers[index]))
	if index<tiers.size()-1: amount = lerpf(amount,_tier_outline(point,tiers[index+1],y),_melt(y,tiers[index],tiers[index+1]))
	return amount

# How much of the mountain at a height is the nearest split, 0 to 1.
func _split_weight(y: float, split: Dictionary) -> float:
	return smoothstep(float(split["y0"])-1.0-SPLIT_MELT,float(split["y0"])-1.0,y)*(1.0-smoothstep(float(split["y1"])+1.0,float(split["y1"])+1.0+SPLIT_MELT,y))

# How much of the mountain at a height is a split's own rock, 0 to 1.
func _split_share(y: float) -> float:
	var split := _split_near(y)
	return 0.0 if split.is_empty() else _split_weight(y,split)

func _split_near(y: float) -> Dictionary:
	for split in splits:
		if y>float(split["y0"])-1.0-SPLIT_MELT and y<float(split["y1"])+1.0+SPLIT_MELT: return split
	return {}

# Small breaks of an edge: beds bulging out of it and chips between them, so
# that no stretch of rock runs ruled.
func _breakup(point: Vector2) -> float:
	var bed := sin((point.y+noise.get_noise_2d(point.x*.4,point.y*.4+30.0)*5.0)*1.7)*.55
	return bed+noise.get_noise_2d(point.x*1.5+20.0,point.y*1.5)*1.1

func _pillar(point: Vector2, pillar: Array) -> float:
	var y0: float = pillar[1]
	var y1: float = pillar[2]
	if point.y<y0 or point.y>y1: return -INF
	var half := float(pillar[3])*(.74+.26*sin((point.y-y0)*.8+float(pillar[4])))
	if point.y>y1-1.2: half = float(pillar[3])*1.35
	return minf(half-absf(point.x-float(pillar[0])),y1-point.y)

# A rock hanging from a ledge, wide at its root, coming to a blunt point.
func _drop(point: Vector2, drop: Array) -> float:
	var fall := (float(drop[1])-point.y)/float(drop[3])
	if fall< -.3 or fall>1.0: return -INF
	return float(drop[2])*(1.0-pow(absf(fall-.15),1.4))-absf(point.x-float(drop[0]))

func _outline_at(point: Vector2) -> float:
	var top := height+1.5
	if point.y< -2.0: return -10.0
	if point.y>top+.5: return _mesa(point) if point.y<top+SPIRE_RISE+.5 else -10.0
	var split := _split_near(point.y)
	# The canyon gives way to a split along a leaning, gently waving line, so a
	# wide bench fading into it leaves no ruled rim.
	var weight := _split_weight(point.y+noise.get_noise_2d(point.x*.12,130.0)*.5+point.x*_border_tilt(0),split) if not split.is_empty() else 0.0
	var amount := _canyon_at(point) if weight<1.0 else 0.0
	# Far from its ridges a split's sky counts for little, so the seam follows
	# the canyon's own shapes instead of running level across them.
	if weight>0.0: amount = lerpf(amount,maxf(_split_inside(point,split,top),-SPLIT_SKY),weight)
	amount += _breakup(point)
	amount = _foot(point,amount)
	amount = _cut_windows(amount,point,weight)
	# The last units are the mesa alone, grown out of the canyon below it.
	var crown := smoothstep(_mesa_floor()-3.0,_mesa_floor(),point.y)
	if crown>0.0: amount = lerpf(amount,_mesa(point),crown)
	if point.y>top: return maxf(minf(amount,top+.5-point.y),_mesa(point))
	if point.y>height-8.0: amount = maxf(amount,_route_stone(point))
	return amount

# The ordinary canyon: tiers with their pillars, drops and windows.
func _canyon_at(point: Vector2) -> float:
	var amount := _tiers_outline(point)
	for pillar in pillars: amount = smooth_max(amount,_pillar(point,pillar),1.6)
	for drop in drops: amount = smooth_max(amount,_drop(point,drop),1.2)
	for boulder in boulders:
		var lumpy := noise.get_noise_2d(point.x*1.1+float(boulder[0])*7.0,point.y*1.1)*.18
		amount = smooth_max(amount,float(boulder[2])-point.distance_to(Vector2(float(boulder[0]),float(boulder[1])))+lumpy,.45)
	return _with_features(amount,point)

# Windows and gates cut through the worn outline, so their jambs stay
# straight: an arch with a flat lintel, its upper corners rounded; lintel and
# sill wave a little, never ruled. A split's own rock is left whole.
func _cut_windows(amount: float, point: Vector2, weight: float) -> float:
	for window in windows:
		var half: Vector2 = window[1]
		var center: Vector2 = window[0]
		# A great gate stands in a frame of its own, jambs and lintel, which a
		# split growing out of the canyon nearby does not wear away.
		if half.x>=GATE_HALF:
			var frame := Rect2(center-half-Vector2(JAMB,1.0),half*2.0+Vector2(JAMB*2.0,LINTEL+1.0))
			amount = smooth_max(amount,_bench(point,frame,1.8,_tilt(center),0.0)+_breakup(point)*.7-smoothstep(.6,1.0,weight)*20.0,1.0)
		var opening := _bench(point,Rect2(center-half,half*2.0),minf(half.x,half.y)*.4,_tilt(center),0.0)-(20.0 if weight>=1.0 else 0.0)
		amount = -smooth_max(-amount,opening,.6)
	for slit in slits:
		if weight<.5: amount = -smooth_max(-amount,rounded_box(point,slit,minf(slit.size.x*.45,1.0)),.5)
	return amount

# A rounded box whose flat top and bottom lean a little and wave gently
# along x: a slab, a lintel, a sill, flat to the eye but never ruled.
# Positive inside.
func _bench(point: Vector2, box: Rect2, radius: float, tilt: float, wave: float = .9) -> float:
	var lift := noise.get_noise_2d(point.x*.45,box.position.y*3.0+17.0)*wave+(point.x-box.get_center().x)*tilt
	return rounded_box(point+Vector2(noise.get_noise_2d(20.0+box.position.x,point.y*.5)*.25,lift),box,radius)

# A small lean for a shape at a place, one way or the other.
func _tilt(at: Vector2) -> float:
	var pick := fposmod(sin(at.x*12.9+at.y*78.2)*437.5,1.0)
	return (.08+pick*.06)*(1.0 if pick>.5 else -1.0)

# Where the mesa begins: its full depth below the top, but clear of the last
# split, whose two ways need the canyon's rock.
func _mesa_floor() -> float:
	var floor_y := height-MESA_DEPTH
	for split in splits: floor_y = maxf(floor_y,float(split["y1"])+2.0)
	return minf(floor_y,height-4.0)

# The summit: a flat mesa on the route's line, its top waving a little, and a
# narrow spire standing up from one side of it.
func _mesa(point: Vector2) -> float:
	var center := corridor_center(height)
	var half := lerpf(MESA_HALF.x,MESA_HALF.y,.5+.5*noise.get_noise_2d(5.0,height))
	var floor_y := _mesa_floor()
	var mesa := _bench(point,Rect2(center-half,floor_y-1.0,half*2.0,height+2.0-floor_y),1.6,_tilt(Vector2(center,height))*.6,.6)
	var side := 1.0 if noise.get_noise_2d(9.0,height)>0.0 else -1.0
	var spire_x := center+side*(half-1.3)
	var thin := 1.1+.25*sin(point.y*1.3)
	var spire := minf(thin-absf(point.x-spire_x),height+1.0+SPIRE_RISE-point.y)
	return smooth_max(mesa,spire,.9)

# The canyon stands on a broad tumble of rock.
func _foot(point: Vector2, amount: float) -> float:
	if point.y>FOOT_TOP: return amount
	var foot := 19.0*(1.0-pow(clampf(point.y/FOOT_TOP,0,1),1.5))+noise.get_noise_2d(point.x*.5,point.y*.8+70.0)*2.2-absf(point.x)
	return maxf(amount,foot)

# Where the slope of the foot is at a distance from the middle, roughly.
func _foot_top(x: float) -> float:
	return FOOT_TOP*pow(clampf(1.0-absf(x)/19.0,0,1),1.0/1.5)

# Sandstone wears round: every corner and tip of the outline is taken off.
func _finished_outline(outline: Image) -> Image:
	var size := outline.get_size()
	var worn: Image = outline.duplicate()
	worn.resize(size.x/OUTLINE_WEAR,size.y/OUTLINE_WEAR,Image.INTERPOLATE_LANCZOS)
	worn.resize(size.x,size.y,Image.INTERPOLATE_CUBIC)
	return worn

# The main ridge of a split is a stack of blocks, each a little wider or
# narrower than the one under it, as the canyon's own walls.
func _split_edge(y: float) -> float:
	var part := floorf(y/SPLIT_BLOCK)
	return (fposmod(sin(part*12.9+3.1)*437.5,1.0)-.5)*1.8

# Ridges and slabs of a split join with a short round: sky stays between.
func _split_blend() -> float:
	return 1.6

func _far_ridge(point: Vector2, split: Dictionary) -> float:
	if split["style"]=="stones": return -INF
	var far: float = split["far_x"]
	var y0: float = split["y0"]
	var y1: float = split["y1"]
	var main: float = split["main_x"]
	var near := minf(main,far)
	var wide := maxf(main,far)
	var pillar := 2.8 if split["style"]=="ledge" else 2.4
	# A column of blocks set one on another, each a little off the last,
	# between a slab at its foot and a slab at its top: the canyon's own
	# tiers and legs, not one soft band.
	var amount := -INF
	var y := y0
	var block := 0
	while y<y1:
		var tall := 3.0+fposmod(sin(far*12.9+block*78.2)*437.5,1.0)*2.0
		var shift := (fposmod(sin(far*4.1+block*31.7)*917.3,1.0)-.5)*1.6
		var half := pillar*(.8+fposmod(sin(far*7.3+block*11.1)*271.9,1.0)*.3)
		amount = smooth_max(amount,_bench(point,Rect2(far+shift-half,y-.25,half*2.0,minf(tall,y1-y)+.5),1.1,_tilt(Vector2(far,y)),.5),.8)
		y += tall
		block += 1
	amount = smooth_max(amount,_bench(point,Rect2(near,y0-.5,wide-near,3.7),1.6,_tilt(Vector2(near,y0))),1.4)
	return smooth_max(amount,_bench(point,Rect2(near,y1-3.6,wide-near,4.6),1.6,_tilt(Vector2(near,y1))),1.4)

func _dress_brief(source: LevelSource) -> void:
	source.brief["rock"] = "desert"
	source.brief["free_route"] = true
	var marks: Array = []
	for tier in tiers:
		if int(tier[4])==1: marks.append([snappedf(float(tier[0]),.01),snappedf(float(tier[1]),.01),snappedf(float(tier[2]),.01),snappedf(float(tier[3])+float(tier[5]),.01)])
	source.brief["marks"] = marks
