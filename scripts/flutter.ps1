param(
    [ValidateSet('run', 'apk', 'analyze', 'test', 'doctor', 'devices', 'pub')]
    [string]$Action = 'run',
    [string]$Device = '',
    [string]$Config = '',
    [switch]$Release
)

$ErrorActionPreference = 'Stop'
$taskProjectRoot = Split-Path -Parent $PSScriptRoot
Set-Location -LiteralPath $taskProjectRoot

# Process-local fixes only: do not change the user's global environment.
if ($env:PUB_CACHE) {
    $taskCacheDrive = [System.IO.Path]::GetPathRoot($env:PUB_CACHE)
    if (-not (Test-Path -LiteralPath $taskCacheDrive)) {
        $env:PUB_CACHE = Join-Path $env:LOCALAPPDATA 'Pub\Cache'
    }
}

$taskSdkCandidates = @(
    $env:ANDROID_HOME,
    $env:ANDROID_SDK_ROOT,
    (Join-Path $env:LOCALAPPDATA 'Android\Sdk')
)
$taskSdk = $taskSdkCandidates | Where-Object { $_ -and (Test-Path -LiteralPath (Join-Path $_ 'platform-tools')) } | Select-Object -First 1
if ($taskSdk) {
    $taskSdk = (Resolve-Path -LiteralPath $taskSdk).Path.TrimEnd('\')
    if ($taskSdk.Contains(' ')) {
        # A junction avoids moving the installed SDK or changing Android Studio settings.
        $taskSdkLink = Join-Path ([System.IO.Path]::GetPathRoot($taskProjectRoot)) 'RigMarketAndroidSdk'
        if (-not (Test-Path -LiteralPath $taskSdkLink)) {
            New-Item -ItemType Junction -Path $taskSdkLink -Target $taskSdk | Out-Null
        }
        $taskLinkInfo = Get-Item -LiteralPath $taskSdkLink
        if ($taskLinkInfo.LinkType -ne 'Junction' -or [string]$taskLinkInfo.Target -ne $taskSdk) {
            throw "SDK alias $taskSdkLink already exists and does not point to the expected SDK. Set ANDROID_HOME to a valid path without spaces."
        }
        $taskSdk = $taskSdkLink
    }
    $env:ANDROID_HOME = $taskSdk
    $env:ANDROID_SDK_ROOT = $taskSdk
}

$taskBundledJava = 'C:\Program Files\Android\Android Studio\jbr'
if (-not $env:JAVA_HOME -and (Test-Path -LiteralPath $taskBundledJava)) { $env:JAVA_HOME = $taskBundledJava }

if (-not (Get-Command flutter -ErrorAction SilentlyContinue)) {
    if (Test-Path -LiteralPath 'C:\flutter\bin\flutter.bat') { $env:PATH = 'C:\flutter\bin;' + $env:PATH }
    else { throw 'Flutter is not installed or not on PATH. Install the stable Flutter SDK first.' }
}

$taskFlutterArgs = @()
switch ($Action) {
    'run' { $taskFlutterArgs = @('run'); if ($Device) { $taskFlutterArgs += @('-d', $Device) } }
    'apk' { $taskFlutterArgs = @('build', 'apk'); if ($Release) { $taskFlutterArgs += '--release' } else { $taskFlutterArgs += '--debug' } }
    'analyze' { $taskFlutterArgs = @('analyze') }
    'test' { $taskFlutterArgs = @('test') }
    'doctor' { $taskFlutterArgs = @('doctor', '-v') }
    'devices' { $taskFlutterArgs = @('devices') }
    'pub' { $taskFlutterArgs = @('pub', 'get') }
}
if ($Config) {
    if ($Action -notin @('run', 'apk')) { throw '-Config is only supported with run or apk.' }
    if (-not (Test-Path -LiteralPath $Config)) { throw "Configuration file not found: $Config" }
    $taskFlutterArgs += "--dart-define-from-file=$Config"
}
& flutter @taskFlutterArgs
if ($LASTEXITCODE -ne 0) { throw "Flutter $Action failed (exit code $LASTEXITCODE)." }
