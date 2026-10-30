class_name RouteGraph
extends RefCounted

# Directed audit of a generated route. An edge is judged from the state the
# player is really in after the source grip acted: its entry consumed, a root
# clock running, an ice contact slid, a spring released without its bonus.
# Positional connectivity of the original grips alone proves nothing.

# Closest two grips may stand: nearer, a hook aimed at one catches the other.
const GRIP_SPACING := 1.45

# An exit judged from where the grip really leaves the hook: ice from every
# contact its slide can produce on the drawn stone; other types as the
# generator placed them.
static func exit_after_effect(layout: MountainLayout, grip: Dictionary, target: Vector2) -> bool:
	if GripSpec.kind_of(grip)!=GripSpec.ICE: return layout.exit_reachable(grip,target)
	for contact in GripSpec.slide_contacts(grip):
		if contact.distance_to(target)>=MountainLayout.LINK_REACH or not layout.transition_clear(contact,target): return false
	return true

static func audit(layout: MountainLayout) -> Dictionary:
	var problems: Array[String] = []
	var stats := {}
	var rope := float(MountainLayout.base_kit()["rope"])
	var anchors := layout.anchors
	var route := layout.main_route
	var row_of := {}
	for row in range(route.size()): row_of[route[row]] = row
	# 1-2. The main path is climbable by the base kit, one way, from each grip
	# to the next, and never needs a timed, sliding or choice grip.
	for row in range(1,route.size()):
		var a: Dictionary = anchors[route[row-1]]
		var b: Dictionary = anchors[route[row]]
		var from: Vector2 = a["pos"]
		var to: Vector2 = b["pos"]
		if to.y<=from.y or from.distance_to(to)>rope or not layout.transition_clear(from,to):
			problems.append("main %d->%d is not a rising base-kit transfer" % [row-1,row])
		if not GripSpec.network_kind(GripSpec.kind_of(b)) and not GripSpec.fork(b):
			problems.append("main %d needs a %s grip" % [row,GripSpec.type_of(b)])
	# 3-6. Branches leave from a grip that is consumed behind the player. Each
	# record is judged in the state after its grip acted: every candidate exit
	# is reached from the slid contact and before the clock ends, and none of
	# them lies behind a consumed entry.
	var recorded := {}
	for branch in layout.branches:
		var entry: Dictionary = anchors[branch["entry"]]
		var grip: Dictionary = anchors[branch["anchor"]]
		recorded[grip["id"]] = true
		if entry["pos"].distance_to(grip["pos"])>rope or not layout.transition_clear(entry["pos"],grip["pos"]):
			problems.append("branch %d cannot be entered" % grip["id"])
		if bool(branch.get("entry_consumed",true))!=(not entry["permanent"]):
			problems.append("branch %d records a stale entry lifetime" % grip["id"])
		var entry_row := int(row_of.get(branch["entry"],-1))
		for exit in branch.get("candidate_exits",[{"row":branch["exit_row"],"pos":branch["exit_pos"],"kind":"main"}]):
			if not exit_after_effect(layout,grip,exit["pos"]):
				# Frozen generators (saved attempts only) keep the check they
				# were built against; their real-slide gaps are only counted.
				if layout is ExpeditionLayout or not layout.exit_reachable(grip,exit["pos"]):
					problems.append("branch %d (%s) has no %s exit after its effect" % [grip["id"],GripSpec.type_of(grip),exit["kind"]])
				else: stats["legacy_ice_exit"] = int(stats.get("legacy_ice_exit",0))+1
			if exit.has("row") and entry_row>=0 and not entry["permanent"] and int(exit["row"])<=entry_row:
				problems.append("branch %d rejoins behind its consumed entry" % grip["id"])
		if branch.has("hazard_state"):
			if int(branch["safe_exit"])<0 and int(branch["risky_exit"])<0:
				problems.append("branch %d has neither a safe nor a risky exit" % grip["id"])
			if (branch["hazard_state"] in ["timer","slide"])!=(int(branch["risky_exit"])>=0):
				problems.append("branch %d hazard %s disagrees with its exits" % [grip["id"],branch["hazard_state"]])
	# Optional grips without a directed record cannot be audited.
	for grip in anchors:
		if GripSpec.role(grip) in ["branch","reward"] and not recorded.has(grip["id"]):
			if layout.safe_routes: problems.append("branch %d has no directed record" % grip["id"])
			else: stats["untracked_branch"] = int(stats.get("untracked_branch",0))+1
	for grip in anchors:
		match GripSpec.kind_of(grip):
			GripSpec.ROOT:
				if grip.get("permanent",false): problems.append("root %d is permanent" % grip["id"])
			GripSpec.SPRING:
				# 7. The throw neither rises into rock nor heads for the fall zone.
				if not grip.get("reserve",false) and not layout.spring_lane_clear(grip["pos"],GripSpec.exit_direction(grip)):
					if layout.calibrated_routes: problems.append("spring %d throws into rock or down" % grip["id"])
					else: stats["blocked_spring"] = int(stats.get("blocked_spring",0))+1
				# The impulse is a bonus: the next grip is reachable without it.
				if row_of.has(grip["id"]) and int(row_of[grip["id"]])+1<route.size():
					var next: Vector2 = anchors[route[int(row_of[grip["id"]])+1]]["pos"]
					if grip["pos"].distance_to(next)>rope: problems.append("spring %d is the only way on" % grip["id"])
			GripSpec.CRYSTAL:
				var exits := GripSpec.choice_exits(grip)
				if layout.scenario_routes and exits.size()!=2:
					problems.append("crystal %d offers %d exits" % [grip["id"],exits.size()])
				for exit_id in exits:
					if not exit_after_effect(layout,grip,anchors[int(exit_id)]["pos"]):
						problems.append("crystal %d exit %d unreachable" % [grip["id"],int(exit_id)])
	# Every grip a route names keeps its own space (reserves sit under their
	# grip by design and stay dormant until a revival).
	for grip in anchors:
		if grip.get("reserve",false): continue
		for other_id in layout.nearby_ids(grip["pos"].y-GRIP_SPACING,grip["pos"].y+GRIP_SPACING):
			var other: Dictionary = anchors[other_id]
			if other_id<=int(grip["id"]) or other.get("reserve",false) or grip["pos"].distance_to(other["pos"])>=GRIP_SPACING: continue
			if layout.calibrated_routes and (GripSpec.role(grip) in ["branch","reward"] or GripSpec.role(other) in ["branch","reward"]):
				problems.append("grips %d and %d overlap" % [grip["id"],other_id])
			else: stats["crowded_pair"] = int(stats.get("crowded_pair",0))+1
	# 7. Recovery: an activated reserve leads into untouched grips ahead.
	for id in layout.rescue_anchors.keys():
		if not row_of.has(id) or int(row_of[id])+1>=route.size(): continue
		var reserve: Vector2 = anchors[layout.rescue_anchors[id]]["pos"]
		var next: Vector2 = anchors[route[int(row_of[id])+1]]["pos"]
		if reserve.distance_to(next)>rope or not layout.transition_clear(reserve,next):
			problems.append("reserve under %d leads nowhere" % id)
	# 8. One new mechanic per phrase at most.
	if layout is EncounterLayout:
		for plan in (layout as EncounterLayout).scenarios.values():
			var key: String = plan["template"]+("" if plan["placed"] or plan["template"]=="intro" else "_skipped")
			stats[key] = int(stats.get(key,0))+1
			if plan["new"] and plan["combo"]: problems.append("phrase %d mixes a new rule with a combination" % plan["block"])
	return {"problems":problems,"stats":stats}
