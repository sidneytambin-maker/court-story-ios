$ErrorActionPreference = "Stop"

$projectRoot = Resolve-Path (Join-Path $PSScriptRoot "..")
$buildsRoot = Join-Path $projectRoot "builds"

$ipa = Get-ChildItem -Path $buildsRoot -Filter "TennisTracker-development-unsigned-*.ipa" |
    Sort-Object LastWriteTime -Descending |
    Select-Object -First 1

if (-not $ipa) {
    throw "No Tennis Tracker IPA was found in $buildsRoot. Run Scripts\download_latest_github_artifact.ps1 first."
}

$contents = tar -tf $ipa.FullName
$watchPath = "Payload/TennisTracker.app/Watch/TennisTrackerWatchApp.app/"
$pluginWatchPath = "Payload/TennisTracker.app/PlugIns/TennisTrackerWatchApp.app/"

if ($contents -contains $pluginWatchPath) {
    throw "The Watch app is embedded in PlugIns, which physical testing shows makes it disappear from the iPhone Watch app and Apple Watch."
}

if (-not ($contents -contains $watchPath)) {
    throw "The IPA does not contain $watchPath"
}

Write-Host "Verified embedded Watch app:"
Write-Host $watchPath
Write-Host "IPA:"
Write-Host $ipa.FullName
