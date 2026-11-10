class_name AssetWarmup
extends RefCounted

# Loads the art the climb instantiates lazily (flag, platform and treasure
# models, plant and loot sprites) on worker threads while the menu is up.
# Otherwise the first flag, chest or tuft of a run is read from disk on the
# main thread in the middle of a climb: a 30-100 ms stall on a PC, far more
# on a phone. Loaded resources are held here so the cache keeps them.

# The 3D hero too: each run builds a new one, and once the menu had freed
# the last, its model was read from disk again on the Start press (~100 ms
# on a PC).
const FOLDERS := ["res://assets/models","res://assets/sprites","res://assets/hero"]
const EXTENSIONS := ["glb","png","tres","res"]
# Single files the climber builds with on every Start (ExplorerView).
const FILES := ["res://assets/art/modular-pack-v1/rope-albedo.png","res://assets/art/modular-pack-v1/hook-head.png"]

static var _pending: Array[String] = []
static var _held: Array[Resource] = []
static var _started := false

static func start() -> void:
	if _started: return
	_started = true
	for folder in FOLDERS: _collect(folder)
	_pending.append_array(FILES)
	for path in _pending: ResourceLoader.load_threaded_request(path)

static func _collect(folder: String) -> void:
	# list_directory reports exported (remapped) resources by their source names.
	for entry in ResourceLoader.list_directory(folder):
		if entry.ends_with("/"):
			_collect(folder.path_join(entry.trim_suffix("/")))
		elif entry.get_extension().to_lower() in EXTENSIONS:
			_pending.append(folder.path_join(entry))

# Collects finished loads; cheap enough to call every frame.
static func poll() -> void:
	for index in range(_pending.size()-1,-1,-1):
		var path := _pending[index]
		var status := ResourceLoader.load_threaded_get_status(path)
		if status==ResourceLoader.THREAD_LOAD_IN_PROGRESS: continue
		if status==ResourceLoader.THREAD_LOAD_LOADED:
			var resource := ResourceLoader.load_threaded_get(path)
			if resource!=null: _held.append(resource)
		_pending.remove_at(index)

static func done() -> bool:
	return _started and _pending.is_empty()
