param(
    [Parameter(Mandatory)][string]$ApkPath,
    [Parameter(Mandatory)][string]$BuildToolsPath,
    [Parameter(Mandatory)][string]$DebugKeystorePath
)
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.IO.Compression.FileSystem
$taskApk = [IO.Path]::GetFullPath($ApkPath)
$taskPacked = $taskApk + '.icon-fix.zip'
Copy-Item -LiteralPath $taskApk -Destination $taskPacked -Force
$taskArchive = [IO.Compression.ZipFile]::Open($taskPacked, [IO.Compression.ZipArchiveMode]::Update)
$taskChanged = $false
try {
    # Godot 4.7.2's APK resource table still references this path after renaming
    # its adaptive icon to icon.xml. Keep both paths so the table is valid.
    if (-not $taskArchive.GetEntry('res/mipmap-anydpi-v26/themed_icon.xml')) {
        $taskIcon = $taskArchive.GetEntry('res/mipmap-anydpi-v26/icon.xml')
        if (-not $taskIcon) { throw 'The exported APK has no adaptive icon.' }
        $taskInput = $taskIcon.Open()
        $taskBytes = [IO.MemoryStream]::new()
        try { $taskInput.CopyTo($taskBytes) } finally { $taskInput.Dispose() }
        $taskDuplicate = $taskArchive.CreateEntry('res/mipmap-anydpi-v26/themed_icon.xml')
        $taskOutput = $taskDuplicate.Open()
        try { $taskBytes.Position = 0; $taskBytes.CopyTo($taskOutput) }
        finally { $taskOutput.Dispose(); $taskBytes.Dispose() }
        $taskChanged = $true
        foreach ($taskEntry in @($taskArchive.Entries | Where-Object { $_.FullName -match '^META-INF/.*\.(SF|RSA|DSA|EC|MF)$' })) {
            $taskEntry.Delete()
        }
    }
} finally { $taskArchive.Dispose() }
try {
    if ($taskChanged) {
        & (Join-Path $BuildToolsPath 'zipalign.exe') -f -P 16 4 $taskPacked $taskApk
        if ($LASTEXITCODE -ne 0) { throw 'APK alignment failed.' }
        & (Join-Path $BuildToolsPath 'apksigner.bat') sign --ks $DebugKeystorePath --ks-pass pass:android --ks-key-alias androiddebugkey $taskApk
        if ($LASTEXITCODE -ne 0) { throw 'APK debug signing failed.' }
        Write-Output 'Adaptive icon resource repaired; APK aligned and signed again.'
    }
    & (Join-Path $BuildToolsPath 'apksigner.bat') verify $taskApk
    if ($LASTEXITCODE -ne 0) { throw 'APK signature verification failed.' }
} finally { Remove-Item -LiteralPath $taskPacked -Force }
