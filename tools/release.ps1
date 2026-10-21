param(
    # Version to release, for example 0.14.0. Empty keeps the current one.
    [string]$Version = '',
    [ValidateSet('All','Windows','Android')][string]$Target = 'All',
    # Replace an existing Builds\Versions\v<version> folder.
    [switch]$Force
)
$ErrorActionPreference = 'Stop'
$taskRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$taskModel = Join-Path $taskRoot 'game\scripts\game_model.gd'
$taskPresets = Join-Path $taskRoot 'game\export_presets.cfg'
$taskUtf8 = [Text.UTF8Encoding]::new($false)

$taskModelText = [IO.File]::ReadAllText($taskModel)
$taskCurrent = [regex]::Match($taskModelText, 'const BUILD_VERSION := "([^"]+)"').Groups[1].Value
if (-not $taskCurrent) { throw 'BUILD_VERSION is missing from game_model.gd.' }
$taskVersions = Join-Path $taskRoot 'Builds\Versions'
if (-not $Version) {
    # Every run without a version is a new release: the current version if it
    # has not been built yet, otherwise the next free patch number.
    if ($taskCurrent -notmatch '^(\d+)\.(\d+)\.(\d+)$') { throw "BUILD_VERSION '$taskCurrent' must look like 0.14.0." }
    $taskPatch = [int]$Matches[3]
    $Version = $taskCurrent
    while (Test-Path -LiteralPath (Join-Path $taskVersions "v$Version")) {
        $taskPatch += 1
        $Version = '{0}.{1}.{2}' -f $Matches[1],$Matches[2],$taskPatch
    }
}
$Version = $Version.Trim().TrimStart('v')
if ($Version -notmatch '^\d+\.\d+\.\d+$') { throw "Version must look like 0.14.0, got '$Version'." }

$taskOutput = Join-Path $taskVersions "v$Version"
if ((Test-Path -LiteralPath $taskOutput) -and -not $Force) {
    throw "Folder $taskOutput already exists. Pick a new version or run with -Force."
}

# One version everywhere: the in-game label, Windows file metadata and the
# Android version name. A new version also raises the Android version code,
# which stores require to grow with every update.
function Set-TaskValue([string]$Text, [string]$Key, [string]$Value) {
    $pattern = '(?m)^' + [regex]::Escape($Key) + '=.*?(\r?)$'
    if (-not [regex]::IsMatch($Text, $pattern)) { throw "export_presets.cfg has no $Key." }
    return [regex]::Replace($Text, $pattern, { param($m) $Key + '=' + $Value + $m.Groups[1].Value })
}
$taskPresetText = [IO.File]::ReadAllText($taskPresets)
$taskCode = [int][regex]::Match($taskPresetText, '(?m)^version/code=(\d+)').Groups[1].Value
if ($Version -ne $taskCurrent) {
    $taskModelText = $taskModelText.Replace("const BUILD_VERSION := `"$taskCurrent`"", "const BUILD_VERSION := `"$Version`"")
    [IO.File]::WriteAllText($taskModel, $taskModelText, $taskUtf8)
    $taskCode += 1
    $taskPresetText = Set-TaskValue $taskPresetText 'version/code' $taskCode
}
$taskPresetText = Set-TaskValue $taskPresetText 'application/product_name' '"Last Hook"'
$taskPresetText = Set-TaskValue $taskPresetText 'application/file_description' "`"Last Hook $Version`""
$taskPresetText = Set-TaskValue $taskPresetText 'application/product_version' "`"$Version`""
$taskPresetText = Set-TaskValue $taskPresetText 'application/file_version' "`"$Version`""
$taskPresetText = Set-TaskValue $taskPresetText 'version/name' "`"$Version`""
[IO.File]::WriteAllText($taskPresets, $taskPresetText, $taskUtf8)
Write-Output "Last Hook $Version (Android code $taskCode): tests and release export..."

& (Join-Path $PSScriptRoot 'build.ps1') -Target $Target -Release

if (Test-Path -LiteralPath $taskOutput) { Remove-Item -LiteralPath $taskOutput -Recurse -Force }
New-Item -ItemType Directory -Path $taskOutput -Force | Out-Null
$taskFiles = @()
if ($Target -in @('All','Windows')) {
    $taskExe = Join-Path $taskRoot 'Builds\Windows-Release\LastHook.exe'
    $taskZip = Join-Path $taskOutput "LastHook-v$Version-Windows-x64.zip"
    Compress-Archive -LiteralPath $taskExe -DestinationPath $taskZip -CompressionLevel Optimal
    $taskFiles += $taskZip
}
if ($Target -in @('All','Android')) {
    $taskApk = Join-Path $taskOutput "LastHook-v$Version-Android-arm64.apk"
    Copy-Item -LiteralPath (Join-Path $taskRoot 'Builds\Android\LastHook-release.apk') -Destination $taskApk
    $taskFiles += $taskApk
}
$taskSums = foreach ($taskFile in $taskFiles) {
    (Get-FileHash -Algorithm SHA256 -LiteralPath $taskFile).Hash.ToLower() + '  ' + (Split-Path -Leaf $taskFile)
}
[IO.File]::WriteAllLines((Join-Path $taskOutput 'SHA256SUMS.txt'), [string[]]$taskSums, $taskUtf8)
Write-Output "Release Last Hook $Version is ready: $taskOutput"
