extends SceneTree

var checks := 0
var failures: Array[String] = []

func _initialize() -> void:
	call_deferred("run_tests")

func check(condition: bool, description: String) -> void:
	checks += 1
	if not condition:
		failures.append(description)
		push_error(description)

func run_tests() -> void:
	var directory := OS.get_environment("LASTHOOK_SAVE_DIR")
	if directory.is_empty():
		quit(2)
		return
	DirAccess.make_dir_recursive_absolute(directory)
	var rig := load("res://scenes/player.tscn").instantiate() as ExplorerRig
	root.add_child(rig)
	var child_count := rig.get_child_count()
	rig.setup()
	check(rig.authored and rig.head is Sprite3D and rig.grip is Marker3D,"the game binds editable scene nodes and its rope marker")
	rig.setup()
	check(rig.get_child_count()==child_count and rig.shoulders.size()==2,"binding does not rebuild or duplicate authored parts")
	rig.head.position += Vector3(.03,.02,0)
	rig.head.scale *= 1.12
	rig.shoulders[0].position += Vector3(-.025,.015,0)
	rig.shoulders[0].rotation.z += .12
	rig.elbows[1].position = Vector3(.015,-.175,.01)
	rig.hands[1].position = Vector3(.012,-.145,.015)
	rig.grip.position = Vector3(.02,-.04,.03)
	var expected_head := rig.head.transform
	var expected_shoulder := rig.shoulders[0].transform
	var packed := PackedScene.new()
	var packed_ok := packed.pack(rig)==OK
	var path := directory.path_join("editable-player-roundtrip.tscn")
	check(packed_ok and ResourceSaver.save(packed,path)==OK,"manual edits can be saved as an ordinary Godot scene")
	var loaded := load(path).instantiate() as ExplorerRig
	root.add_child(loaded)
	loaded.setup()
	check(loaded.head.transform.is_equal_approx(expected_head) and loaded.shoulders[0].transform.is_equal_approx(expected_shoulder),"head size and shoulder placement survive saving and reopening")
	var sim := RopeSim.new()
	sim.vel = Vector2.ZERO
	sim.grounded = true
	loaded.animate(sim,Vector2(3,3),false,0)
	check(loaded.shoulders[0].transform.is_equal_approx(expected_shoulder),"idle animation preserves the user's authored resting shoulder pose")
	loaded.animate_limbs = false
	var frozen_arm := loaded.shoulders[1].transform
	var frozen_leg := loaded.hips[0].transform
	sim.vel = Vector2(5,-3)
	sim.attached = true
	loaded.animate(sim,Vector2(-3,3),true,1)
	check(loaded.shoulders[1].transform.is_equal_approx(frozen_arm) and loaded.hips[0].transform.is_equal_approx(frozen_leg),"animation can be disabled to keep the assembled limb pose")
	check(loaded.grip_position().is_equal_approx(loaded.hands[1].to_global(Vector3(.02,-.04,.03))),"the rope uses the user-positioned Grip marker")
	var shoulder := Vector2(loaded.shoulders[1].position.x,loaded.shoulders[1].position.y)
	var destination := shoulder+Vector2(.20,.12)
	loaded.pose_arm(1,destination,-1)
	var wrist := loaded.to_local(loaded.hands[1].global_position)
	check(Vector2(wrist.x,wrist.y).distance_to(destination)<.001 and loaded.elbows[1].position.is_equal_approx(Vector3(.015,-.175,.01)),"arm aiming uses edited bone lengths and directions without moving their joints")
	rig.free()
	loaded.free()
	var output := FileAccess.open(directory.path_join("character-editing-test-report.json"),FileAccess.WRITE)
	output.store_string(JSON.stringify({"checks":checks,"failures":failures,"passed":failures.is_empty()},"\t"))
	output.close()
	print("CHARACTER_EDITING_TESTS ",checks," checks, ",failures.size()," failures")
	quit(0 if failures.is_empty() else 1)
