@echo off
setlocal
start "Last Hook Animations" "%~dp0tools\godot\Godot_v4.7.2-stable_win64.exe" --path "%~dp0game" --script res://tools/animation_preview.gd
