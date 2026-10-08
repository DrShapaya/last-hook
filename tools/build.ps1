param(
    [ValidateSet('All','Windows','Android')][string]$Target = 'All',
    [string]$AndroidSdkPath = 'C:\Users\isaev\AppData\Local\Android\Sdk',
    [string]$JavaSdkPath = 'C:\Program Files\Eclipse Adoptium\jdk-21.0.10.7-hotspot'
)
$ErrorActionPreference = 'Stop'
$taskRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$taskGodot = Join-Path $PSScriptRoot 'godot\Godot_v4.7.2-stable_win64_console.exe'
$taskProject = Join-Path $taskRoot 'game'
$taskArtifacts = Join-Path $taskRoot 'artifacts'
New-Item -ItemType Directory -Path $taskArtifacts -Force | Out-Null
if (-not (Test-Path -LiteralPath $taskGodot)) { throw 'Portable Godot is missing from tools/godot.' }
$env:LASTHOOK_SAVE_DIR = Join-Path $taskArtifacts 'build-test-profile'
$env:APPDATA = Join-Path $taskArtifacts 'build-appdata'
New-Item -ItemType Directory -Path $env:APPDATA -Force | Out-Null

function Invoke-TaskGodot([string[]]$TaskArguments, [string]$TaskLog) {
    & $taskGodot --path $taskProject --log-file $TaskLog @TaskArguments
    if ($LASTEXITCODE -ne 0) { throw "Godot returned $LASTEXITCODE. See $TaskLog" }
    if ((Get-Content -Raw -LiteralPath $TaskLog) -match '(?m)^(SCRIPT ERROR:|ERROR:)') { throw "Godot logged an error. See $TaskLog" }
}

Invoke-TaskGodot @('--headless','--editor','--import','--quit') (Join-Path $taskArtifacts 'build-import.log')
Invoke-TaskGodot @('--headless','--script','res://tests/test_rules.gd') (Join-Path $taskArtifacts 'build-rules.log')
Invoke-TaskGodot @('--headless','--script','res://tests/test_integration.gd') (Join-Path $taskArtifacts 'build-integration.log')
Invoke-TaskGodot @('--headless','--script','res://tests/test_generation.gd') (Join-Path $taskArtifacts 'build-generation.log')
Invoke-TaskGodot @('--headless','--script','res://tests/test_responsive.gd') (Join-Path $taskArtifacts 'build-responsive.log')

if ($Target -in @('All','Windows')) {
    $taskWindows = Join-Path $taskRoot 'Builds\Windows'
    New-Item -ItemType Directory -Path $taskWindows -Force | Out-Null
    Invoke-TaskGodot @('--headless','--export-debug','Windows Desktop',(Join-Path $taskWindows 'LastHook.exe')) (Join-Path $taskArtifacts 'export-windows.log')
}

if ($Target -in @('All','Android')) {
    if (-not (Test-Path -LiteralPath (Join-Path $AndroidSdkPath 'platform-tools\adb.exe'))) { throw 'Android SDK path is invalid.' }
    if (-not (Test-Path -LiteralPath (Join-Path $JavaSdkPath 'bin\java.exe'))) { throw 'Java SDK path is invalid.' }
    $taskSettings = Join-Path $PSScriptRoot 'godot\editor_data\editor_settings-4.7.tres'
    $taskSettingsText = Get-Content -Raw -LiteralPath $taskSettings
    $taskSettingValues = @{
        'export/android/android_sdk_path' = $AndroidSdkPath.Replace('\','/')
        'export/android/java_sdk_path' = $JavaSdkPath.Replace('\','/')
    }
    foreach ($taskSettingName in $taskSettingValues.Keys) {
        $taskReplacement = $taskSettingName + ' = "' + $taskSettingValues[$taskSettingName] + '"'
        $taskSettingsText = [regex]::Replace($taskSettingsText, '(?m)^' + [regex]::Escape($taskSettingName) + ' = .*$', [System.Text.RegularExpressions.MatchEvaluator]{ param($taskMatch) $taskReplacement })
    }
    [IO.File]::WriteAllText($taskSettings, $taskSettingsText, [Text.UTF8Encoding]::new($false))
    $taskAndroid = Join-Path $taskRoot 'Builds\Android'
    New-Item -ItemType Directory -Path $taskAndroid -Force | Out-Null
    Invoke-TaskGodot @('--headless','--export-debug','Android',(Join-Path $taskAndroid 'LastHook-debug.apk')) (Join-Path $taskArtifacts 'export-android.log')
    $taskBuildTools = Get-ChildItem -LiteralPath (Join-Path $AndroidSdkPath 'build-tools') -Directory |
        Where-Object { Test-Path -LiteralPath (Join-Path $_.FullName 'apksigner.bat') } |
        Sort-Object { [version]($_.Name -replace '-.*$','') } -Descending | Select-Object -First 1
    if (-not $taskBuildTools) { throw 'Android build tools are missing.' }
    & (Join-Path $PSScriptRoot 'fix_android_icon.ps1') -ApkPath (Join-Path $taskAndroid 'LastHook-debug.apk') -BuildToolsPath $taskBuildTools.FullName -DebugKeystorePath (Join-Path $PSScriptRoot 'godot\editor_data\keystores\debug.keystore')
}
Write-Output 'Last Hook build finished.'
