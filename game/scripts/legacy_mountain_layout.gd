class_name LegacyMountainLayout
extends MountainLayout

# Generator v4 remains in use for locations outside the current first-location work.
var next_point := Vector2.ZERO
var previous_point := Vector2.ZERO

func setup(world_seed: int, biome: int) -> void:
	super.setup(world_seed,biome)
	ledges[0] = {"left":-5.8,"right":5.8,"top":.15}
	var random := rng(0,19)
	next_point = Vector2(random.randf_range(1.5,2.1)*(-1 if random.randf()<.5 else 1),random.randf_range(3.8,4.3))

func _add_anchor(point: Vector2, kind: int, dimensions: Vector2, primary: bool = false) -> int:
	var id := super._add_anchor(point,kind,dimensions,primary)
	anchors[id].erase("polygon")
	anchors[id]["shape"] = "rectangle"
	return id

func outer_edge(y: float, side: int) -> float:
	var index := int(floor(y/4))
	return side*rng(index,30+side).randf_range(3.9,5.9)

func outside(point: Vector2, _margin: float = .65) -> bool:
	return absf(point.x)>9.5

func generate_to(height: float, is_finite: bool, summit_height: float) -> void:
	finite = is_finite
	summit = summit_height
	while next_point.y<height and (not finite or next_point.y<=summit-.4):
		var random := rng(row,1)
		var point := next_point
		var zone := clampi(int(point.y/20),0,5)
		var kind := 2 if row>1 and random.randf()<.23 else 0
		var id := _add_anchor(point,kind,Vector2(random.randf_range(1.5,2.2),random.randf_range(.5,.8)),true)
		main_route.append(id)
		if row>0 and row%5==0:
			ledges.append({"left":point.x+signf(point.x)*.35-1.15,"right":point.x+signf(point.x)*.35+1.15,"top":point.y-1.2})
		_add_find(point+Vector2(-signf(point.x)*.4,-1.15),zone,false)
		if row>=3 and row%3==0:
			var side := signf(point.x)
			var bonus := Vector2(side*random.randf_range(4.3,4.6),point.y+random.randf_range(.8,1.2))
			var extra_kind := (4 if zone>=5 else 3) if zone>=3 else 1
			_add_anchor(bonus,extra_kind,Vector2(1.2,.6))
			_add_find(bonus+Vector2(0,-.75),zone,true)
			obstacles.append({"pos":Vector2(side*5.8,point.y-.65),"dimensions":Vector2(random.randf_range(1.2,1.8),random.randf_range(.7,1.3))})
		previous_point = point
		row += 1
		var step_random := rng(row,2)
		var rise := step_random.randf_range(2.7,3.35)
		var x := -signf(point.x)*step_random.randf_range(1.5,2.2)
		var span := Vector2(x-point.x,rise)
		if span.length()>5: x = point.x+signf(span.x)*sqrt(25-rise*rise)
		next_point = Vector2(x,point.y+rise)
	if finite and height>=summit and not summit_added:
		main_route.append(_add_anchor(Vector2(previous_point.x,summit+.9),0,Vector2(2,.6),true))
		ledges.append({"left":previous_point.x-1.5,"right":previous_point.x+1.5,"top":summit-.25})
		summit_added = true
