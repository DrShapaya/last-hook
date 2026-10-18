param(
    [string]$AndroidSdkPath = 'C:\Users\isaev\AppData\Local\Android\Sdk',
    [string]$JavaSdkPath = 'C:\Program Files\Eclipse Adoptium\jdk-21.0.10.7-hotspot',
    [switch]$RebuildPlugin
)
$ErrorActionPreference = 'Stop'
$adsRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$adsBuild = Join-Path $adsRoot 'game\android\build'
$adsTemplates = Join-Path $PSScriptRoot 'godot\editor_data\export_templates\4.7.2.stable'
$adsSourceZip = Join-Path $adsTemplates 'android_source.zip'
$adsGodotLibrary = Join-Path $adsBuild 'libs\debug\godot-lib.template_debug.aar'

if (-not (Test-Path -LiteralPath $adsGodotLibrary)) {
    if (-not (Test-Path -LiteralPath $adsSourceZip)) {
        $adsTemplateArchive = Join-Path $PSScriptRoot 'godot\export_templates.tpz'
        if (-not (Test-Path -LiteralPath $adsTemplateArchive)) {
            throw 'Install Godot 4.7.2 Android build templates or provide tools/godot/export_templates.tpz.'
        }
        Add-Type -AssemblyName System.IO.Compression.FileSystem
        $adsArchive = [IO.Compression.ZipFile]::OpenRead($adsTemplateArchive)
        try {
            New-Item -ItemType Directory -Path $adsTemplates -Force | Out-Null
            [IO.Compression.ZipFileExtensions]::ExtractToFile($adsArchive.GetEntry('templates/android_source.zip'),$adsSourceZip,$true)
        } finally { $adsArchive.Dispose() }
    }
    New-Item -ItemType Directory -Path $adsBuild -Force | Out-Null
    Expand-Archive -LiteralPath $adsSourceZip -DestinationPath $adsBuild -Force
}
New-Item -ItemType File -Path (Join-Path $adsBuild '.gdignore') -Force | Out-Null
[IO.File]::WriteAllText((Join-Path $adsRoot 'game\android\.build_version'),'4.7.2.stable',[Text.UTF8Encoding]::new($false))
$adsGradleProperties = Join-Path $adsBuild 'gradle.properties'
$adsGradleText = Get-Content -Raw -LiteralPath $adsGradleProperties
if ($adsGradleText -notmatch '(?m)^org\.gradle\.daemon=') {
    Add-Content -LiteralPath $adsGradleProperties -Value "`norg.gradle.daemon=false"
} else {
    $adsGradleText = [regex]::Replace($adsGradleText,'(?m)^org\.gradle\.daemon=.*$','org.gradle.daemon=false')
    [IO.File]::WriteAllText($adsGradleProperties,$adsGradleText,[Text.UTF8Encoding]::new($false))
}

$adsBinary = Join-Path $adsRoot 'game\addons\last_hook_ads\bin\LastHookAds.aar'
if ($RebuildPlugin -or -not (Test-Path -LiteralPath $adsBinary)) {
    $env:JAVA_HOME = $JavaSdkPath
    $env:ANDROID_HOME = $AndroidSdkPath
    & (Join-Path $adsBuild 'gradlew.bat') --no-daemon --console=plain -p (Join-Path $PSScriptRoot 'android-ads') installPlugin
    if ($LASTEXITCODE -ne 0) { throw 'LastHookAds native module build failed.' }
}
Write-Output 'Android build template and LastHookAds module are ready.'
