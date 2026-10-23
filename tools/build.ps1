param(
    [ValidateSet('All','Windows','Android')][string]$Target = 'All',
    [string]$AndroidSdkPath = 'C:\Users\isaev\AppData\Local\Android\Sdk',
    [string]$JavaSdkPath = 'C:\Program Files\Eclipse Adoptium\jdk-21.0.10.7-hotspot',
    [string]$ProjectPath = '',
    # Release mode exports without debug features and signs the APK with the
    # store key instead of the debug key.
    [switch]$Release,
    # Release.cmd uses this for a one-click APK export. Run the full suite
    # explicitly when you want a CI-style validation pass.
    [switch]$SkipTests,
    [string]$ReleaseKeystorePath = '',
    [string]$ReleaseKeystorePasswordFile = '',
    [string]$ReleaseKeyAlias = 'lasthook'
)
$ErrorActionPreference = 'Stop'
$taskRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$taskGodot = Join-Path $PSScriptRoot 'godot\Godot_v4.7.2-stable_win64_console.exe'
$taskProject = if ($ProjectPath) { [IO.Path]::GetFullPath($ProjectPath) } else { Join-Path $taskRoot 'game' }
$taskLocalAndroidSdk = Join-Path $PSScriptRoot 'android-sdk'
if (-not $PSBoundParameters.ContainsKey('AndroidSdkPath') -and (Test-Path -LiteralPath (Join-Path $taskLocalAndroidSdk 'platform-tools\adb.exe')) -and (Test-Path -LiteralPath (Join-Path $taskLocalAndroidSdk 'platforms\android-36\android.jar'))) {
    $AndroidSdkPath = $taskLocalAndroidSdk
}
$taskArtifacts = Join-Path $taskRoot 'artifacts'
$taskExport = if ($Release) { '--export-release' } else { '--export-debug' }
if ($Release -and $Target -in @('All','Android')) {
    if (-not $ReleaseKeystorePath) { $ReleaseKeystorePath = Join-Path $taskRoot 'Builds\RuStore\last-hook-release.keystore' }
    if (-not $ReleaseKeystorePasswordFile) { $ReleaseKeystorePasswordFile = Join-Path $taskRoot 'Builds\RuStore\last-hook-release-password.txt' }
    if (-not (Test-Path -LiteralPath $ReleaseKeystorePath)) { throw "Release keystore is missing: $ReleaseKeystorePath" }
    if (-not (Test-Path -LiteralPath $ReleaseKeystorePasswordFile)) { throw "Release keystore password file is missing: $ReleaseKeystorePasswordFile" }
}
New-Item -ItemType Directory -Path $taskArtifacts -Force | Out-Null
if (-not (Test-Path -LiteralPath $taskGodot)) { throw 'Portable Godot is missing from tools/godot.' }
# Builds share the Godot import cache, test saves and output folders, so only
# one may run at a time. The lock is released when this process exits.
try {
    $taskLock = [IO.File]::Open((Join-Path $taskArtifacts 'build.lock'), 'OpenOrCreate', 'ReadWrite', 'None')
} catch {
    throw 'Another Last Hook build is already running. Wait for it to finish and start again.'
}
# Tests start from empty saves every time, never from a previous build's files.
$taskTestProfile = Join-Path $taskArtifacts 'build-test-profile'
if (Test-Path -LiteralPath $taskTestProfile) { Remove-Item -LiteralPath $taskTestProfile -Recurse -Force }
New-Item -ItemType Directory -Path $taskTestProfile -Force | Out-Null
$env:LASTHOOK_SAVE_DIR = $taskTestProfile.Replace('\','/')
$env:APPDATA = (Join-Path $taskArtifacts 'build-appdata').Replace('\','/')
$env:TEMP = Join-Path $taskArtifacts 'build-temp'
$env:TMP = $env:TEMP
$env:GRADLE_USER_HOME = Join-Path $taskArtifacts 'gradle-user-home'
$env:ANDROID_USER_HOME = Join-Path $taskArtifacts 'android-user-home'
New-Item -ItemType Directory -Path $env:APPDATA,$env:TEMP,$env:GRADLE_USER_HOME,$env:ANDROID_USER_HOME -Force | Out-Null

function Invoke-TaskGodot([string[]]$TaskArguments, [string]$TaskLog) {
    & $taskGodot --path $taskProject --log-file $TaskLog @TaskArguments
    if ($LASTEXITCODE -ne 0) { throw "Godot returned $LASTEXITCODE. See $TaskLog" }
    if ((Get-Content -Raw -LiteralPath $TaskLog) -match '(?m)^(SCRIPT ERROR:|ERROR:)') { throw "Godot logged an error. See $TaskLog" }
}

if (-not $SkipTests) {
Invoke-TaskGodot @('--headless','--editor','--import','--quit') (Join-Path $taskArtifacts 'build-import.log')
Invoke-TaskGodot @('--headless','--script','res://tests/test_rules.gd') (Join-Path $taskArtifacts 'build-rules.log')
Invoke-TaskGodot @('--headless','--script','res://tests/test_progression.gd') (Join-Path $taskArtifacts 'build-progression.log')
Invoke-TaskGodot @('--headless','--script','res://tests/test_economy.gd') (Join-Path $taskArtifacts 'build-economy.log')
Invoke-TaskGodot @('--headless','--script','res://tests/test_integration.gd') (Join-Path $taskArtifacts 'build-integration.log')
Invoke-TaskGodot @('--headless','--script','res://tests/test_hook.gd') (Join-Path $taskArtifacts 'build-hook.log')
Invoke-TaskGodot @('--headless','--script','res://tests/test_controls.gd') (Join-Path $taskArtifacts 'build-controls.log')
Invoke-TaskGodot @('--headless','--script','res://tests/test_generation.gd') (Join-Path $taskArtifacts 'build-generation.log')
Invoke-TaskGodot @('--headless','--script','res://tests/test_routes.gd') (Join-Path $taskArtifacts 'build-routes.log')
Invoke-TaskGodot @('--headless','--script','res://tests/test_levels.gd') (Join-Path $taskArtifacts 'build-levels.log')
Invoke-TaskGodot @('--headless','--script','res://tests/test_grip_types.gd') (Join-Path $taskArtifacts 'build-grip-types.log')
Invoke-TaskGodot @('--headless','--script','res://tests/test_terrain.gd') (Join-Path $taskArtifacts 'build-terrain.log')
Invoke-TaskGodot @('--headless','--script','res://tests/test_visuals.gd') (Join-Path $taskArtifacts 'build-visuals.log')
Invoke-TaskGodot @('--headless','--script','res://tests/test_gameplay_foundation.gd') (Join-Path $taskArtifacts 'build-foundation.log')
Invoke-TaskGodot @('--headless','--script','res://tests/test_responsive.gd') (Join-Path $taskArtifacts 'build-responsive.log')
Invoke-TaskGodot @('--headless','--script','res://tests/test_menus.gd') (Join-Path $taskArtifacts 'build-menus.log')
Invoke-TaskGodot @('--headless','--script','res://tests/test_ads.gd') (Join-Path $taskArtifacts 'build-ads.log')
Invoke-TaskGodot @('--headless','--script','res://tests/test_character_editing.gd') (Join-Path $taskArtifacts 'build-character-editing.log')
Invoke-TaskGodot @('--headless','--script','res://tests/test_sprite_animation.gd') (Join-Path $taskArtifacts 'build-sprite-animation.log')
Invoke-TaskGodot @('--headless','--script','res://tests/test_polish.gd') (Join-Path $taskArtifacts 'build-polish.log')
}

if ($Target -in @('All','Windows')) {
    $taskWindows = Join-Path $taskRoot $(if ($Release) { 'Builds\Windows-Release' } else { 'Builds\Windows' })
    New-Item -ItemType Directory -Path $taskWindows -Force | Out-Null
    Invoke-TaskGodot @('--headless',$taskExport,'Windows Desktop',(Join-Path $taskWindows 'LastHook.exe')) (Join-Path $taskArtifacts 'export-windows.log')
}

if ($Target -in @('All','Android')) {
    if (-not (Test-Path -LiteralPath (Join-Path $AndroidSdkPath 'platform-tools\adb.exe'))) { throw 'Android SDK path is invalid.' }
    if (-not (Test-Path -LiteralPath (Join-Path $JavaSdkPath 'bin\java.exe'))) { throw 'Java SDK path is invalid.' }
    & (Join-Path $PSScriptRoot 'prepare_android_ads.ps1') -AndroidSdkPath $AndroidSdkPath -JavaSdkPath $JavaSdkPath
    $taskSettings = Join-Path $PSScriptRoot 'godot\editor_data\editor_settings-4.7.tres'
    $taskSettingsText = Get-Content -Raw -LiteralPath $taskSettings
    $taskSettingValues = @{
        'export/android/android_sdk_path' = $AndroidSdkPath.Replace('\','/')
        'export/android/java_sdk_path' = $JavaSdkPath.Replace('\','/')
    }
    foreach ($taskSettingName in $taskSettingValues.Keys) {
        $taskReplacement = $taskSettingName + ' = "' + $taskSettingValues[$taskSettingName] + '"'
        $taskSettingMatch = '(?m)^' + [regex]::Escape($taskSettingName) + ' = .*\r?$'
        if ([regex]::IsMatch($taskSettingsText, $taskSettingMatch)) {
            $taskSettingsText = [regex]::Replace($taskSettingsText, $taskSettingMatch, $taskReplacement.Replace('$', '$$'))
        } else {
            $taskSettingsText += "`n" + $taskReplacement + "`n"
        }
    }
    [IO.File]::WriteAllText($taskSettings, $taskSettingsText, [Text.UTF8Encoding]::new($false))
    $taskAndroid = Join-Path $taskRoot 'Builds\Android'
    New-Item -ItemType Directory -Path $taskAndroid -Force | Out-Null
    $taskApk = Join-Path $taskAndroid $(if ($Release) { 'LastHook-release.apk' } else { 'LastHook-debug.apk' })
    if ($Release) {
        # Godot reads the release key from the environment, so the password
        # never lands in editor settings or the export preset.
        $env:GODOT_ANDROID_KEYSTORE_RELEASE_PATH = $ReleaseKeystorePath
        $env:GODOT_ANDROID_KEYSTORE_RELEASE_USER = $ReleaseKeyAlias
        $env:GODOT_ANDROID_KEYSTORE_RELEASE_PASSWORD = (Get-Content -Raw -LiteralPath $ReleaseKeystorePasswordFile).Trim()
    }
    $taskAndroidLog = Join-Path $taskArtifacts 'export-android.log'
    try {
        try {
            Invoke-TaskGodot @('--headless',$taskExport,'Android',$taskApk) $taskAndroidLog
        } catch {
            # Gradle can leave a stale daemon registry after an interrupted
            # export. Remove only this build's private daemon state and retry
            # the same export once; no version changes or manual cleanup are
            # required from Release.cmd.
            $taskDaemonHome = Join-Path $taskArtifacts 'gradle-user-home\daemon'
            if (Test-Path -LiteralPath $taskDaemonHome) {
                Remove-Item -LiteralPath $taskDaemonHome -Recurse -Force -ErrorAction SilentlyContinue
            }
            Write-Output 'Android export retry after cleaning the Gradle daemon state...'
            Invoke-TaskGodot @('--headless',$taskExport,'Android',$taskApk) $taskAndroidLog
        }
    } finally {
        Remove-Item Env:GODOT_ANDROID_KEYSTORE_RELEASE_PASSWORD -ErrorAction SilentlyContinue
    }
    $taskBuildTools = Get-ChildItem -LiteralPath (Join-Path $AndroidSdkPath 'build-tools') -Directory |
        Where-Object { Test-Path -LiteralPath (Join-Path $_.FullName 'apksigner.bat') } |
        Sort-Object { [version]($_.Name -replace '-.*$','') } -Descending | Select-Object -First 1
    if (-not $taskBuildTools) { throw 'Android build tools are missing.' }
    if ($Release) {
        & (Join-Path $PSScriptRoot 'fix_android_icon.ps1') -ApkPath $taskApk -BuildToolsPath $taskBuildTools.FullName -DebugKeystorePath $ReleaseKeystorePath -KeyAlias $ReleaseKeyAlias -KeystorePasswordFile $ReleaseKeystorePasswordFile
    } else {
        & (Join-Path $PSScriptRoot 'fix_android_icon.ps1') -ApkPath $taskApk -BuildToolsPath $taskBuildTools.FullName -DebugKeystorePath (Join-Path $PSScriptRoot 'godot\editor_data\keystores\debug.keystore')
    }
}
Write-Output 'Last Hook build finished.'
