class_name LootPlacement
extends RefCounted

# Generator v15: finds by placement role, on top of the v14 acts. The layout
# only *requests* a point with a role while it builds a row; a request is
# resolved two rows later, when every hazard that may touch it (hazards of
# rows up to request+2) exists. Resolution order is row, then priority, then
# request order, and only hazards up to request+2 are read, so the result is
# the same however generate_to() is chunked.
#
# Roles:
#   main_safe       under every second main grip: valuable / single coin /
#                   one regional material per act
#   main_coin       a short arc of single coins under the other main grips
#   detour          beside-path branch: a part of the act's set, with a short
#                   scatter of coins on the way in (visible before the choice)
#   choice, fork_collection   rare artifact behind one clear risk
#   fork_risky_shortcut       coin cache 40-60
#   fork_speed, other forks   the region's risk material
#   landmark        once per act, under its exit grip: the act's landmark relic
#   contract_target the first branch find of the run's contract act becomes
#                   the contract cargo (next act if the act has no branch)
# Nothing here moves a grip, shelf or hazard: geometry stays v14.

const PRIORITY := {"landmark":5,"fork":3,"choice":3,"detour":2,"main_safe":1}
const OFFSETS := [Vector2.ZERO,Vector2(.45,0),Vector2(-.45,0),Vector2(0,.4),Vector2(.7,.2),Vector2(-.7,.2)]
const FIND_SPACING := .8
const GRIP_CLEARANCE := 1.2
# The layout owns this planner; a weak link avoids a reference cycle.
var _owner: WeakRef
var layout: ExpeditionLayout:
	get: return _owner.get_ref() as ExpeditionLayout
var pending: Array[Dictionary] = []
var serial := 0
var main_counts: Dictionary = {}
var contract_act := -1
# Statistics for tests and the report.
var placed: Dictionary = {}
var dropped: Dictionary = {}

func _init(owner: ExpeditionLayout) -> void:
	_owner = weakref(owner)

func request(row: int, point: Vector2, role: String, from: Vector2 = Vector2.INF) -> void:
	pending.append({"row":row,"pos":point,"role":role,"from":from,"act":int(layout.row_of(row)["act"]),"order":serial})
	serial += 1

static func priority(role: String) -> int:
	return int(PRIORITY.get("fork" if role.begins_with("fork_") else role,1))

func resolve_until(limit_row: float) -> void:
	while true:
		var ready: Array[Dictionary] = []
		var waiting: Array[Dictionary] = []
		for entry in pending:
			if float(entry["row"])<=limit_row: ready.append(entry)
			else: waiting.append(entry)
		pending = waiting
		if ready.is_empty(): return
		ready.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
			if a["row"]!=b["row"]: return int(a["row"])<int(b["row"])
			if priority(a["role"])!=priority(b["role"]): return priority(a["role"])>priority(b["role"])
			return int(a["order"])<int(b["order"]))
		for entry in ready: _resolve(entry)

func _contract_candidate(entry: Dictionary) -> bool:
	if not layout.finite or not layout.contract.is_empty(): return false
	var role: String = entry["role"]
	if role!="detour" and not role.begins_with("fork_"): return false
	if contract_act<0:
		var random := RandomNumberGenerator.new()
		random.seed = layout.seed_value*7919+layout.location*104729+901
		contract_act = random.randi_range(0,layout.spans.size()-1)
	# An act without a branch passes the contract to the next one.
	if int(entry["act"])>contract_act: contract_act = int(entry["act"])
	return int(entry["act"])==contract_act

func _resolve(entry: Dictionary) -> void:
	var act: int = entry["act"]
	var info := layout.span(act)
	var definition: Dictionary = info["def"]
	var act_id := str(info["id"])
	var location := layout.location
	var point: Vector2 = entry["pos"]
	var tier := clampi(int(point.y/layout.height_units*6.0),0,5)
	var random := layout.act_rng(act,int(entry["row"]),800+int(entry["order"])%7)
	var role: String = entry["role"]
	var drops: Dictionary = ItemCatalog.balance()["material_drops"][clampi(location,0,2)]
	if _contract_candidate(entry):
		var cargo := ItemCatalog.contract(0,location,act_id,tier,str(definition.get("contract_tag","")))
		var id := _place(point,cargo,entry,"contract_target")
		if id>=0:
			layout.contract = {"tag":str(definition.get("contract_tag","")),"act":act,"act_id":act_id,"act_name":str(definition["display_name"]),"find":id,"name":cargo["name"]}
			return
	var item: Dictionary
	match role:
		"landmark":
			item = ItemCatalog.relic(0,location,act_id,tier,str(definition.get("reward_tag","")),true)
		"main_safe":
			var k := int(main_counts.get(act,0))
			main_counts[act] = k+1
			if k==2: item = ItemCatalog.material(0,location,act_id,tier,str(drops["main"][random.randi_range(0,drops["main"].size()-1)]))
			elif k%2==1: item = ItemCatalog.coin(0,location,act_id,int(ItemCatalog.balance()["coins"]["single"]))
			else: item = ItemCatalog.valuable(0,location,act_id,tier)
		"main_coin":
			# A short arc of single coins where the hero hangs below the grip.
			var count := int(ItemCatalog.balance()["coins"].get("main_arc",1))
			for index in range(count):
				var dx := (index-(count-1)*.5)*.85
				_place(point+Vector2(dx,absf(dx)*.3),ItemCatalog.coin(0,location,act_id,int(ItemCatalog.balance()["coins"]["single"])),entry,"main_coin",count==1)
			return
		"detour":
			item = ItemCatalog.relic(0,location,act_id,tier,str(definition.get("reward_tag","")))
			_scatter(entry,act_id)
		"choice", "fork_collection":
			item = ItemCatalog.valuable(0,location,act_id,tier,"artifact")
		"fork_risky_shortcut":
			var coins: Dictionary = ItemCatalog.balance()["coins"]
			item = ItemCatalog.coin(0,location,act_id,random.randi_range(int(coins["cache_min"]),int(coins["cache_max"])),"cache")
		_:
			item = ItemCatalog.material(0,location,act_id,tier,str(drops["risk"]))
	if _place(point,item,entry,role)<0 and role=="landmark" and int(layout.row_of(int(entry["row"])+1)["act"])==act:
		# The landmark tries the act's last grip before giving up (checked
		# against the same hazards, so chunking cannot change the result).
		_place(layout.main_point(int(entry["row"])+1)+Vector2(.25,-2.05),item,entry,role)

# Three coins on the way from the main grip's hanging spot to the detour.
func _scatter(entry: Dictionary, act_id: String) -> void:
	var from: Vector2 = entry["from"]
	if not from.is_finite(): return
	var coins: Dictionary = ItemCatalog.balance()["coins"]
	var count := int(coins["scatter_count"])
	for index in range(count):
		var at := from.lerp(entry["pos"],float(index+1)/float(count+1))
		_place(at,ItemCatalog.coin(0,layout.location,act_id,int(coins["scatter_value"]),"scatter"),entry,"scatter",false)

func _place(point: Vector2, item: Dictionary, entry: Dictionary, role: String, shift: bool = true) -> int:
	for offset in (OFFSETS if shift else [Vector2.ZERO]):
		var at: Vector2 = point+offset
		if not clear(at,int(entry["row"])): continue
		var id := layout.finds.size()
		item["id"] = id
		item["item_id"] = "%s/%s/%d" % [item["act_id"],role,id]
		layout.finds.append({"item":item,"pos":at,"origin":point,"row":int(entry["row"]),"picked":false,"rare":str(item["rarity"]) in ["artifact","set","contract"],"role":role,"act":int(entry["act"])})
		placed[role] = int(placed.get(role,0))+1
		return id
	dropped[role] = int(dropped.get(role,0))+1
	return -1

# Placement checks: inside the face, clear of grips, obstacles, shelves,
# fork spots and other finds; never in a main-path field hazard, on an
# icicle line or beside a contact hazard.
# A grip built after a find (a network bridge of a later row) moves the find
# to another checked spot near its origin, or withdraws it. Ids never change.
func on_grip_added(grip: Vector2) -> void:
	for index in range(layout.finds.size()-1,-1,-1):
		var find: Dictionary = layout.finds[index]
		if not find.has("origin"): continue
		if (find["pos"] as Vector2).distance_to(grip)>=GRIP_CLEARANCE: continue
		var moved := false
		for offset in OFFSETS+[Vector2(.9,-.3),Vector2(-.9,-.3),Vector2(0,-.6),Vector2(1.2,0),Vector2(-1.2,0),Vector2(0,-1.0)]:
			var at: Vector2 = find["origin"]+offset
			if clear(at,int(find["row"]),index):
				find["pos"] = at
				moved = true
				break
		# No room left: the find is withdrawn (never shown, never collected).
		if not moved:
			find["withdrawn"] = true
			find["picked"] = true

func clear(point: Vector2, row: int, ignore: int = -1) -> bool:
	if layout.outside(point,0): return false
	for id in layout.nearby_ids(point.y-2.5,point.y+2.5):
		if layout.anchors[id]["pos"].distance_to(point)<GRIP_CLEARANCE: return false
	for obstacle in layout.obstacles:
		if MountainLayout.blocked(point,point,obstacle,Vector2(.35,.35)): return false
	for ledge in layout.ledges:
		if point.x>float(ledge["left"])-.3 and point.x<float(ledge["right"])+.3 and point.y>float(ledge["top"])-.7 and point.y<float(ledge["top"])+.3: return false
	for spots in layout.reserved_spots.values():
		for spot in spots:
			if (spot as Vector2).distance_to(point)<1.0: return false
	for hazard in layout.hazards:
		if int(hazard["row"])>row+2: continue
		match str(hazard["kind"]):
			"field":
				if bool(hazard.get("affects_main",false)) and (hazard["rect"] as Rect2).grow(.3).has_point(point): return false
			"falling":
				if absf(point.x-float(hazard["x"]))<float(hazard["radius"])+.6 and point.y>float(hazard["bottom"])-.5 and point.y<float(hazard["top"])+.5: return false
			"contact":
				if point.distance_to(hazard["pos"])<float(hazard["radius"])+1.5: return false
	for index in range(layout.finds.size()):
		if index!=ignore and (layout.finds[index]["pos"] as Vector2).distance_to(point)<FIND_SPACING: return false
	return true
