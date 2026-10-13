"""Fail closed on missing companions, temporary IDs, test hooks or private resources."""
import argparse
import json
import plistlib
import re
from pathlib import Path

PHONE_ID = "com.inclusophy.tennistracker"
GROUP_ID = "group.com.inclusophy.tennistracker"
APP_NAME = "Court Story"
BUILD = "34"
CONNECT_DATA_TYPES = {'NSPrivacyCollectedDataTypeFitness', 'NSPrivacyCollectedDataTypeUserID', 'NSPrivacyCollectedDataTypeEmailsOrTextMessages', 'NSPrivacyCollectedDataTypeName', 'NSPrivacyCollectedDataTypeDeviceID', 'NSPrivacyCollectedDataTypeEmailAddress', 'NSPrivacyCollectedDataTypeOtherUserContent'}
FORBIDDEN_SUFFIXES = {".json", ".db", ".sqlite", ".sqlite3", ".p8", ".p12", ".pem", ".swift", ".csv", ".log"}
TEST_MARKERS = (b"-ui-testing-", b"-watch-manual-match", b"-test-notification-", b"TennisRegressionFixtures", b"TennisNotificationTestSupport")


def verify_connect_config(path):
    if not path.is_file():
        raise ValueError("Connect release requires the production service configuration")
    config = json.loads(path.read_bytes())
    if not isinstance(config, dict) or set(config) != {"supabase_url", "publishable_key", "link_host"}:
        raise ValueError("Connect configuration contains unexpected or private fields")
    if config["supabase_url"] != "https://vfgxingpburwhrjbibvf.supabase.co":
        raise ValueError("Connect configuration must target the approved production project")
    if not isinstance(config["publishable_key"], str) or not re.fullmatch(r"sb_publishable_[A-Za-z0-9_-]{20,200}", config["publishable_key"]):
        raise ValueError("Connect must use a public publishable key, never a secret or service-role key")
    host = config["link_host"]
    if not isinstance(host, str) or not re.fullmatch(r"[a-z0-9](?:[a-z0-9-]*[a-z0-9])?(?:\.[a-z0-9](?:[a-z0-9-]*[a-z0-9])?)+", host) or host.endswith((".invalid", ".example", ".localhost")):
        raise ValueError("Connect invitation host must be a production HTTPS domain")


def verify(app):
    app = Path(app)
    watches = list((app / "Watch").glob("*.app"))
    if len(watches) != 1 or list((app / "PlugIns").glob("*.app")):
        raise ValueError("Exactly one companion must be embedded under iPhone.app/Watch")
    watch = watches[0]
    widgets = list((watch / "PlugIns").glob("*.appex"))
    if len(widgets) != 1:
        raise ValueError("The Watch complication extension is missing or duplicated")
    expected = ((app, PHONE_ID), (watch, PHONE_ID + ".watchkitapp"), (widgets[0], PHONE_ID + ".watchkitapp.widgets"))
    report = []
    for bundle, identifier in expected:
        info = plistlib.loads((bundle / "Info.plist").read_bytes())
        if info.get("CFBundleIdentifier") != identifier:
            raise ValueError("Unexpected permanent bundle identifier")
        if (info.get("CFBundleShortVersionString"), info.get("CFBundleVersion")) != ("0.1.0", BUILD):
            raise ValueError("All components must be version 0.1.0 build " + BUILD)
        if info.get("CFBundleDisplayName") != APP_NAME or info.get("CFBundleName") != APP_NAME:
            raise ValueError("Every component must expose the full Court Story app name")
        if b"Tennis Tracker" in plistlib.dumps(info):
            raise ValueError("Old branding remains in app metadata or permission descriptions")
        if bundle == app and (info.get("UIFileSharingEnabled") is not True or info.get("LSSupportsOpeningDocumentsInPlace") is not True):
            raise ValueError("Private owner restore requires the user's Files document route")
        if bundle == app:
            orientations = info.get("UISupportedInterfaceOrientations", [])
            if not isinstance(orientations, list) or "UIInterfaceOrientationPortrait" not in orientations:
                raise ValueError("Phone interface orientations must be explicitly configured")
            if 2 in info.get("UIDeviceFamily", []):
                ipad = info.get("UISupportedInterfaceOrientations~ipad", orientations)
                required = {"UIInterfaceOrientationPortrait", "UIInterfaceOrientationPortraitUpsideDown",
                            "UIInterfaceOrientationLandscapeLeft", "UIInterfaceOrientationLandscapeRight"}
                if not isinstance(ipad, list) or set(ipad) != required:
                    raise ValueError("Declared iPad support requires all four interface orientations")
        executable = bundle / info["CFBundleExecutable"]
        if not executable.is_file() or executable.stat().st_size == 0:
            raise ValueError("Missing compiled executable")
        binary = executable.read_bytes()
        if any(marker in binary for marker in (b"Tennis Tracker", b"Inclusophy")):
            raise ValueError("Old public branding remains in a release executable")
        if any(marker in binary for marker in TEST_MARKERS):
            raise ValueError("A simulator fixture or destructive test hook is present in a release executable")
        manifest = plistlib.loads((bundle / "PrivacyInfo.xcprivacy").read_bytes())
        collected=manifest.get("NSPrivacyCollectedDataTypes", [])
        if manifest.get("NSPrivacyTracking") is not False or {row.get("NSPrivacyCollectedDataType") for row in collected} != CONNECT_DATA_TYPES:
            raise ValueError("Privacy manifest must disclose optional Connect data collection")
        if any(row.get("NSPrivacyCollectedDataTypeTracking") is not False or row.get("NSPrivacyCollectedDataTypeLinked") is not True or row.get("NSPrivacyCollectedDataTypePurposes") != ["NSPrivacyCollectedDataTypePurposeAppFunctionality"] for row in collected):
            raise ValueError("Connect data must be declared for app functionality without tracking")
        if bundle != app and info.get("TennisSharedAppGroup") != GROUP_ID:
            raise ValueError("A temporary or incorrect App Group is configured")
        report.append({"bundle": identifier, "version": "0.1.0", "build": BUILD, "displayName": APP_NAME})
    watch_info = plistlib.loads((watch / "Info.plist").read_bytes())
    if watch_info.get("WKCompanionAppBundleIdentifier") != PHONE_ID or watch_info.get("WKApplication") is not True:
        raise ValueError("Watch companion association is incorrect")
    widget_info = plistlib.loads((widgets[0] / "Info.plist").read_bytes())
    if widget_info.get("NSExtension", {}).get("NSExtensionPointIdentifier") != "com.apple.widgetkit-extension":
        raise ValueError("Incorrect complication extension type")
    verify_connect_config(app / "CourtConnectConfig.json")
    count = 0
    for path in app.rglob("*"):
        if not path.is_file():
            continue
        count += 1
        name = path.name.lower()
        relative = path.relative_to(app).as_posix().lower()
        if path == app / "CourtConnectConfig.json":
            continue
        if path.name == "version.json" and path.parent.name == "Metadata.appintents" and path.parent.parent in {bundle for bundle, _ in expected}:
            metadata = json.loads(path.read_bytes())
            if not isinstance(metadata, dict) or set(metadata) != {"toolsVersion", "version"}:
                raise ValueError("Unexpected App Intents version metadata fields")
            if not isinstance(metadata["toolsVersion"], str) or not re.fullmatch(r"[A-Za-z0-9.]{1,30}", metadata["toolsVersion"]):
                raise ValueError("Unexpected App Intents tools version")
            if not isinstance(metadata["version"], str) or not re.fullmatch(r"[0-9]{1,3}(?:\.[0-9]{1,3}){0,2}", metadata["version"]):
                raise ValueError("Unexpected App Intents metadata version")
            continue
        if path.suffix.lower() in FORBIDDEN_SUFFIXES or any(part in relative for part in ("backup", "fixture", "watchsnapshot", "watch-preferences", "tennis-tracker-data", "sqlite-wal", "sqlite-shm")):
            raise ValueError("Unexpected data/source resource in release: " + relative)
        if name.endswith(".plist") and name != "info.plist":
            raise ValueError("Unreviewed property-list resource: " + relative)
    return {"components": report, "resource_files_checked": count, "personal_data_resources": "none", "test_hooks": "absent", "signing": "requires separate Apple distribution verification"}


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--app", required=True, type=Path)
    args = parser.parse_args()
    print(json.dumps(verify(args.app), indent=2))
