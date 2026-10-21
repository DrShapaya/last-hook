param(
    [Parameter(Mandatory)][string]$ApkPath,
    [Parameter(Mandatory)][string]$BuildToolsPath,
    [Parameter(Mandatory)][string]$DebugKeystorePath,
    # Defaults sign with the debug key; a release build passes its own alias
    # and a file holding the keystore password.
    [string]$KeyAlias = 'androiddebugkey',
    [string]$KeystorePasswordFile = ''
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
    # A release build shortens resource paths (res/-8.xml ...), so the stale
    # path does not exist there and nothing needs repairing.
    $taskObfuscated = -not ($taskArchive.Entries | Where-Object { $_.FullName -like 'res/mipmap-*' })
    if (-not $taskObfuscated -and -not $taskArchive.GetEntry('res/mipmap-anydpi-v26/themed_icon.xml')) {
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
        $taskPass = if ($KeystorePasswordFile) { 'file:' + [IO.Path]::GetFullPath($KeystorePasswordFile) } else { 'pass:android' }
        & (Join-Path $BuildToolsPath 'apksigner.bat') sign --ks $DebugKeystorePath --ks-pass $taskPass --ks-key-alias $KeyAlias $taskApk
        if ($LASTEXITCODE -ne 0) { throw 'APK signing failed.' }
        Write-Output 'Adaptive icon resource repaired; APK aligned and signed again.'
    }
    & (Join-Path $BuildToolsPath 'apksigner.bat') verify $taskApk
    if ($LASTEXITCODE -ne 0) { throw 'APK signature verification failed.' }
} finally { Remove-Item -LiteralPath $taskPacked -Force }
