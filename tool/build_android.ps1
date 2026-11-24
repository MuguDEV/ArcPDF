# Build ArcPDF APKs.
# Usage: tool/build_android.ps1 <debug|preview|preview-compressed|full> [extra flutter args]
#   debug              arm64-v8a debug APK
#   preview            arm64-v8a release APK, split per ABI, obfuscated
#   preview-compressed preview with ARCPDF_COMPRESS_NATIVE_LIBS=true
#   full               all ABIs, release flags as preview
# flutter pub get runs only when pubspec.yaml or pubspec.lock changed since the
# last successful resolution (hash stored in .arc-build). flutter clean is never run.
param(
    [Parameter(Mandatory = $true, Position = 0)]
    [ValidateSet('debug', 'preview', 'preview-compressed', 'full')]
    [string]$Mode,
    [Parameter(ValueFromRemainingArguments = $true)]
    [string[]]$ExtraArgs = @()
)

$ErrorActionPreference = 'Stop'
$RepoRoot = Split-Path -Parent $PSScriptRoot
Set-Location $RepoRoot

$StateDir = Join-Path $RepoRoot '.arc-build'
$HashFile = Join-Path $StateDir 'pubspec.hash'
New-Item -ItemType Directory -Force -Path $StateDir | Out-Null

function Get-FileHashOrMissing([string]$Path) {
    if (Test-Path $Path) { return (Get-FileHash -Algorithm SHA256 $Path).Hash.ToLowerInvariant() }
    return 'missing'
}

function Invoke-Flutter {
    & flutter @args
    if ($LASTEXITCODE -ne 0) { throw "flutter $($args -join ' ') failed with exit code $LASTEXITCODE" }
}

$Want = "$(Get-FileHashOrMissing 'pubspec.yaml') $(Get-FileHashOrMissing 'pubspec.lock') "
$Have = ''
if (Test-Path $HashFile) { $Have = [System.IO.File]::ReadAllText($HashFile) }

if (($Want -ne $Have) -or -not (Test-Path (Join-Path '.dart_tool' 'package_config.json'))) {
    Write-Host 'pubspec changed or not resolved: running flutter pub get'
    Invoke-Flutter pub get
    [System.IO.File]::WriteAllText($HashFile, $Want)
}

$ReleaseFlags = @('--release', '--target-platform', 'android-arm64', '--split-per-abi',
    '--obfuscate', '--split-debug-info=build/symbols/preview')

# Restore environment variables after the build so the caller's shell is not polluted.
$SavedAbis = $env:ARCPDF_ABIS
$SavedCompress = $env:ARCPDF_COMPRESS_NATIVE_LIBS
try {
    switch ($Mode) {
        'debug' {
            $env:ARCPDF_ABIS = 'arm64-v8a'
            Invoke-Flutter build apk --debug --target-platform android-arm64 --no-pub @ExtraArgs
        }
        'preview' {
            $env:ARCPDF_ABIS = 'arm64-v8a'
            Invoke-Flutter build apk @ReleaseFlags --no-pub @ExtraArgs
        }
        'preview-compressed' {
            $env:ARCPDF_ABIS = 'arm64-v8a'
            $env:ARCPDF_COMPRESS_NATIVE_LIBS = 'true'
            Invoke-Flutter build apk @ReleaseFlags --no-pub @ExtraArgs
        }
        'full' {
            if (-not $env:ARCPDF_ABIS) { $env:ARCPDF_ABIS = 'arm64-v8a,armeabi-v7a,x86_64' }
            Invoke-Flutter build apk --release --target-platform 'android-arm,android-arm64,android-x64' `
                --split-per-abi --obfuscate --split-debug-info=build/symbols/full --no-pub @ExtraArgs
        }
    }
}
finally {
    $env:ARCPDF_ABIS = $SavedAbis
    $env:ARCPDF_COMPRESS_NATIVE_LIBS = $SavedCompress
}
