class_name RouteGraph
extends RefCounted

# Directed audit of a generated route. An edge is judged from the state the
# player is really in after the source grip acted: its entry consumed, a root
# clock running, an ice contact slid, a spring released without its bonus.
# Positional connectivity of the original grips alone proves nothing.

static func audit(layout: MountainLayout) -> Dictionary:
	var problems: Array[String] = []
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
		if not GripSpec.network_kind(GripSpec.kind_of(b)):
			problems.append("main %d needs a %s grip" % [row,GripSpec.type_of(b)])
	# 3-6. Branches leave from a grip that is consumed behind the player.
	for branch in layout.branches:
		var entry: Dictionary = anchors[branch["entry"]]
		var grip: Dictionary = anchors[branch["anchor"]]
		var exit: Vector2 = branch["exit_pos"]
		if entry["pos"].distance_to(grip["pos"])>rope or not layout.transition_clear(entry["pos"],grip["pos"]):
			problems.append("branch %d cannot be entered" % grip["id"])
		if not layout.exit_reachable(grip,exit):
			problems.append("branch %d (%s) has no exit after its effect" % [grip["id"],GripSpec.type_of(grip)])
		if row_of.has(branch["entry"]) and int(branch["exit_row"])<=int(row_of[branch["entry"]]):
			problems.append("branch %d rejoins behind its consumed entry" % grip["id"])
	for grip in anchors:
		match GripSpec.kind_of(grip):
			GripSpec.ROOT:
				if grip.get("permanent",false): problems.append("root %d is permanent" % grip["id"])
			GripSpec.SPRING:
				# The impulse is a bonus: the next grip is reachable without it.
				if row_of.has(grip["id"]) and int(row_of[grip["id"]])+1<route.size():
					var next: Vector2 = anchors[route[int(row_of[grip["id"]])+1]]["pos"]
					if grip["pos"].distance_to(next)>rope: problems.append("spring %d is the only way on" % grip["id"])
			GripSpec.CRYSTAL:
				var exits := GripSpec.choice_exits(grip)
				if layout.scenario_routes and exits.size()!=2:
					problems.append("crystal %d offers %d exits" % [grip["id"],exits.size()])
				for exit_id in exits:
					if not layout.exit_reachable(grip,anchors[int(exit_id)]["pos"]):
						problems.append("crystal %d exit %d unreachable" % [grip["id"],int(exit_id)])
	# 7. Recovery: an activated reserve leads into untouched grips ahead.
	for id in layout.rescue_anchors.keys():
		if not row_of.has(id) or int(row_of[id])+1>=route.size(): continue
		var reserve: Vector2 = anchors[layout.rescue_anchors[id]]["pos"]
		var next: Vector2 = anchors[route[int(row_of[id])+1]]["pos"]
		if reserve.distance_to(next)>rope or not layout.transition_clear(reserve,next):
			problems.append("reserve under %d leads nowhere" % id)
	# 8. One new mechanic per phrase at most.
	var stats := {}
	if layout is EncounterLayout:
		for plan in (layout as EncounterLayout).scenarios.values():
			var key: String = plan["template"]+("" if plan["placed"] or plan["template"]=="intro" else "_skipped")
			stats[key] = int(stats.get(key,0))+1
			if plan["new"] and plan["combo"]: problems.append("phrase %d mixes a new rule with a combination" % plan["block"])
	return {"problems":problems,"stats":stats}
