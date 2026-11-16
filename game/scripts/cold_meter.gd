class_name ColdMeter
extends RefCounted

# Cold of the blizzard: builds up inside a blizzard band, drains on supports
# and fast at a campfire. It only slows the hero; rope length is untouched.

var cold := 0.0

func step(dt: float, presence: Dictionary, grounded: bool, near_fire: bool) -> void:
	var rate := 0.0
	if near_fire:
		rate = -1.0/2.5
	elif presence.get("kind","")=="blizzard" and bool(presence.get("inside",false)):
		var name := String(presence.get("phase",{}).get("name","calm"))
		if name=="active": rate = -1.0/10.0 if grounded else 1.0/16.0
		elif name=="telegraph": rate = -1.0/10.0 if grounded else 1.0/40.0
		else: rate = -1.0/6.0 if grounded else -1.0/30.0
	else:
		rate = -1.0/8.0
	cold = clampf(cold+rate*dt,0.0,1.0)

func swing_scale() -> float:
	return 1.0-.35*cold

func reel_scale() -> float:
	return 1.0-.35*cold

func throw_scale() -> float:
	return 1.0-.25*cold

func walk_scale() -> float:
	return 1.0-.3*cold
