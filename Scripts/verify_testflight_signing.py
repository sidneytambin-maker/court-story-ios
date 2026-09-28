"""Verify the exported App Store IPA's signatures on macOS, before uploading to Apple."""
import argparse
import datetime as dt
import json
import plistlib
import subprocess
import tempfile
from pathlib import Path

from verify_testflight_release import GROUP_ID, PHONE_ID, verify

TEAM_ID = "HT5X86Q4DD"


def allowed_value(claim, allowed):
    if isinstance(claim, str) and isinstance(allowed, str):
        return claim == allowed or (allowed.endswith("*") and claim.startswith(allowed[:-1]))
    if isinstance(claim, list) and isinstance(allowed, list):
        return all(any(allowed_value(item, option) for option in allowed) for item in claim)
    if isinstance(claim, dict) and isinstance(allowed, dict):
        return all(key in allowed and allowed_value(value, allowed[key]) for key, value in claim.items())
    return type(claim) is type(allowed) and claim == allowed


def check_profile(profile, entitlements, identifier, certificate, now=None):
    now = now or dt.datetime.now(dt.timezone.utc)
    expires = profile.get("ExpirationDate")
    if not isinstance(expires, dt.datetime) or expires.replace(tzinfo=dt.timezone.utc) <= now:
        raise ValueError("Missing or expired distribution profile")
    if profile.get("TeamIdentifier") != [TEAM_ID]:
        raise ValueError("Distribution profile belongs to the wrong team")
    if "ProvisionedDevices" in profile or profile.get("ProvisionsAllDevices"):
        raise ValueError("Device development, ad hoc and enterprise profiles cannot be used for this TestFlight upload")
    grants = profile.get("Entitlements", {})
    if grants.get("get-task-allow") is not False or entitlements.get("get-task-allow", False) is not False:
        raise ValueError("Debugging must be disabled in App Store distribution")
    if entitlements.get("application-identifier") != TEAM_ID + "." + identifier:
        raise ValueError("Signed application identity does not match its bundle")
    if entitlements.get("com.apple.developer.team-identifier") != TEAM_ID:
        raise ValueError("Signed application belongs to the wrong team")
    if not certificate or certificate not in profile.get("DeveloperCertificates", []):
        raise ValueError("The actual signing certificate is not authorized by the embedded profile")
    for key, claim in entitlements.items():
        if key not in grants or not allowed_value(claim, grants[key]):
            raise ValueError("Embedded profile does not authorize signed entitlement " + key)
    groups = entitlements.get("com.apple.security.application-groups", [])
    if groups != ([] if identifier == PHONE_ID else [GROUP_ID]):
        raise ValueError("Signed App Group does not match this component's privacy boundary")
    if identifier == PHONE_ID + ".watchkitapp" and entitlements.get("com.apple.developer.healthkit") is not True:
        raise ValueError("The Watch must retain its HealthKit capability")
    return {"bundle": identifier, "team": TEAM_ID, "profile_type": "app-store", "entitlements": "authorized", "signing_certificate": "matches_profile"}


def command(stage, *args):
    print(stage, flush=True)
    result = subprocess.run(args, capture_output=True, check=False)
    if result.returncode:
        # Keep account names, profile details and certificate subjects out of public CI logs.
        raise ValueError(stage + " failed; private native output withheld")
    return result.stdout


def extract_signing_certificate(bundle):
    with tempfile.TemporaryDirectory(prefix="tennis-signature-") as directory:
        prefix = str(Path(directory) / "certificate")
        # codesign's optional long-option value must be attached, not another bundle operand.
        command("Extract actual signing certificate", "codesign", "-d", "--extract-certificates=" + prefix, str(bundle))
        return Path(prefix + "0").read_bytes()


def verify_signing(app):
    app = Path(app).resolve()
    structure = verify(app)
    command("Verify complete exported signature tree", "codesign", "--verify", "--deep", "--strict", str(app))
    bundles = [app, *sorted((app / "Watch").glob("*.app")), *sorted((app / "Watch").glob("*.app/PlugIns/*.appex"))]
    report = []
    for bundle in bundles:
        command("Verify component signature", "codesign", "--verify", "--strict", str(bundle))
        info = plistlib.loads((bundle / "Info.plist").read_bytes())
        entitlements = plistlib.loads(command("Read signed component entitlements", "codesign", "-d", "--entitlements", ":-", str(bundle)))
        profile = plistlib.loads(command("Read embedded distribution profile", "security", "cms", "-D", "-i", str(bundle / "embedded.mobileprovision")))
        certificate = extract_signing_certificate(bundle)
        report.append(check_profile(profile, entitlements, info["CFBundleIdentifier"], certificate))
    return {"structure": structure["components"], "signed_components": report, "apple_processing": "not_yet_verified"}


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--app", required=True, type=Path, help="Phone .app extracted without changes from the exported IPA")
    args = parser.parse_args()
    print(json.dumps(verify_signing(args.app), indent=2))
