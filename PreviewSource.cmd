@echo off
setlocal
set "LASTHOOK_SAVE_DIR=%~dp0UserData"
start "Last Hook Source Preview" "%~dp0tools\godot\Godot_v4.7.2-stable_win64.exe" --path "%~dp0game"
