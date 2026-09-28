"""Read-only deployment preflight; platform trust and launch still require the devices."""
import argparse
from datetime import datetime, timezone
import fnmatch
import json
from pathlib import Path
import plistlib
import subprocess
import zipfile

from verify_macho_seals import check_bundle, signature_blobs, slices


def validate_architecture(infos, allow_widgets=False):
    phone = [path for path in infos if path.startswith("Payload/") and path.count("/") == 2 and path.endswith(".app/")]
    if len(phone) != 1:
        raise ValueError("Expected one top-level iPhone app")
    watch = [path for path in infos if path.startswith(phone[0] + "Watch/") and path.count("/") == 4 and path.endswith(".app/")]
    if len(watch) != 1:
        raise ValueError("Watch app must remain in the iPhone app's Watch directory")
    extensions = [path for path in infos if path.endswith(".appex/")]
    if extensions and not allow_widgets:
        raise ValueError("Widget extension requires a separately approved deployment stage")
    for path in extensions:
        if not path.startswith(watch[0] + "PlugIns/"):
            raise ValueError("Unexpected extension location")
        extension, companion = infos[path], infos[watch[0]]
        if not extension.get("CFBundleIdentifier", "").startswith(companion["CFBundleIdentifier"] + "."):
            raise ValueError("Widget identity is not nested under the Watch identity")
        if extension.get("NSExtension", {}).get("NSExtensionPointIdentifier") != "com.apple.widgetkit-extension":
            raise ValueError("Unexpected extension type")
        if extension.get("CFBundleVersion") != companion.get("CFBundleVersion"):
            raise ValueError("Watch and widget build versions differ")
        group = companion.get("TennisSharedAppGroup")
        if not group or group.endswith(".preview") or extension.get("TennisSharedAppGroup") != group:
            raise ValueError("Watch and widget must use the same registered shared container")
    for path in infos:
        if path.endswith(".app/") and path not in (phone[0], watch[0]):
            raise ValueError("Unexpected additional application bundle")
    wi = infos[watch[0]]
    if wi.get("WKApplication") is not True or wi.get("WKWatchKitApp"):
        raise ValueError("Working single-target Watch metadata changed")
    if wi.get("WKCompanionAppBundleIdentifier") != infos[phone[0]]["CFBundleIdentifier"]:
        raise ValueError("Watch companion identifier mismatch")
    return phone[0], watch[0]


def permits(granted, requested):
    if isinstance(requested, list):
        return isinstance(granted, list) and all(any(permits(g, value) for g in granted) for value in requested)
    if isinstance(requested, str):
        return isinstance(granted, str) and fnmatch.fnmatchcase(requested, granted)
    return granted == requested


def inspect(candidate, baseline, repo, openssl, allow_health=False, allow_widgets=False):
    with zipfile.ZipFile(baseline) as old, zipfile.ZipFile(candidate) as archive:
        def infos(z):
            return {name.removesuffix("Info.plist"): plistlib.loads(z.read(name)) for name in z.namelist()
                    if name.endswith((".app/Info.plist", ".appex/Info.plist"))}
        before, after = infos(old), infos(archive)
        old_phone, old_watch = validate_architecture(before, allow_widgets=True)
        phone, watch = validate_architecture(after, allow_widgets=allow_widgets)
        for prior, current in ((old_phone, phone), (old_watch, watch)):
            if prior != current or before[prior]["CFBundleIdentifier"] != after[current]["CFBundleIdentifier"]:
                raise ValueError("Working bundle path or identifier changed")
        results = []
        for path, info in after.items():
            seal = check_bundle(archive, path)
            if seal["failures"]:
                raise ValueError("Signature content failed: " + "; ".join(seal["failures"]))
            profile = plistlib.loads(subprocess.run(
                [str(openssl), "cms", "-verify", "-inform", "DER", "-noverify"],
                input=archive.read(path + "embedded.mobileprovision"),
                capture_output=True, check=True
            ).stdout)
            expiry = profile["ExpirationDate"].replace(tzinfo=timezone.utc)
            if expiry <= datetime.now(timezone.utc):
                raise ValueError("Provisioning profile expired")
            metadata = json.loads((repo / "work/signing-assets" / ("iphone" if path == phone else "watch") / "bundle.json").read_text(encoding="utf-8-sig"))
            if metadata["udid"] not in profile.get("ProvisionedDevices", []):
                raise ValueError("Physical device is missing from its profile")
            for executable in slices(archive.read(path + info["CFBundleExecutable"])):
                entitlements = plistlib.loads(signature_blobs(executable)[5][8:])
                if not entitlements.get("application-identifier", "").endswith("." + info["CFBundleIdentifier"]):
                    raise ValueError("Signed application identity does not match bundle metadata")
                for key, value in entitlements.items():
                    if not permits(profile["Entitlements"].get(key), value):
                        raise ValueError("Profile does not authorize signed entitlement " + key)
                if entitlements.get("com.apple.developer.healthkit") and not allow_health:
                    raise ValueError("HealthKit requires its separately approved deployment stage")
                if entitlements.get("com.apple.security.application-groups") and not allow_widgets:
                    raise ValueError("Shared container requires its separately approved deployment stage")
                if info.get("TennisHealthEnabled") and not entitlements.get("com.apple.developer.healthkit"):
                    raise ValueError("Health feature enabled without signed HealthKit authorization")
                group = info.get("TennisSharedAppGroup")
                if group and group not in entitlements.get("com.apple.security.application-groups", []):
                    raise ValueError("Shared snapshot container is not authorized")
            results.append({"component": "iPhone" if path == phone else "Watch" if path == watch else "Watch widget",
                            "build": info.get("CFBundleVersion"), "content_seals_valid": True,
                            "device_in_profile": True, "profile_expires": expiry.isoformat()})
        return {"preflight_passed": True, "components": results, "physical_install_and_launch_required": True}


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--candidate", type=Path, required=True)
    parser.add_argument("--baseline", type=Path, required=True)
    parser.add_argument("--repo", type=Path, required=True)
    parser.add_argument("--openssl", type=Path, required=True)
    parser.add_argument("--allow-health", action="store_true")
    parser.add_argument("--allow-widgets", action="store_true")
    args = parser.parse_args()
    print(json.dumps(inspect(args.candidate, args.baseline, args.repo, args.openssl, args.allow_health, args.allow_widgets), indent=2))
