@echo off
setlocal
title Last Hook - Android release APK

rem Double-click this file to build the current project as a signed release APK.
rem The output path is stable and is never versioned or renamed:
rem   Builds\Android\LastHook-release.apk

cd /d "%~dp0"
echo.
echo === Last Hook: Android release APK ===
echo.

powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0tools\build.ps1" -Target Android -Release -SkipTests
set "CODE=%ERRORLEVEL%"

if not "%CODE%"=="0" (
    echo.
    echo Release APK build failed with code %CODE%.
    echo See artifacts\export-android.log and the build logs for details.
    pause
    exit /b %CODE%
)

if not exist "%~dp0Builds\Android\LastHook-release.apk" (
    echo.
    echo Build finished but the APK was not found:
    echo %~dp0Builds\Android\LastHook-release.apk
    pause
    exit /b 2
)

echo.
echo APK ready:
echo %~dp0Builds\Android\LastHook-release.apk
start "" explorer.exe /select,"%~dp0Builds\Android\LastHook-release.apk"
pause
exit /b 0
