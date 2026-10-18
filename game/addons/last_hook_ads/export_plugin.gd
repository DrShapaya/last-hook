@tool
extends EditorPlugin

var android_export: AndroidAdsExport

func _enter_tree() -> void:
	android_export = AndroidAdsExport.new()
	add_export_plugin(android_export)

func _exit_tree() -> void:
	remove_export_plugin(android_export)

class AndroidAdsExport extends EditorExportPlugin:
	func _get_name() -> String:
		return "LastHookAds"

	func _supports_platform(platform: EditorExportPlatform) -> bool:
		return platform is EditorExportPlatformAndroid

	func _get_android_libraries(_platform: EditorExportPlatform, _debug: bool) -> PackedStringArray:
		return PackedStringArray(["res://addons/last_hook_ads/bin/LastHookAds.aar"])

	func _get_android_dependencies(_platform: EditorExportPlatform, _debug: bool) -> PackedStringArray:
		return PackedStringArray(["com.yandex.android:mobileads:8.5.0"])
