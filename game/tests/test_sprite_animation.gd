extends SceneTree

var checks := 0
var failures: Array[String] = []

func _initialize() -> void:
	call_deferred("run_tests")

func check(ok: bool, description: String) -> void:
	checks += 1
	if not ok:
		failures.append(description)
		push_error("ANIMATION FAILED: "+description)

func create_sprite() -> ExplorerSprite:
	var sprite := ExplorerSprite.new()
	root.add_child(sprite)
	sprite.setup()
	return sprite

func run_tests() -> void:
	var rig := create_sprite()
	var sim := RopeSim.new()
	check(rig.get_child_count()==1 and rig.surface.mesh.get_surface_count()==1,"character uses one continuous image surface")
	check((rig.material.get_shader_parameter("art") as Texture2D).resource_path.ends_with("explorer-whole-v3.png"),"the generated whole-character image is used in the game")
	rig.animate(sim,Vector2(2,3),false,0)
	check(rig.state=="idle","grounded character breathes in idle")
	sim.grounded = false
	rig.animate(sim,Vector2(2,3),true,1.0/60)
	check(rig.state=="throw","flying hook starts the throw pose")
	sim.attached = true
	rig.animate(sim,Vector2(2,3),true,2.0/60)
	check(rig.state=="swing","attachment starts swing motion")
	sim.attached = false
	sim.vel = Vector2(4,5)
	rig.animate(sim,Vector2(2,3),false,3.0/60)
	check(rig.state=="flight","ascending player tucks legs for flight")
	sim.vel.y = -5
	rig.animate(sim,Vector2(2,3),false,4.0/60)
	check(rig.state=="fall","descending player enters falling motion")
	sim.grounded = true
	sim.vel = Vector2.ZERO
	rig.animate(sim,Vector2(2,3),false,5.0/60)
	check(rig.state=="land" and rig.squash>0,"touchdown eases into a landing compression")
	for index in range(6,120): rig.animate(sim,Vector2(2,3),false,index/60.0)
	check(rig.state=="idle" and absf(rig.squash)<.0001,"landing settles back to idle")
	var frozen := rig.transform
	var frozen_pose := rig.pose
	rig.animate(sim,Vector2(2,3),false,119.0/60)
	check(rig.transform.is_equal_approx(frozen) and rig.pose.is_equal_approx(frozen_pose),"paused animation clock freezes all visual motion")
	# A single elapsed-time sequence crosses every state and both turn directions.
	var largest_pose_step := 0.0
	var largest_lean_step := 0.0
	var largest_yaw_step := 0.0
	for index in range(360):
		var old_pose := rig.pose
		var old_lean := rig.rotation.z
		var old_yaw := rig.rotation.y
		sim.grounded = index<30 or index>=300
		sim.attached = index>=60 and index<180
		sim.vel = Vector2(-7 if index>=120 and index<240 else 7,5 if index<220 else -6)
		var tether := index>=30 and index<180
		rig.animate(sim,Vector2(-3 if index>=120 else 3,4),tether,2+index/60.0)
		largest_pose_step = maxf(largest_pose_step,rig.pose.distance_to(old_pose))
		largest_lean_step = maxf(largest_lean_step,absf(rig.rotation.z-old_lean))
		largest_yaw_step = maxf(largest_yaw_step,absf(rig.rotation.y-old_yaw))
	check(largest_pose_step<.07 and largest_lean_step<.09,"pose changes blend without jumps at throw/catch/release/fall/landing")
	check(largest_yaw_step<.65,"direction changes rotate smoothly rather than instantly mirroring")
	var a := create_sprite()
	var b := create_sprite()
	sim.grounded = false
	sim.attached = true
	sim.vel = Vector2(5,-2)
	for index in range(121): a.animate(sim,Vector2(3,4),true,index/30.0)
	for index in range(481): b.animate(sim,Vector2(3,4),true,index/120.0)
	check(a.pose.distance_to(b.pose)<.01 and absf(a.lean-b.lean)<.002,"animation timing stays consistent at 30 and 120 FPS")
	var expected := Vector2((ExplorerSprite.GRIP_UV.x-.5)*ExplorerSprite.SIZE,(.5-ExplorerSprite.GRIP_UV.y)*ExplorerSprite.SIZE)
	var pivot := Vector2(.166,.005)*ExplorerSprite.SIZE
	expected = expected.lerp(pivot+(expected-pivot).rotated(a.pose.x),ExplorerSprite.arm_weight(ExplorerSprite.GRIP_UV))
	check(a.grip_position().distance_to(a.to_global(Vector3(expected.x,expected.y,.025)))<.00001,"rope endpoint follows the deformed painted hand")
	var target_pose := a.pose
	# A throttled frame must remain bounded, with no jump to a distant sine phase.
	a.animate(sim,Vector2(3,4),true,100)
	check(a.pose.distance_to(target_pose)<.05,"a long frame does not skip to a remote animation phase")
	rig.free()
	a.free()
	b.free()
	print("SPRITE_ANIMATION_TESTS ",checks," checks, ",failures.size()," failures")
	quit(0 if failures.is_empty() else 1)
