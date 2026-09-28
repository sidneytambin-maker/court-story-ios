param(
    [string]$TeamIdentifier = "HT5X86Q4DD",
    [string]$OutputDirectory = ""
)

$ErrorActionPreference = "Stop"

$repoRoot = Resolve-Path (Join-Path $PSScriptRoot "..")
$buildsRoot = Join-Path $repoRoot "builds"

if (-not $OutputDirectory) {
    $OutputDirectory = Join-Path $repoRoot "work\sideloadly"
}

$ipa = Get-ChildItem -Path $buildsRoot -Filter "TennisTracker-development-unsigned-*.ipa" |
    Sort-Object LastWriteTime -Descending |
    Select-Object -First 1

if (-not $ipa) {
    throw "No downloaded TennisTracker development IPA was found in $buildsRoot."
}

New-Item -ItemType Directory -Force -Path $OutputDirectory | Out-Null

$stagedIpa = Join-Path $OutputDirectory "TennisTracker-latest.ipa"
$patchedIpa = Join-Path $OutputDirectory "TennisTracker-latest-sideloadly-watch.ipa"
$tempRoot = Join-Path $OutputDirectory ("ipa-expand-" + (Get-Date -Format "yyyyMMdd-HHmmss-ffff"))

Copy-Item -LiteralPath $ipa.FullName -Destination $stagedIpa -Force
New-Item -ItemType Directory -Force -Path $tempRoot | Out-Null
$zipCopy = Join-Path $OutputDirectory "TennisTracker-latest.zip"
Copy-Item -LiteralPath $stagedIpa -Destination $zipCopy -Force
Expand-Archive -LiteralPath $zipCopy -DestinationPath $tempRoot -Force

$iphoneApp = Join-Path $tempRoot "Payload\TennisTracker.app"
$iphoneInfo = Join-Path $iphoneApp "Info.plist"
$watchAppName = "TennisTrackerWatchApp.app"
$pluginsWatchApp = Join-Path $iphoneApp "PlugIns\$watchAppName"
$legacyWatchApp = Join-Path $iphoneApp "Watch\$watchAppName"

$watchApp = if (Test-Path -LiteralPath $pluginsWatchApp) { $pluginsWatchApp } else { $legacyWatchApp }
$watchInfo = Join-Path $watchApp "Info.plist"

if (-not (Test-Path -LiteralPath $iphoneInfo)) {
    throw "The iPhone Info.plist was not found in the IPA."
}

if (-not (Test-Path -LiteralPath $watchInfo)) {
    throw "The embedded Watch app was not found at Payload/TennisTracker.app/PlugIns/TennisTrackerWatchApp.app or Payload/TennisTracker.app/Watch/TennisTrackerWatchApp.app."
}

$pythonCandidates = @()
if ($env:LOCALAPPDATA) {
    $pythonCandidates += @(
        (Join-Path $env:LOCALAPPDATA "Programs\Python\Python312\python.exe"),
        (Join-Path $env:LOCALAPPDATA "Programs\Python\Python311\python.exe")
    )
}
$pythonCandidates += @("python3", "python", "py")

$python = $null
foreach ($candidate in $pythonCandidates) {
    if (Test-Path -LiteralPath $candidate) {
        $python = [pscustomobject]@{ Source = $candidate }
        break
    }

    $command = Get-Command $candidate -ErrorAction SilentlyContinue
    if ($command -and $command.Source -notmatch "WindowsApps\\python(?:3)?\.exe$") {
        $python = $command
        break
    }
}

if (-not $python) {
    throw "Python is required to patch the IPA plist files. Install Python 3 and run this script again."
}

$readBundleScript = @"
import plistlib
from pathlib import Path

iphone_info = Path(r"$iphoneInfo")
with iphone_info.open("rb") as f:
    print(plistlib.load(f).get("CFBundleIdentifier", ""))
"@

$readBundleFile = Join-Path $OutputDirectory "read-iphone-bundle.py"
Set-Content -LiteralPath $readBundleFile -Value $readBundleScript -Encoding UTF8
$iphoneBundleId = (& $python.Source $readBundleFile).Trim()

if (-not $iphoneBundleId) {
    throw "Could not read the iPhone bundle identifier from the IPA."
}

$sideloadlyFinalIphoneBundleId = "$iphoneBundleId.$TeamIdentifier"
$sideloadlyFinalWatchBundleId = "$sideloadlyFinalIphoneBundleId.watchkitapp"

$patchScript = @"
import plistlib
from pathlib import Path

watch_info = Path(r"$watchInfo")
with watch_info.open("rb") as f:
    plist = plistlib.load(f)
plist["CFBundleIdentifier"] = "$sideloadlyFinalWatchBundleId"
plist["WKCompanionAppBundleIdentifier"] = "$sideloadlyFinalIphoneBundleId"
with watch_info.open("wb") as f:
    plistlib.dump(plist, f, sort_keys=False)
"@

$patchFile = Join-Path $OutputDirectory "patch-watch-plist.py"
Set-Content -LiteralPath $patchFile -Value $patchScript -Encoding UTF8
& $python.Source $patchFile

if (Test-Path -LiteralPath $patchedIpa) {
    Remove-Item -LiteralPath $patchedIpa -Force
}

Compress-Archive -Path (Join-Path $tempRoot "Payload") -DestinationPath $patchedIpa -Force

Write-Host "Source IPA:"
Write-Host $ipa.FullName
Write-Host "Staged no-spaces IPA:"
Write-Host $stagedIpa
Write-Host "Sideloadly-compatible Watch IPA:"
Write-Host $patchedIpa
Write-Host "Expected Sideloadly iPhone bundle:"
Write-Host $sideloadlyFinalIphoneBundleId
Write-Host "Patched Watch bundle:"
Write-Host $sideloadlyFinalWatchBundleId
Write-Host ""
Write-Host "Signing inspection:"
try {
    & (Join-Path $PSScriptRoot "inspect_ipa_signing.ps1") `
        -IpaPath $patchedIpa `
        -ExpectedIphoneBundleId $iphoneBundleId `
        -ExpectedWatchBundleId $sideloadlyFinalWatchBundleId `
        -ExpectedWatchCompanionBundleId $sideloadlyFinalIphoneBundleId
    if ($LASTEXITCODE -ne 0) {
        throw "Signing inspection reported an unsigned or incomplete Watch bundle."
    }
} catch {
    Write-Warning "The staged IPA is intentionally unsigned before Sideloadly runs. The Watch bundle must be rechecked after signing/install preparation."
}
