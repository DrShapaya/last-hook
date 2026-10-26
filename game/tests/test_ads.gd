extends SceneTree

var checks := 0
var failures: Array[String] = []

class FakeAds extends RefCounted:
	signal initialized
	signal rewarded_loaded
	signal interstitial_loaded
	signal reward_earned
	signal rewarded_closed
	signal interstitial_closed
	signal ad_failed(kind: String, message: String)
	signal banner_height_changed(height: int)
	var rewards_shown := 0
	var interstitials_shown := 0
	var reward_loads := 0
	var interstitial_loads := 0
	var banners_loaded := 0
	var banner_visible := false
	var reward_id := ""
	var reported_events: Array[String] = []
	func initialize() -> void: initialized.emit()
	func loadRewarded(id: String) -> void:
		reward_loads += 1
		reward_id = id
	func loadInterstitial(_id: String) -> void: interstitial_loads += 1
	func loadBanner(_id: String) -> void: banners_loaded += 1
	func showRewarded() -> void: rewards_shown += 1
	func showInterstitial() -> void: interstitials_shown += 1
	func setBannerVisible(visible: bool) -> void: banner_visible = visible
	func reportEvent(event_name: String) -> void: reported_events.append(event_name)

func _initialize() -> void:
	call_deferred("run_tests")

func check(condition: bool, description: String) -> void:
	checks += 1
	if not condition:
		failures.append(description)
		push_error("ADS FAILED: "+description)

func flush() -> void:
	await process_frame
	await process_frame

func rescue_fixture(game) -> void:
	game.start_run(false)
	game.run_seed = 58273
	game._create_world(58273,0,126)
	var grip: Dictionary = game.world.anchor_by_id(game.world.main_route[0])
	game.safe_anchor_id = grip["id"]
	game.safe_contact = grip["pos"]
	game.safe_position = game.safe_contact+Vector2(0,-2.8)
	game.sim.pos = game.safe_position
	game.sim.highest = game.sim.pos.y+3
	game.model.bag = [{"id":-50,"tier":5,"value":560}]
	game.model.profile["diamonds"] = 10
	game.fail_run("Ad rescue fixture")
	check(game.state=="revive" and game.revive_available(),"fixture offers a safe recovery")

func run_tests() -> void:
	var directory := OS.get_environment("LASTHOOK_SAVE_DIR")
	if directory.is_empty():
		quit(2)
		return
	var game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	game.set_physics_process(false)
	game.model.profile = GameModel.fresh_profile()
	check(not game.ads.supported and not game.ads.request_rewarded(),"desktop has no native ads and cannot award a reward")
	var native := FakeAds.new()
	game.ads.attach_backend(native,true)
	await flush()
	check(native.banner_visible,"the menu's banner request made before the plugin attached reaches it at launch")
	check("app_initialized" in native.reported_events,"AppMetrica receives the SDK initialization event")
	check(native.reward_id=="demo-rewarded-yandex","debug build requests demo inventory")
	check(native.reward_loads==1 and native.interstitial_loads==1,"SDK initialization preloads each fullscreen format once")
	game.ads.preload_fullscreen()
	check(native.reward_loads==1,"concurrent preload requests are deduplicated")
	game.show_menu()
	await flush()
	check("menu_opened" in native.reported_events,"AppMetrica receives menu events")
	check(native.banner_visible and native.banners_loaded==1,"banner loads and is visible in the main menu")
	# The native banner is docked at the top; menu controls must start below it
	# while the section bar stays anchored to the bottom.
	for dimensions in [Vector2i(432,960),Vector2i(540,960),Vector2i(1280,800)]:
		root.size = dimensions
		native.banner_height_changed.emit(110)
		await flush()
		var first := INF
		var lowest := 0.0
		for button in game.hud.content.find_children("*","Button",true,false):
			first = minf(first,button.get_global_rect().position.y)
			lowest = maxf(lowest,button.get_global_rect().end.y)
		check(first>=110,"menu controls start below the top banner at %s" % dimensions)
		check(lowest<=game.get_viewport().get_visible_rect().size.y+1,"menu controls stay inside the viewport at %s" % dimensions)
	rescue_fixture(game)
	check(not native.banner_visible,"banner hides before gameplay and modal screens")
	var test_buttons := 0
	for button in game.hud.content.find_children("*","Button",true,false):
		if button.text=="Тестовое продолжение": test_buttons += 1
	check(test_buttons==0,"Android SDK flow cannot expose the free debug continuation")
	game.revive("ad")
	check(not game.revive_used,"direct ad revival without earned authorization is rejected")
	game.request_ad_revive()
	game.hud.update_play()
	check(not game.ads.fullscreen and not game.revive_used,"unloaded ad leaves the recovery screen usable")
	check(game.hud.toast_label.visible,"unavailable-ad feedback is visible on the recovery screen")
	native.rewarded_loaded.emit()
	await flush()
	game.request_ad_revive()
	game.request_ad_revive()
	var run_before: String = game.run_id
	game.show_menu()
	game.start_run(false)
	game.revive("diamonds")
	check(native.rewards_shown==1 and game.ads.fullscreen and game.run_id==run_before and game.state=="revive" and game.model.profile["diamonds"]==10,"fullscreen blocks double taps, navigation, new runs and currency spending")
	check(game.hud.ad_blocker.visible,"fullscreen blocks GUI controls while Android opens the ad")
	native.rewarded_closed.emit()
	await flush()
	check(game.state=="revive" and not game.revive_used and not game.ads.fullscreen,"closing without reward does not revive and unlocks the screen")
	native.reward_earned.emit()
	await flush()
	check(not game.revive_used,"unsolicited reward outside a show is ignored")
	native.rewarded_loaded.emit()
	await flush()
	game.request_ad_revive()
	native.reward_earned.emit()
	native.reward_earned.emit()
	await flush()
	check(game.state=="revive" and not game.revive_used,"reward waits for dismissal before resuming physics")
	check(bool(game.model.profile["active"].get("ad_revive_earned",false)),"verified SDK reward is persisted before dismissal")
	var recovered = load("res://scenes/main.tscn").instantiate()
	root.add_child(recovered)
	recovered.set_physics_process(false)
	recovered.model = GameModel.new(directory.path_join("pending-reward.json"))
	recovered.model.profile = game.model.profile.duplicate(true)
	recovered.resume_run()
	check(recovered.state=="play" and recovered.revive_used and recovered.model.profile["diamonds"]==10,"process restart restores an earned revival without another ad or currency charge")
	check(not bool(recovered.model.profile["active"].get("ad_revive_earned",false)),"restored reward is consumed and cannot be redeemed again")
	recovered.queue_free()
	native.rewarded_closed.emit()
	await flush()
	check(game.state=="play" and game.revive_used and game.model.profile["diamonds"]==10 and game.model.bag_value()==560,"completed ad revives once while preserving currency and loot")
	check(game.model.profile["active"]["revive_used"],"earned revival is persisted in the active run")
	native.rewarded_closed.emit()
	native.reward_earned.emit()
	await flush()
	check(game.state=="play" and game.model.profile["diamonds"]==10,"duplicate SDK callbacks cannot duplicate a reward")
	rescue_fixture(game)
	native.rewarded_loaded.emit()
	await flush()
	game.request_ad_revive()
	native.ad_failed.emit("rewarded_show","offline")
	await flush()
	check(not game.ads.fullscreen and not game.revive_used and game.state=="revive","show failure unlocks UI without awarding revival")
	var loads_before := native.reward_loads
	game.request_ad_revive()
	game.ads.preload_fullscreen()
	check(native.reward_loads==loads_before,"show failures use cooldown instead of a request loop")
	# A reward belongs only to the run for which viewing was requested.
	game.ads._retry_after.clear()
	native.rewarded_loaded.emit()
	await flush()
	game.request_ad_revive()
	game.run_id += "-changed"
	native.reward_earned.emit()
	native.rewarded_closed.emit()
	await flush()
	check(not game.revive_used,"reward from another run is rejected")
	game.start_run(false)
	native.interstitial_loaded.emit()
	await flush()
	var shown_before := native.interstitials_shown
	game.finish_run(false)
	check(native.interstitials_shown==shown_before,"failed attempts do not trigger level-completion ads")
	game.start_run(false)
	game.preview = false
	game.finish_run(true)
	check(game.state=="result" and game.ads.fullscreen and native.interstitials_shown==shown_before+1,"successful summit settles rewards before showing one interstitial")
	game.finish_run(true)
	check(native.interstitials_shown==shown_before+1,"repeat completion cannot show the same interstitial twice")
	native.interstitial_closed.emit()
	await flush()
	check(not game.ads.fullscreen and game.state=="result","interstitial dismissal returns to the settled result")
	game.start_run(false)
	game.finish_run(true)
	check(not game.ads.fullscreen,"unloaded interstitial does not block completion")
	game.start_run(false)
	native.interstitial_loaded.emit()
	await flush()
	check(not game.ads.fullscreen and game.state=="play","late interstitial load never interrupts an active run")
	game.finish_run(false)
	game.show_menu()
	game.start_practice()
	game.finish_run(true)
	check(not game.ads.fullscreen and native.interstitials_shown==shown_before+1,"practice completion never shows an interstitial")
	var production := AdsService.new()
	root.add_child(production)
	production.attach_backend(FakeAds.new(),false)
	await flush()
	check(production.units=={"revive_rewarded":"R-M-20238117-1","level_complete_interstitial":"R-M-20238117-2","main_menu_banner":"R-M-20238117-3"},"release config uses all three owner-provided IDs")
	production.queue_free()
	var report := FileAccess.open(directory.path_join("ads-test-report.json"),FileAccess.WRITE)
	report.store_string(JSON.stringify({"checks":checks,"failures":failures,"passed":failures.is_empty()},"\t"))
	report.close()
	game.queue_free()
	await process_frame
	print("ADS_TESTS ",checks," checks, ",failures.size()," failures")
	quit(0 if failures.is_empty() else 1)
