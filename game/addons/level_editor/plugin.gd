@tool
extends EditorPlugin

# The «Уровни» main screen: the level editor of docs/LEVEL_PIPELINE.md.

const LevelEditor := preload("res://addons/level_editor/level_editor.gd")

var editor: Control

func _enter_tree() -> void:
	editor = LevelEditor.new()
	editor.godot_executable = OS.get_executable_path()
	EditorInterface.get_editor_main_screen().add_child(editor)
	_make_visible(false)

func _exit_tree() -> void:
	if is_instance_valid(editor): editor.queue_free()

func _has_main_screen() -> bool:
	return true

func _make_visible(visible: bool) -> void:
	if is_instance_valid(editor): editor.visible = visible

func _get_plugin_name() -> String:
	return "Уровни"

func _get_plugin_icon() -> Texture2D:
	return EditorInterface.get_editor_theme().get_icon("ImageTexture","EditorIcons")
