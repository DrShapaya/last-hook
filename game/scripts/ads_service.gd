class_name AdsService
extends Node

signal availability_changed
signal fullscreen_changed(active: bool)
signal rewarded_finished(earned: bool)
signal reward_verified
signal banner_layout_changed

const CONFIG_PATH := "res://data/yandex_ads.json"
const APP_METRICA_CONFIG_PATH := "res://data/appmetrica.json"
const RETRY_SECONDS := 30.0
const LOAD_TIMEOUT := 45.0
var backend: Object
var supported := false
var initialized := false
var rewarded_ready := false
var interstitial_ready := false
var fullscreen := false
var banner_height := 0
var test_mode := true
var units: Dictionary = {}
var _menu := false
var _banner_requested := false
var _reward_earned := false
var _showing := ""
var _loading: Dictionary = {}
var _retry_after: Dictionary = {}

func setup() -> void:
	if not OS.has_feature("android") or not Engine.has_singleton("LastHookAds"):
		return
	attach_backend(Engine.get_singleton("LastHookAds"),OS.is_debug_build())

# Also allows a deterministic backend in lifecycle tests without SDK requests.
func attach_backend(native: Object, use_demo_units: bool) -> void:
	backend = native
	test_mode = use_demo_units
	units = JSON.parse_string(FileAccess.get_file_as_string(CONFIG_PATH))["ad_units"].duplicate()
	var appmetrica_config: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(APP_METRICA_CONFIG_PATH))
	if backend.has_method("setAppMetricaApiKey"):
		backend.call("setAppMetricaApiKey",str(appmetrica_config.get("api_key","")))
	if test_mode:
		units = {"revive_rewarded":"demo-rewarded-yandex", "level_complete_interstitial":"demo-interstitial-yandex", "main_menu_banner":"demo-banner-yandex"}
	supported = true
	backend.connect("initialized",_on_initialized,CONNECT_DEFERRED)
	backend.connect("rewarded_loaded",_on_rewarded_loaded,CONNECT_DEFERRED)
	backend.connect("interstitial_loaded",_on_interstitial_loaded,CONNECT_DEFERRED)
	backend.connect("reward_earned",_on_reward_earned,CONNECT_DEFERRED)
	backend.connect("rewarded_closed",_on_rewarded_closed,CONNECT_DEFERRED)
	backend.connect("interstitial_closed",_on_interstitial_closed,CONNECT_DEFERRED)
	backend.connect("ad_failed",_on_failed,CONNECT_DEFERRED)
	backend.connect("banner_height_changed",_on_banner_height,CONNECT_DEFERRED)
	backend.call("initialize")

func _on_initialized() -> void:
	if initialized: return
	initialized = true
	_report_event("app_initialized")
	preload_fullscreen()
	if _menu: _load_banner()
	availability_changed.emit()

func _now() -> float:
	return Time.get_ticks_msec()/1000.0

func _can_load(kind: String) -> bool:
	return initialized and not fullscreen and not _loading.has(kind) and _now()>=float(_retry_after.get(kind,0))

func preload_fullscreen() -> void:
	if not rewarded_ready and _can_load("rewarded"):
		_loading["rewarded"] = _now()
		backend.call("loadRewarded",str(units["revive_rewarded"]))
	if not interstitial_ready and _can_load("interstitial"):
		_loading["interstitial"] = _now()
		backend.call("loadInterstitial",str(units["level_complete_interstitial"]))

func set_main_menu(visible: bool) -> void:
	_menu = visible
	if not supported: return
	backend.call("setBannerVisible",visible and not fullscreen)
	if visible and not _banner_requested: _load_banner()

func _load_banner() -> void:
	if not _can_load("banner"): return
	_banner_requested = true
	backend.call("loadBanner",str(units["main_menu_banner"]))

func menu_banner_height() -> int:
	return banner_height if supported and _menu else 0

func request_rewarded() -> bool:
	if not rewarded_ready or fullscreen:
		preload_fullscreen()
		return false
	rewarded_ready = false
	_report_event("rewarded_requested")
	_reward_earned = false
	_showing = "rewarded"
	_set_fullscreen(true)
	backend.call("showRewarded")
	return true

func show_level_complete() -> bool:
	# A late load must never interrupt the next run or a menu screen.
	if not interstitial_ready or fullscreen:
		preload_fullscreen()
		return false
	interstitial_ready = false
	_report_event("interstitial_requested")
	_showing = "interstitial"
	_set_fullscreen(true)
	backend.call("showInterstitial")
	return true

func _set_fullscreen(active: bool) -> void:
	fullscreen = active
	backend.call("setBannerVisible",_menu and not active)
	fullscreen_changed.emit(active)
	availability_changed.emit()

func _on_rewarded_loaded() -> void:
	_loading.erase("rewarded")
	rewarded_ready = true
	availability_changed.emit()

func _on_interstitial_loaded() -> void:
	_loading.erase("interstitial")
	interstitial_ready = true

func _on_reward_earned() -> void:
	if _showing=="rewarded" and fullscreen and not _reward_earned:
		_reward_earned = true
		_report_event("rewarded_earned")
		reward_verified.emit()

func _on_rewarded_closed() -> void:
	if _showing!="rewarded": return
	var earned := _reward_earned
	_reward_earned = false
	_showing = ""
	_set_fullscreen(false)
	rewarded_finished.emit(earned)
	preload_fullscreen()

func _on_interstitial_closed() -> void:
	if _showing!="interstitial": return
	_showing = ""
	_set_fullscreen(false)
	preload_fullscreen()

func _on_banner_height(height: int) -> void:
	banner_height = maxi(0,height)
	banner_layout_changed.emit()

func _report_event(event_name: String) -> void:
	if is_instance_valid(backend) and backend.has_method("reportEvent"):
		backend.call("reportEvent",event_name)

func report_event(event_name: String) -> void:
	_report_event(event_name)

func _on_failed(kind: String, message: String) -> void:
	print("Yandex Ads / %s: %s" % [kind,message])
	var format := kind.get_slice("_",0)
	_loading.erase(format)
	_retry_after[format] = _now()+RETRY_SECONDS
	if format=="rewarded": rewarded_ready = false
	if format=="interstitial": interstitial_ready = false
	if kind=="banner_load": _banner_requested = false
	if kind.ends_with("_show") and _showing==format:
		_showing = ""
		_reward_earned = false
		_set_fullscreen(false)
		if format=="rewarded": rewarded_finished.emit(false)
	availability_changed.emit()

func _process(_delta: float) -> void:
	# No retry loop on no-fill/offline errors. A later user action may retry.
	for kind in _loading.keys():
		if _now()-float(_loading[kind])>LOAD_TIMEOUT:
			_on_failed(str(kind)+"_load","Loading timed out")

func _exit_tree() -> void:
	if is_instance_valid(backend): backend.call("setBannerVisible",false)
