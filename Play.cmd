@echo off
setlocal
set "LASTHOOK_SAVE_DIR=%~dp0UserData"
if exist "%~dp0Builds\Windows\LastHook.exe" (
  start "Last Hook" "%~dp0Builds\Windows\LastHook.exe"
) else (
  start "Last Hook" "%~dp0tools\godot\Godot_v4.7.2-stable_win64.exe" --path "%~dp0game"
)
