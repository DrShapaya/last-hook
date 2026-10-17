class_name PracticeLayout
extends MountainLayout

const HEIGHT := 47.4
const SEED := 58273
const POINTS := [Vector2(1.6,4),Vector2(3.4,6.4),Vector2(5.6,9.05),
	Vector2(8.8,12),Vector2(11.8,14.9),Vector2(8.5,18),Vector2(5.2,21.2),
	Vector2(2,24.2),Vector2(-1.2,27.3),Vector2(-4.5,30.5),Vector2(-7.6,33.5),
	Vector2(-4.1,36.6),Vector2(-.6,39.6),Vector2(2.7,43),Vector2(5.9,46.2)]

func main_point(index: int) -> Vector2:
	if index<POINTS.size(): return POINTS[index]
	return POINTS[-1]+Vector2(0,(index-POINTS.size()+1)*3.0)
