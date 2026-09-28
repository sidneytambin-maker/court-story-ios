param(
    [string]$IpaPath = "",
    [string]$AppPath = "",

    [string]$ExpectedIphoneBundleId = "",
    [string]$ExpectedWatchBundleId = "",
    [string]$ExpectedWatchCompanionBundleId = "",
    [string]$ExpectedIphoneDeviceUdid = "",
    [string]$ExpectedWatchDeviceUdid = "",
    [switch]$ReportOnly
)

$ErrorActionPreference = "Stop"

if (-not $IpaPath -and -not $AppPath) {
    throw "Provide either -IpaPath or -AppPath."
}

if ($IpaPath -and $AppPath) {
    throw "Provide only one input: -IpaPath or -AppPath."
}

if ($IpaPath -and -not (Test-Path -LiteralPath $IpaPath)) {
    throw "IPA was not found: $IpaPath"
}

if ($AppPath -and -not (Test-Path -LiteralPath $AppPath)) {
    throw "App bundle was not found: $AppPath"
}

$repoRoot = Resolve-Path (Join-Path $PSScriptRoot "..")
$workRoot = Join-Path $repoRoot "work\ipa-signing-inspection"
$expandRoot = Join-Path $workRoot ("expanded-" + (Get-Date -Format "yyyyMMdd-HHmmss-ffff"))

New-Item -ItemType Directory -Force -Path $expandRoot | Out-Null

if ($IpaPath) {
    $zipCopy = Join-Path $workRoot ("input-" + (Get-Date -Format "yyyyMMdd-HHmmss-ffff") + ".zip")
    Copy-Item -LiteralPath $IpaPath -Destination $zipCopy -Force
    Expand-Archive -LiteralPath $zipCopy -DestinationPath $expandRoot -Force
    $inputDescription = $IpaPath
} else {
    $payloadRoot = Join-Path $expandRoot "Payload"
    New-Item -ItemType Directory -Force -Path $payloadRoot | Out-Null
    Copy-Item -LiteralPath $AppPath -Destination $payloadRoot -Recurse -Force
    $inputDescription = $AppPath
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
    throw "Python is required for IPA signing inspection."
}

$inspector = @'
import base64
import json
import hashlib
import plistlib
import re
import sys
from pathlib import Path

root = Path(sys.argv[1])
def arg_value(index):
    if index >= len(sys.argv):
        return ""
    value = sys.argv[index]
    return "" if value == "__EMPTY__" else value

expected_iphone = arg_value(2)
expected_watch = arg_value(3)
expected_companion = arg_value(4)
expected_iphone_device = arg_value(5)
expected_watch_device = arg_value(6)

def read_plist(path):
    if not path.exists():
        return None
    with path.open("rb") as f:
        return plistlib.load(f)

def decode_mobileprovision(path):
    if not path.exists():
        return None
    data = path.read_bytes()
    match = re.search(rb"<\?xml.*?</plist>", data, re.S)
    if not match:
        return {"present": True, "decoded": False}
    profile = plistlib.loads(match.group(0))
    devices = profile.get("ProvisionedDevices") or []
    certs = profile.get("DeveloperCertificates") or []
    entitlements = profile.get("Entitlements") or {}
    return {
        "present": True,
        "decoded": True,
        "name": profile.get("Name"),
        "uuid": profile.get("UUID"),
        "team_identifier": profile.get("TeamIdentifier"),
        "application_identifier_prefix": profile.get("ApplicationIdentifierPrefix"),
        "creation_date": str(profile.get("CreationDate")),
        "expiration_date": str(profile.get("ExpirationDate")),
        "platform": profile.get("Platform"),
        "provisioned_device_count": len(devices),
        "includes_expected_iphone_device": (not expected_iphone_device) or expected_iphone_device in devices,
        "includes_expected_watch_device": (not expected_watch_device) or expected_watch_device in devices,
        "developer_certificate_count": len(certs),
        "entitlements": entitlements,
    }

def bundle_report(path):
    info = read_plist(path / "Info.plist") or {}
    profile = decode_mobileprovision(path / "embedded.mobileprovision")
    code_resources = path / "_CodeSignature" / "CodeResources"
    executable = info.get("CFBundleExecutable")
    executable_path = path / executable if executable else None
    return {
        "path": str(path.relative_to(root)),
        "exists": path.exists(),
        "bundle_id": info.get("CFBundleIdentifier"),
        "display_name": info.get("CFBundleDisplayName") or info.get("CFBundleName"),
        "executable": executable,
        "executable_present": bool(executable_path and executable_path.exists()),
        "minimum_os": info.get("MinimumOSVersion"),
        "supported_platforms": info.get("CFBundleSupportedPlatforms"),
        "device_families": info.get("UIDeviceFamily"),
        "wk_companion_app_bundle_identifier": info.get("WKCompanionAppBundleIdentifier"),
        "wk_application": info.get("WKApplication"),
        "wk_watchkit_app": info.get("WKWatchKitApp"),
        "embedded_provisioning_present": bool(profile),
        "embedded_provisioning": profile,
        "code_resources_present": code_resources.exists(),
        "code_resources_bytes": code_resources.stat().st_size if code_resources.exists() else 0,
    }

payload = root / "Payload"
apps = sorted(payload.glob("*.app"))
iphone = apps[0] if apps else None
if not iphone:
    raise SystemExit("No .app bundle found in Payload.")

def is_watch_app(path):
    info = read_plist(path / "Info.plist") or {}
    platforms = [str(platform).lower() for platform in info.get("CFBundleSupportedPlatforms") or []]
    families = [str(family) for family in info.get("UIDeviceFamily") or []]
    return bool(info.get("WKApplication") or "watchos" in platforms or "4" in families)

def parent_watch_resource_hashes_current(iphone_path, watch_path):
    if not watch_path or watch_path == iphone_path:
        return False
    resources_path = iphone_path / "_CodeSignature" / "CodeResources"
    if not resources_path.exists():
        return False
    resources = read_plist(resources_path) or {}
    files2 = resources.get("files2") or {}
    checked = 0
    for path in watch_path.rglob("*"):
        if not path.is_file():
            continue
        rel = path.relative_to(iphone_path).as_posix()
        entry = files2.get(rel)
        if not isinstance(entry, dict) or "hash2" not in entry:
            continue
        expected = entry["hash2"]
        expected_bytes = base64.b64decode(expected) if isinstance(expected, str) else bytes(expected)
        actual = hashlib.sha256(path.read_bytes()).digest()
        checked += 1
        if actual != expected_bytes:
            return False
    return checked > 0

watch_apps = []
for container_name in ("PlugIns", "Watch"):
    container = iphone / container_name
    if container.exists():
        watch_apps.extend(path for path in sorted(container.glob("*.app")) if is_watch_app(path))
watch = watch_apps[0] if watch_apps else None

iphone_info = read_plist(iphone / "Info.plist") or {}
if (
    not watch
    and iphone_info.get("CFBundleSupportedPlatforms")
    and any(str(platform).lower() == "watchos" for platform in iphone_info.get("CFBundleSupportedPlatforms"))
):
    watch = iphone

report = {
    "input": sys.argv[7],
    "iphone": bundle_report(iphone),
    "watch": bundle_report(watch) if watch else {"exists": False},
    "checks": {},
}

checks = report["checks"]
checks["watch_bundle_present"] = bool(watch)
checks["iphone_code_resources_present"] = report["iphone"]["code_resources_present"]
checks["iphone_provisioning_present"] = report["iphone"]["embedded_provisioning_present"]
checks["watch_code_resources_present"] = bool(watch and report["watch"]["code_resources_present"])
checks["watch_provisioning_present"] = bool(watch and report["watch"]["embedded_provisioning_present"])
checks["iphone_bundle_matches_expected"] = (not expected_iphone) or report["iphone"]["bundle_id"] == expected_iphone
checks["watch_bundle_matches_expected"] = (not expected_watch) or (watch and report["watch"]["bundle_id"] == expected_watch)
checks["watch_companion_matches_expected"] = (
    (not expected_companion)
    or (watch and report["watch"]["wk_companion_app_bundle_identifier"] == expected_companion)
)
checks["watch_info_marks_watch_app"] = bool(
    watch
    and (report["watch"].get("wk_application") or report["watch"].get("wk_watchkit_app"))
)
checks["watch_info_uses_single_watch_app_key"] = bool(
    watch
    and not (report["watch"].get("wk_application") and report["watch"].get("wk_watchkit_app"))
)
checks["watch_supported_platform_is_watchos"] = bool(
    watch
    and any(str(p).lower() == "watchos" for p in (report["watch"].get("supported_platforms") or []))
)
checks["watch_device_family_is_watch"] = bool(
    watch
    and "4" in [str(family) for family in (report["watch"].get("device_families") or [])]
)
checks["iphone_code_resources_watch_hashes_current"] = parent_watch_resource_hashes_current(iphone, watch) if watch else False

watch_profile = report["watch"].get("embedded_provisioning") if watch else None
watch_entitlements = (watch_profile or {}).get("entitlements") or {}
watch_app_id = watch_entitlements.get("application-identifier", "")
watch_bundle = report["watch"].get("bundle_id") if watch else ""
checks["watch_profile_mentions_watch_bundle"] = bool(
    watch_profile and watch_bundle and watch_app_id.endswith("." + watch_bundle)
)
checks["watch_profile_platform_supported"] = bool(
    watch_profile and any(str(p).lower() in ("ios", "watchos") for p in (watch_profile.get("platform") or []))
)
checks["iphone_profile_includes_expected_iphone_device"] = bool(
    report["iphone"].get("embedded_provisioning")
    and report["iphone"]["embedded_provisioning"].get("includes_expected_iphone_device")
)
checks["iphone_profile_includes_expected_watch_device"] = bool(
    report["iphone"].get("embedded_provisioning")
    and report["iphone"]["embedded_provisioning"].get("includes_expected_watch_device")
)
checks["watch_profile_includes_expected_iphone_device"] = bool(
    watch_profile and watch_profile.get("includes_expected_iphone_device")
)
checks["watch_profile_includes_expected_watch_device"] = bool(
    watch_profile and watch_profile.get("includes_expected_watch_device")
)

print(json.dumps(report, indent=2, sort_keys=True))

failed = [name for name, ok in checks.items() if ok is False]
if failed:
    print("\nFAILED CHECKS:")
    for name in failed:
        print(f"- {name}")
    raise SystemExit(2)
'@

$scriptPath = Join-Path $workRoot "inspect_ipa_signing.py"
New-Item -ItemType Directory -Force -Path $workRoot | Out-Null
Set-Content -LiteralPath $scriptPath -Value $inspector -Encoding UTF8

$expectedIphoneArg = if ($ExpectedIphoneBundleId) { $ExpectedIphoneBundleId } else { "__EMPTY__" }
$expectedWatchArg = if ($ExpectedWatchBundleId) { $ExpectedWatchBundleId } else { "__EMPTY__" }
$expectedCompanionArg = if ($ExpectedWatchCompanionBundleId) { $ExpectedWatchCompanionBundleId } else { "__EMPTY__" }
$expectedIphoneDeviceArg = if ($ExpectedIphoneDeviceUdid) { $ExpectedIphoneDeviceUdid } else { "__EMPTY__" }
$expectedWatchDeviceArg = if ($ExpectedWatchDeviceUdid) { $ExpectedWatchDeviceUdid } else { "__EMPTY__" }

& $python.Source $scriptPath $expandRoot $expectedIphoneArg $expectedWatchArg $expectedCompanionArg $expectedIphoneDeviceArg $expectedWatchDeviceArg $inputDescription
$inspectionExitCode = $LASTEXITCODE

if ($ReportOnly -and $inspectionExitCode -ne 0) {
    Write-Warning "IPA signing inspection found incomplete signing/provisioning, but -ReportOnly was set."
    exit 0
}

exit $inspectionExitCode
