@echo off
setlocal
rem Release build: Release.cmd [version] [-Force]
rem   Release.cmd           - new release: the current version from game_model.gd,
rem                           or the next patch (0.13.0 -> 0.13.1) if it is already built
rem   Release.cmd 0.14.0    - set the version everywhere, then build
rem Result: Builds\Versions\v<version>\ with the Windows zip, the signed APK and SHA256SUMS.txt
set "VERSION_ARG="
if not "%~1"=="" if /i not "%~1"=="-Force" set "VERSION_ARG=-Version %~1"
set "FORCE_ARG="
if /i "%~1"=="-Force" set "FORCE_ARG=-Force"
if /i "%~2"=="-Force" set "FORCE_ARG=-Force"
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0tools\release.ps1" %VERSION_ARG% %FORCE_ARG%
set "CODE=%ERRORLEVEL%"
if not "%CODE%"=="0" echo Release build failed with code %CODE%.
pause
exit /b %CODE%
