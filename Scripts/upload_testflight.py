"""Native macOS distribution from encrypted CI secrets, never from owner data or free-team rewriting."""
import base64
import datetime as dt
import json
import os
import plistlib
import re
import secrets
import shlex
import subprocess
import sys
import tempfile
import uuid
import zipfile
from pathlib import Path

from verify_testflight_release import GROUP_ID, PHONE_ID, verify
from verify_testflight_signing import TEAM_ID, verify_signing
from verify_app_icons import compiled_icons, native_catalogues, source_icons

TARGETS = {
    "TennisTracker": (PHONE_ID, "TENNIS_PHONE_PROFILE"),
    "TennisTrackerWatchApp": (PHONE_ID + ".watchkitapp", "TENNIS_WATCH_PROFILE"),
    "TennisTrackerWatchWidgets": (PHONE_ID + ".watchkitapp.widgets", "TENNIS_WIDGET_PROFILE"),
}
REQUIRED = ("TENNIS_DISTRIBUTION_P12", "TENNIS_DISTRIBUTION_PASSWORD", "TENNIS_ASC_PRIVATE_KEY",
            "TENNIS_ASC_KEY_ID", "TENNIS_ASC_ISSUER_ID", *(value[1] for value in TARGETS.values()))


def require_credentials(environment):
    missing = [name for name in REQUIRED if not environment.get(name)]
    if missing:
        raise ValueError("Signing is not configured. Missing encrypted secrets: " + ", ".join(missing))
    if not re.fullmatch(r"[A-Z0-9]{10}", environment["TENNIS_ASC_KEY_ID"]):
        raise ValueError("Invalid App Store Connect key identifier")
    uuid.UUID(environment["TENNIS_ASC_ISSUER_ID"])


def profile_identifier(profile, identifier, now=None):
    now = now or dt.datetime.now(dt.timezone.utc)
    entitlement = profile.get("Entitlements", {})
    expiry = profile.get("ExpirationDate")
    if profile.get("TeamIdentifier") != [TEAM_ID] or entitlement.get("application-identifier") != TEAM_ID + "." + identifier:
        raise ValueError("A distribution profile does not match the permanent app identity")
    if "ProvisionedDevices" in profile or profile.get("ProvisionsAllDevices") or entitlement.get("get-task-allow") is not False:
        raise ValueError("TestFlight requires App Store distribution profiles, not development, ad hoc or enterprise profiles")
    if not isinstance(expiry, dt.datetime) or expiry.replace(tzinfo=dt.timezone.utc) <= now:
        raise ValueError("A distribution profile is expired")
    if identifier != PHONE_ID and GROUP_ID not in entitlement.get("com.apple.security.application-groups", []):
        raise ValueError("Watch and complication profiles must authorize the permanent App Group")
    if identifier == PHONE_ID + ".watchkitapp" and entitlement.get("com.apple.developer.healthkit") is not True:
        raise ValueError("The Watch distribution profile must authorize HealthKit")
    uuid.UUID(profile["UUID"])
    return profile["UUID"]


def export_options(profiles):
    expected = {value[0] for value in TARGETS.values()}
    if set(profiles) != expected or len(set(profiles.values())) != 3:
        raise ValueError("Export requires three distinct component profiles")
    return {"method": "app-store-connect", "destination": "export", "teamID": TEAM_ID,
            "signingStyle": "manual", "signingCertificate": "Apple Distribution",
            "provisioningProfiles": profiles, "manageAppVersionAndBuildNumber": False, "uploadSymbols": True}


def run(stage, *command, environment=None):
    print(stage, flush=True)
    if environment is None:
        environment = {key: value for key, value in os.environ.items() if key not in REQUIRED}
    result = subprocess.run(command, capture_output=True, env=environment, check=False)
    if result.returncode:
        diagnostics = failure_categories(result.stdout, result.stderr)
        if diagnostics:
            print("Native failure categories: " + ", ".join(diagnostics), flush=True)
        encrypt_failure_diagnostic(stage, result.stdout, result.stderr)
        # Native signing output can contain account names/profile details. Never publish it to a public build log.
        raise RuntimeError(stage + " failed (exit " + str(result.returncode) + "). Raw signing output withheld; no subsequent step ran.")
    return result.stdout


def encrypt_failure_diagnostic(stage, stdout, stderr):
    recipient = os.environ.get("TENNIS_DIAGNOSTIC_RECIPIENT")
    runner_temp = os.environ.get("RUNNER_TEMP")
    if not recipient or not runner_temp:
        return
    try:
        with tempfile.TemporaryDirectory(prefix="tennis-diagnostic-recipient-", dir=runner_temp) as directory:
            certificate = Path(directory) / "recipient.pem"
            certificate.write_text(recipient, encoding="ascii")
            output = ((stdout or b"") + b"\n" + (stderr or b""))[-2 * 1024 * 1024:]
            environment = {key: value for key, value in os.environ.items() if key not in REQUIRED}
            encrypted = subprocess.run(["openssl", "cms", "-encrypt", "-binary", "-aes256", "-outform", "DER", "-recip", str(certificate)],
                                       input=output, capture_output=True, check=False, env=environment)
            if encrypted.returncode or not encrypted.stdout:
                raise ValueError("Diagnostic encryption failed")
            target = Path(runner_temp) / "tennis-private-diagnostics" / (re.sub(r"[^a-zA-Z0-9-]", "-", stage)[:80] + ".cms")
            write_secret(target, encrypted.stdout)
            print("Encrypted failure diagnostic prepared; decryption key is not on this runner.", flush=True)
    except Exception:
        print("Encrypted diagnostics unavailable; raw native output remains withheld.", flush=True)


def failure_categories(stdout, stderr):
    output = ((stdout or b"") + b"\n" + (stderr or b"")).decode("utf-8", errors="replace").lower()
    patterns = {
        "profile_not_found": r"no profiles? for|doesn't have .*provisioning profile|could not find.*provisioning profile|requires a provisioning profile",
        "profile_certificate_mismatch": r"(?:doesn't|does not) include signing certificate",
        "profile_entitlement_mismatch": r"provisioning profile.*(?:doesn't support|does not support|doesn't include the|doesn't match)",
        "profile_expired": r"provisioning profile.*(?:has expired|is expired)",
        "signing_certificate_missing": r"no signing certificate|no valid.*signing identities",
        "certificate_chain_untrusted": r"unable to build chain|certificate.*not trusted",
        "keychain_interaction_required": r"user interaction is not allowed|errsecinternalcomponent",
        "pkcs12_import_failure": r"mac verification failed during pkcs12 import",
        "code_sign_command_failed": r"command codesign failed",
        "duplicate_build_output": r"multiple commands produce",
        "apple_validation_rejected": r"validation failed|asset validation failed",
    }
    return [category for category, pattern in patterns.items() if re.search(pattern, output)]


def write_secret(path, data):
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_bytes(data)
    path.chmod(0o600)


def main():
    require_credentials(os.environ)
    if sys.platform != "darwin":
        raise ValueError("Apple distribution requires the macOS runner")
    if os.environ.get("GITHUB_REF") != "refs/heads/codex/testflight-beta":
        raise ValueError("Distribution is restricted to the reviewed beta branch")
    credential_values = {name: os.environ.pop(name) for name in REQUIRED}
    root = Path(__file__).resolve().parent.parent
    os.chdir(root)
    profile_directory = Path.home() / "Library/Developer/Xcode/UserData/Provisioning Profiles"
    profile_directory.mkdir(parents=True, exist_ok=True)
    installed_profiles = []
    spec = root / "project-testflight-signing.generated.json"
    if spec.exists():
        raise ValueError("Refusing to replace an existing generated signing configuration")
    with tempfile.TemporaryDirectory(prefix="tennis-distribution-", dir=os.environ.get("RUNNER_TEMP")) as temporary:
        temporary = Path(temporary)
        keychain = temporary / "signing.keychain-db"
        password = secrets.token_urlsafe(32)
        child_environment = {key: value for key, value in os.environ.items() if key not in REQUIRED}
        original_keychains = shlex.split(run("Read signing keychain search path", "security", "list-keychains", "-d", "user").decode())
        try:
            write_secret(temporary / "distribution.p12", base64.b64decode(credential_values["TENNIS_DISTRIBUTION_P12"], validate=True))
            run("Create temporary signing keychain", "security", "create-keychain", "-p", password, str(keychain))
            run("Unlock temporary signing keychain", "security", "unlock-keychain", "-p", password, str(keychain))
            run("Set temporary keychain timeout", "security", "set-keychain-settings", "-lut", "21600", str(keychain))
            run("Import distribution certificate", "security", "import", str(temporary / "distribution.p12"), "-k", str(keychain), "-P", credential_values["TENNIS_DISTRIBUTION_PASSWORD"], "-T", "/usr/bin/codesign")
            run("Authorize native code signing", "security", "set-key-partition-list", "-S", "apple-tool:,apple:", "-k", password, str(keychain))
            run("Make distribution certificate available to Xcode", "security", "list-keychains", "-d", "user", "-s", str(keychain), *original_keychains)
            profile_map, settings = {}, {}
            for target, (identifier, secret_name) in TARGETS.items():
                path = temporary / (target + ".mobileprovision")
                write_secret(path, base64.b64decode(credential_values[secret_name], validate=True))
                profile = plistlib.loads(run("Inspect " + target + " distribution profile", "security", "cms", "-D", "-i", str(path)))
                profile_id = profile_identifier(profile, identifier)
                destination = profile_directory / (profile_id + ".mobileprovision")
                if destination.exists():
                    if destination.read_bytes() != path.read_bytes():
                        raise ValueError("Refusing to replace an unrelated installed profile")
                else:
                    write_secret(destination, path.read_bytes())
                    installed_profiles.append(destination)
                profile_map[identifier] = profile_id
                settings[target] = {"settings": {"base": {"CODE_SIGN_STYLE": "Manual", "CODE_SIGN_IDENTITY": "Apple Distribution", "PROVISIONING_PROFILE_SPECIFIER": profile_id}}}
            write_secret(spec, json.dumps({"include": ["project-testflight.yml"], "targets": settings}).encode())
            options = temporary / "ExportOptions.plist"
            write_secret(options, plistlib.dumps(export_options(profile_map)))
            run("Generate native distribution project", "xcodegen", "generate", "--spec", str(spec), environment=child_environment)
            archive = temporary / "TennisTracker.xcarchive"
            run("Archive iPhone, Watch and complication", "xcodebuild", "archive", "-project", "TennisTrackeriOS.xcodeproj", "-scheme", "TennisTrackerTestFlight", "-destination", "generic/platform=iOS", "-configuration", "Release", "-archivePath", str(archive), "OTHER_CODE_SIGN_FLAGS=--keychain " + str(keychain), environment=child_environment)
            verify(archive / "Products/Applications/TennisTracker.app")
            exported = temporary / "Export"
            run("Export App Store package", "xcodebuild", "-exportArchive", "-archivePath", str(archive), "-exportOptionsPlist", str(options), "-exportPath", str(exported), environment=child_environment)
            ipas = list(exported.glob("*.ipa"))
            if len(ipas) != 1: raise ValueError("Export did not produce exactly one IPA")
            source_icons(root)
            with zipfile.ZipFile(ipas[0]) as package:
                print(json.dumps(compiled_icons(package, native_catalogues(package))), flush=True)
            inspection = temporary / "Inspection"
            run("Extract a read-only inspection copy", "ditto", "-x", "-k", str(ipas[0]), str(inspection), environment=child_environment)
            apps = list((inspection / "Payload").glob("*.app"))
            if len(apps) != 1: raise ValueError("Exported IPA must contain exactly one phone app")
            print(json.dumps(verify_signing(apps[0]), indent=2), flush=True)
            api_keys = temporary / "private_keys"
            write_secret(api_keys / ("AuthKey_" + credential_values["TENNIS_ASC_KEY_ID"] + ".p8"), credential_values["TENNIS_ASC_PRIVATE_KEY"].encode())
            child_environment["API_PRIVATE_KEYS_DIR"] = str(api_keys)
            credentials = ("--apiKey", credential_values["TENNIS_ASC_KEY_ID"], "--apiIssuer", credential_values["TENNIS_ASC_ISSUER_ID"])
            run("Validate package with Apple", "xcrun", "altool", "--validate-app", "--file", str(ipas[0]), "--type", "ios", *credentials, environment=child_environment)
            run("Upload validated package to Apple", "xcrun", "altool", "--upload-app", "--file", str(ipas[0]), "--type", "ios", *credentials, environment=child_environment)
            print("Upload completed. Apple processing, owner-only internal testing and physical installation still require verification.")
        finally:
            subprocess.run(["security", "list-keychains", "-d", "user", "-s", *original_keychains], capture_output=True, check=False)
            if keychain.exists():
                subprocess.run(["security", "delete-keychain", str(keychain)], capture_output=True, check=False)
            for path in installed_profiles: path.unlink(missing_ok=True)
            spec.unlink(missing_ok=True)


if __name__ == "__main__":
    try:
        main()
    except Exception as error:
        print(str(error), file=sys.stderr)
        raise SystemExit(1)
