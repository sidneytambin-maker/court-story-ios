$ErrorActionPreference = "Stop"

$projectRoot = Resolve-Path (Join-Path $PSScriptRoot "..")
$sideloadly = Join-Path $env:LOCALAPPDATA "Sideloadly\sideloadly.exe"

if (-not (Test-Path -LiteralPath $sideloadly)) {
    throw "Sideloadly was not found at $sideloadly"
}

$preparedOutput = & (Join-Path $PSScriptRoot "prepare_sideloadly_watch_ipa.ps1") 2>&1
$preparedOutput | Write-Host

$ipaPath = Join-Path $projectRoot "work\sideloadly\TennisTracker-latest-sideloadly-watch.ipa"
if (-not (Test-Path -LiteralPath $ipaPath)) {
    throw "Prepared Sideloadly IPA was not found: $ipaPath"
}

Start-Process -FilePath $sideloadly -ArgumentList ('"' + $ipaPath + '"')
Write-Host "Opened Sideloadly with:"
Write-Host $ipaPath
Write-Host ""
Write-Host "Important: after Sideloadly signs the package, the embedded Watch app must have its own valid signature and provisioning profile. If Sideloadly signs only the iPhone app, the Watch will show an integrity verification error."
