class_name ExplorerSprite
extends ExplorerRig

# One continuous textured surface; no detached body parts or frame swaps.
const SIZE := 1.18
const GRID := 40
const GRIP_UV := Vector2(.780,.270)
const ARM_PIVOT := Vector2(.666,.495)
const ANIMATION_NAMES := ["idle","throw","swing","flight","fall","land"]

var surface: MeshInstance3D
var material: ShaderMaterial
var state := "idle"
var phase := 0.0
var last_time := -1.0
var pose := Vector4.ZERO # arm, leg, tuck, head
var pack_sway := 0.0
var breath := 0.0
var squash := 0.0
var turn := 0.0
var lean := 0.0
var impact := 0.0
var previous_grounded := true
var previous_attached := false

func setup() -> void:
	if is_instance_valid(surface): return
	name = "WholeExplorer"
	surface = MeshInstance3D.new()
	surface.name = "Цельный спрайт"
	var vertices := PackedVector3Array()
	var uv := PackedVector2Array()
	var indices := PackedInt32Array()
	for y in range(GRID+1):
		for x in range(GRID+1):
			var point := Vector2(float(x)/GRID,float(y)/GRID)
			vertices.append(Vector3((point.x-.5)*SIZE,(.5-point.y)*SIZE,0))
			uv.append(point)
	for y in range(GRID):
		for x in range(GRID):
			var a := y*(GRID+1)+x
			indices.append_array(PackedInt32Array([a,a+GRID+1,a+1,a+1,a+GRID+1,a+GRID+2]))
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_TEX_UV] = uv
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays)
	surface.mesh = mesh
	surface.custom_aabb = AABB(Vector3(-1,-1,-.1),Vector3(2,2,.2))
	surface.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	material = ShaderMaterial.new()
	material.shader = preload("res://shaders/explorer_sprite.gdshader")
	material.set_shader_parameter("art",preload("res://assets/art/explorer-whole-v3.png"))
	material.set_shader_parameter("sprite_size",SIZE)
	surface.material_override = material
	add_child(surface)

static func smooth_weight(edge0: float, edge1: float, value: float) -> float:
	var t := clampf((value-edge0)/(edge1-edge0),0,1)
	return t*t*(3-2*t)

static func arm_weight(uv: Vector2) -> float:
	return smooth_weight(.665,.745,uv.x)*(1-smooth_weight(.49,.56,uv.y))

func animate(sim: RopeSim, target: Vector2, tether: bool, time: float) -> void:
	var dt := clampf(time-last_time,0,.1) if last_time>=0 else 0.0
	last_time = time
	phase += dt
	var direction := target-sim.pos
	# Hysteresis keeps tiny velocity changes near the swing apex from flipping art.
	if tether and absf(direction.x)>1.0:
		facing = signf(direction.x)
	elif not tether and absf(sim.vel.x)>1.5:
		facing = signf(sim.vel.x)
	var turn_target := 0.0 if facing>0 else PI
	turn = lerpf(turn,turn_target,1-exp(-dt*13))
	rotation.y = turn
	if sim.grounded and not previous_grounded: impact = .075
	if sim.attached and not previous_attached: impact = -.028
	previous_grounded = sim.grounded
	previous_attached = sim.attached
	impact *= exp(-dt*9)
	if sim.attached:
		state = "swing"
	elif tether:
		state = "throw"
	elif sim.grounded:
		state = "land" if impact>.006 else "idle"
	else:
		state = "fall" if sim.vel.y<-.6 else "flight"
	var speed := clampf(sim.vel.length()/9,0,1)
	var cycle := sin(phase*3.6)
	var desired := Vector4(-.07,.015*cycle,0,.012*sin(phase*1.9))
	var desired_lean := clampf(-sim.vel.x*.025,-.22,.22)
	match state:
		"swing":
			desired = Vector4(clampf(direction.angle()-PI*.35,-.14,.14),.065*cycle+sim.vel.x*facing*.008,.075+speed*.035,-.018*cycle)
			desired_lean += clampf(-direction.x*.035,-.15,.15)
		"throw":
			desired = Vector4(.12,.05*cycle,.06,-.025)
		"flight":
			desired = Vector4(-.03,.10*cycle,.12,.025)
			desired_lean += clampf(sim.vel.y*.009,0,.07)
		"fall":
			desired = Vector4(-.20,.14*cycle,-.025,-.035)
			desired_lean += .04*sin(phase*2.2)
		"land":
			desired.z = impact*.8
	var blend := 1-exp(-dt*10)
	pose = pose.lerp(desired,blend)
	lean = lerpf(lean,desired_lean,1-exp(-dt*8))
	rotation.z = lean
	pack_sway = lerpf(pack_sway,clampf(sim.vel.x*facing*.005,-.035,.035)+.008*sin(phase*2.3),1-exp(-dt*6))
	breath = .004*sin(phase*1.9)
	squash = lerpf(squash,impact,1-exp(-dt*18))
	scale = Vector3(1+squash,1-squash,1)
	position.y = breath
	material.set_shader_parameter("pose",pose)
	material.set_shader_parameter("pack_sway",pack_sway)
	material.set_shader_parameter("breath",breath)

func grip_position() -> Vector3:
	# Matches the vertex shader at the painted gripping hand, including yaw/lean.
	var point := Vector2((GRIP_UV.x-.5)*SIZE,(.5-GRIP_UV.y)*SIZE)
	var pivot := Vector2((ARM_PIVOT.x-.5)*SIZE,(.5-ARM_PIVOT.y)*SIZE)
	point = point.lerp(pivot+(point-pivot).rotated(pose.x),arm_weight(GRIP_UV))
	return to_global(Vector3(point.x,point.y,.025))
