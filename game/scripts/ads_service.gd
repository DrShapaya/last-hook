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
# Two banner placements of the same size at the top of the screen: the main
# menu's and the climb's. Each has its own ad unit, wish to be shown, request
# state and measured native height; a screen makes room only for its own.
const BANNERS := {"menu":"main_menu_banner","play":"gameplay_banner"}
var banner_height := 0
var gameplay_banner_height := 0
var _wanted := {"menu":false,"play":false}
var _requested := {"menu":false,"play":false}
var _native_heights := {"menu":0,"play":0}
var test_mode := true
var units: Dictionary = {}
var _menu := false
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
		units = {"revive_rewarded":"demo-rewarded-yandex", "level_complete_interstitial":"demo-interstitial-yandex", "main_menu_banner":"demo-banner-yandex", "gameplay_banner":"demo-banner-yandex"}
	supported = true
	backend.connect("initialized",_on_initialized,CONNECT_DEFERRED)
	backend.connect("rewarded_loaded",_on_rewarded_loaded,CONNECT_DEFERRED)
	backend.connect("interstitial_loaded",_on_interstitial_loaded,CONNECT_DEFERRED)
	backend.connect("reward_earned",_on_reward_earned,CONNECT_DEFERRED)
	backend.connect("rewarded_closed",_on_rewarded_closed,CONNECT_DEFERRED)
	backend.connect("interstitial_closed",_on_interstitial_closed,CONNECT_DEFERRED)
	backend.connect("ad_failed",_on_failed,CONNECT_DEFERRED)
	backend.connect("banner_slot_height_changed",_on_banner_height,CONNECT_DEFERRED)
	# A screen asked for its banner before the plugin was attached (setup
	# runs a frame later): pass that wish on now, or the banner loads hidden
	# and shows only after the next screen switch.
	for name in BANNERS:
		if _wanted[name]: backend.call("setBannerSlotVisible",name,not fullscreen)
	backend.call("initialize")

func _on_initialized() -> void:
	if initialized: return
	initialized = true
	_report_event("app_initialized")
	preload_fullscreen()
	for name in BANNERS:
		if _wanted[name]: _load_banner(name)
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
	_set_banner("menu",visible)

# The climb's own banner: shown while a run is played.
func set_gameplay(visible: bool) -> void:
	_set_banner("play",visible)

func _set_banner(name: String, visible: bool) -> void:
	_wanted[name] = visible
	_apply_banner_height()
	if not supported: return
	backend.call("setBannerSlotVisible",name,visible and not fullscreen)
	if visible and not bool(_requested[name]): _load_banner(name)

# Failures and retries are kept per placement ("banner", "bannerplay").
static func _banner_kind(name: String) -> String:
	return "banner" if name=="menu" else "banner"+name

func _load_banner(name: String) -> void:
	if not _can_load(_banner_kind(name)) or not units.has(BANNERS[name]): return
	_requested[name] = true
	backend.call("loadBannerSlot",name,str(units[BANNERS[name]]))

func menu_banner_height() -> int:
	return banner_height if supported and _menu else 0

func play_banner_height() -> int:
	return gameplay_banner_height if supported and bool(_wanted["play"]) else 0

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
	for name in BANNERS: backend.call("setBannerSlotVisible",name,bool(_wanted[name]) and not active)
	_apply_banner_height()
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

func _on_banner_height(name: String, height: int) -> void:
	# Sent once a banner has loaded and been measured (and again whenever it
	# is shown). Only the screen that shows it makes room for it.
	if not _native_heights.has(name): return
	_native_heights[name] = maxi(0,height)
	_apply_banner_height()

func _apply_banner_height() -> void:
	var menu := int(_native_heights["menu"]) if bool(_wanted["menu"]) and not fullscreen else 0
	var play := int(_native_heights["play"]) if bool(_wanted["play"]) and not fullscreen else 0
	if menu==banner_height and play==gameplay_banner_height: return
	banner_height = menu
	gameplay_banner_height = play
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
	for name in BANNERS:
		if kind==_banner_kind(name)+"_load":
			_requested[name] = false
			_native_heights[name] = 0
			_apply_banner_height()
	if kind.ends_with("_show") and _showing==format:
		_showing = ""
		_reward_earned = false
		_set_fullscreen(false)
		if format=="rewarded": rewarded_finished.emit(false)
	availability_changed.emit()

func _process(_delta: float) -> void:
	# A failed banner tries again on its own after RETRY_SECONDS while its
	# screen stays open; it no longer waits for a screen switch.
	if initialized and not fullscreen:
		for name in BANNERS:
			if bool(_wanted[name]) and not bool(_requested[name]): _load_banner(name)
	for kind in _loading.keys():
		if _now()-float(_loading[kind])>LOAD_TIMEOUT:
			_on_failed(str(kind)+"_load","Loading timed out")

func _exit_tree() -> void:
	if is_instance_valid(backend):
		for name in BANNERS: backend.call("setBannerSlotVisible",name,false)
