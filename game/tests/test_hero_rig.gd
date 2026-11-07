extends SceneTree

# HeroRig, the stage 2 cut-out slice: bones from skeleton.json, skinned bends
# without tears, seams that stay closed and the drawing order.

var checks := 0
var failures: Array[String] = []

func _initialize() -> void:
	call_deferred("run_tests")

func check(ok: bool, description: String) -> void:
	checks += 1
	if not ok:
		failures.append(description)
		push_error("HERO RIG FAILED: "+description)

func run_tests() -> void:
	var rig := HeroRig.new()
	root.add_child(rig)
	rig.setup()
	var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(HeroRig.SKELETON_PATH))
	check(rig.skeleton.get_bone_count()==data["bones"].size()+rig.helpers.size(),"every bone of skeleton.json is in the rig, plus joint helpers")
	check(rig.helpers.has("elbow_near_mid") and rig.helpers.has("knee_far_mid") and rig.helpers.has("chest_mid"),"elbows, knees and the spine bend through half-angle helpers")
	for layer in HeroRig.SLICE: check(rig.parts.has(layer),"slice part %s is built" % layer)
	check(rig.art_source.ends_with("/placeholder/") or rig.art_source.ends_with("/pioneer/"),"part art is loaded")
	rig.set_pose({})
	var largest := 0.0
	for layer in rig.parts:
		var skinned := rig.skinned_vertices(layer)
		for index in range(skinned.size()): largest = maxf(largest,skinned[index].distance_to(rig.rest_vertices[layer][index]))
	check(largest<.0001,"the rest pose draws parts exactly where they are painted")
	for pose_name in HeroPrototypePoses.POSES:
		rig.set_pose(HeroPrototypePoses.POSES[pose_name])
		var stats := sleeve_stats(rig)
		print("pose %s: stretch %.2f..%.2f, folded %.0f%%, cuff gap %.4f" % [pose_name,stats["min"],stats["max"],stats["folded"]*100,stats["cuff_gap"]])
		# The inner side of a bend may bunch up (fabric folds); the outer side
		# rounds over the elbow and must not stretch like rubber; no part of the
		# sleeve may turn inside out.
		check(stats["min"]>.15 and stats["max"]<1.7,"sleeve neither tears nor stretches like rubber in %s (%.2f..%.2f)" % [pose_name,stats["min"],stats["max"]])
		check(stats["folded"]==0.0,"no part of the sleeve turns inside out in %s (%.0f%%)" % [pose_name,stats["folded"]*100])
		check(stats["cuff_gap"]<.01,"the cuff stays on the wrist in %s" % pose_name)
	rig.set_pose({})
	var grip_rest := rig.grip_position()
	rig.set_pose({"hand_near":.8})
	check(rig.grip_position().distance_to(grip_rest)>.01,"the rope grip follows the hand")
	rig.set_pose({"shoulder_near":1.0})
	var hand: Vector3 = rig.skeleton.get_bone_global_pose(rig.bone_index["hand_near"]).origin
	check(rig.grip_position().distance_to(rig.skeleton.global_transform*hand)<.12,"the grip stays in the glove when the arm moves")
	var order: Array = data["layers_back_to_front"]
	check(rig.priority("torso")<rig.priority("glove_near") and rig.priority("glove_near")<rig.priority("sleeve_near"),"the near arm is drawn over the torso, the wrist inside the cuff")
	check(rig.priority("torso")<rig.priority("head") and rig.priority("head")<rig.priority("eyes"),"head over torso, eyes over head")
	check(rig.priority("joint_shadow_neck")>rig.priority("torso") and rig.priority("joint_shadow_neck")<rig.priority("head"),"the neck shadow lies on the torso under the head")
	check(order.find("backpack")<order.find("torso") and order.find("sleeve_far")<order.find("torso"),"backpack and far arm are behind the torso")
	rig.set_layer("sleeve_near","torso")
	check(rig.priority("sleeve_near")>rig.priority("torso") and rig.priority("sleeve_near")<rig.priority("head"),"the animation can pass the arm behind the head")
	rig.reset_layers()
	rig.arm_behind_head()
	check(rig.priority("glove_near")>rig.priority("torso") and rig.priority("glove_near")<rig.priority("sleeve_near") and rig.priority("sleeve_near")<rig.priority("head"),"the glove goes behind the head with its sleeve, still under the cuff")
	rig.reset_layers()
	check(rig.priority("sleeve_near")==rig.layer_priority("sleeve_near"),"layers return to the template order")
	var largest_step := 0.0
	var previous := HeroPrototypePoses.throw_pose(0)
	for index in range(1,int(HeroPrototypePoses.THROW_TIME*60)):
		var pose := HeroPrototypePoses.throw_pose(index/60.0)
		for bone in pose: largest_step = maxf(largest_step,absf(float(pose[bone])-float(previous.get(bone,0.0))))
		previous = pose
	check(largest_step<.4,"the throw moves fast but without jumps (%.2f rad per frame)" % largest_step)
	full_body_tests()
	print("HERO_RIG_TESTS ",checks," checks, ",failures.size()," failures")
	for failure in failures: print("  FAILED: ",failure)
	quit(0 if failures.is_empty() else 1)

# Edge stretch, folded triangles and the gap between the cuff and the wrist.
func sleeve_stats(rig: HeroRig, layer: String = "sleeve_near", end_bone: String = "hand_near") -> Dictionary:
	var rest: PackedVector3Array = rig.rest_vertices[layer]
	var now := rig.skinned_vertices(layer)
	var columns := 4
	var rows := rest.size()/(columns+1)-1
	var low := 10.0
	var high := 0.0
	var folded := 0
	var triangles := 0
	# Only the painted body of the sleeve (inner columns); the outer columns lie
	# in the transparent margin of the canvas and nobody sees them stretch.
	for row in range(rows+1):
		for column in range(1,columns):
			var a := row*(columns+1)+column
			for b in [a+1 if column<columns-1 else -1,a+columns+1 if row<rows else -1]:
				if b<0: continue
				var ratio := now[a].distance_to(now[b])/maxf(.00001,rest[a].distance_to(rest[b]))
				low = minf(low,ratio)
				high = maxf(high,ratio)
	for row in range(rows):
		for column in range(1,columns-1):
			var a := row*(columns+1)+column
			for tri in [[a,a+1,a+columns+1],[a+1,a+columns+2,a+columns+1]]:
				var r := (Vector2(rest[tri[1]].x,rest[tri[1]].y)-Vector2(rest[tri[0]].x,rest[tri[0]].y)).cross(Vector2(rest[tri[2]].x,rest[tri[2]].y)-Vector2(rest[tri[0]].x,rest[tri[0]].y))
				var n := (Vector2(now[tri[1]].x,now[tri[1]].y)-Vector2(now[tri[0]].x,now[tri[0]].y)).cross(Vector2(now[tri[2]].x,now[tri[2]].y)-Vector2(now[tri[0]].x,now[tri[0]].y))
				triangles += 1
				if signf(r)!=signf(n): folded += 1
	# The wrist joint row of the painted sleeve, after skinning, against the hand bone.
	var part := rig.part_info(layer.trim_suffix("_near").trim_suffix("_far"))
	var end_joint := end_bone.replace("_far","_near")
	var hand_row: float = part["joints_px"][end_joint][1]/float(part["canvas_px"][1])*rows
	var row_index := roundi(hand_row)
	var center := (now[row_index*(columns+1)+columns/2])
	var hand: Vector3 = rig.skeleton.get_bone_global_pose(rig.bone_index[end_bone]).origin
	return {"min":low,"max":high,"folded":float(folded)/triangles,"cuff_gap":Vector2(center.x-hand.x,center.y-hand.y).length()}

# The whole hero: every layer builds, legs bend at the knee like the sleeve at
# the elbow, the walk has no jumps and the boot stays on the ankle.
func full_body_tests() -> void:
	var rig := HeroRig.new()
	root.add_child(rig)
	rig.setup(HeroRig.FULL)
	for layer in HeroRig.FULL: check(rig.parts.has(layer),"full hero part %s is built" % layer)
	check(rig.priority("pant_leg_far")<rig.priority("pelvis") and rig.priority("pelvis")<rig.priority("pant_leg_near") and rig.priority("pant_leg_near")<rig.priority("torso"),"far leg, pelvis, near leg, then the jacket over them")
	check(rig.priority("backpack")<rig.priority("torso") and rig.priority("glove_far")<rig.priority("sleeve_far"),"backpack behind the jacket, far glove under its cuff")
	var poses := HeroPrototypePoses.BODY_POSES.duplicate()
	for index in range(8): poses["walk_%d" % index] = HeroPrototypePoses.walk_pose(index*HeroPrototypePoses.WALK_TIME/8)
	for pose_name in poses:
		rig.set_pose(poses[pose_name])
		for side in ["near","far"]:
			var stats := sleeve_stats(rig,"pant_leg_"+side,"foot_"+side)
			check(stats["min"]>.15 and stats["max"]<1.7 and stats["folded"]==0.0,"%s leg bends cleanly in %s (%.2f..%.2f, folded %.0f%%)" % [side,pose_name,stats["min"],stats["max"],stats["folded"]*100])
			check(stats["cuff_gap"]<.01,"the %s boot stays on the ankle in %s" % [side,pose_name])
		var arm := sleeve_stats(rig,"sleeve_far","hand_far")
		check(arm["folded"]==0.0 and arm["cuff_gap"]<.01,"the far sleeve holds together in %s" % pose_name)
	rig.set_pose(HeroPrototypePoses.LAND)
	check(rig.plant_feet()>.05,"a crouch drops the body so the feet stay on the ground")
	var foot: Vector3 = rig.skeleton.global_transform*rig.skeleton.get_bone_global_pose(rig.bone_index["foot_near"]).origin
	var foot_far: Vector3 = rig.skeleton.global_transform*rig.skeleton.get_bone_global_pose(rig.bone_index["foot_far"]).origin
	check(absf(minf(foot.y,foot_far.y)-(HeroRig.FEET_Y+rig.rest["foot_near"].y*HeroRig.HEIGHT))<.001,"the lower foot ends up at ground height")
	var largest_step := 0.0
	var previous := HeroPrototypePoses.walk_pose(0)
	for index in range(1,int(HeroPrototypePoses.WALK_TIME*60)+1):
		var pose := HeroPrototypePoses.walk_pose(index/60.0)
		for bone in pose: largest_step = maxf(largest_step,absf(float(pose[bone])-float(previous.get(bone,0.0))))
		previous = pose
	check(largest_step<.1,"the walk loops smoothly (%.3f rad per frame)" % largest_step)
	rig.queue_free()
