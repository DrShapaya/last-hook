class_name BuildCache
extends RefCounted

# Answers that cost a lot to work out and are the same every time a level is
# built again (on each return to the camp and each restart). Static only:
# nothing here holds a node or a world.

# The back plane of a platform (MountainVisuals.platform_back), per level.
static var platform_backs := {}
const LIMIT := 4000

static func get_back(key: String) -> float:
	return float(platform_backs.get(key,NAN))

static func put_back(key: String, value: float) -> void:
	if platform_backs.size()>LIMIT: platform_backs.clear()
	platform_backs[key] = value

static func clear() -> void:
	platform_backs.clear()
