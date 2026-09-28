"""Validate and patch widget metadata before the existing nested signing pass."""
import argparse
from copy import deepcopy
from pathlib import Path
import plistlib
import subprocess


def prepare_metadata(watch, widget, watch_profile, widget_profile, watch_id, widget_id, group):
    if not widget_id.startswith(watch_id + "."):
        raise ValueError("Widget identifier must be inside the existing Watch identity")
    if not group.startswith("group.") or group.endswith(".preview"):
        raise ValueError("A registered non-preview shared container is required")
    if widget.get("NSExtension", {}).get("NSExtensionPointIdentifier") != "com.apple.widgetkit-extension":
        raise ValueError("Expected a WidgetKit extension")
    if widget.get("CFBundleVersion") != watch.get("CFBundleVersion"):
        raise ValueError("Watch and widget versions differ")
    if watch_profile.get("TeamIdentifier") != widget_profile.get("TeamIdentifier"):
        raise ValueError("Watch and widget signing teams differ")
    for profile, identifier in ((watch_profile, watch_id), (widget_profile, widget_id)):
        entitlements = profile.get("Entitlements", {})
        prefixes = profile.get("ApplicationIdentifierPrefix") or profile.get("TeamIdentifier") or []
        if not prefixes or entitlements.get("application-identifier") != prefixes[0] + "." + identifier:
            raise ValueError("Provisioning profile does not authorize the exact bundle identifier")
        if group not in entitlements.get("com.apple.security.application-groups", []):
            raise ValueError("Both profiles must authorize the shared container")
    if watch.get("TennisHealthEnabled") and not watch_profile["Entitlements"].get("com.apple.developer.healthkit"):
        raise ValueError("The existing Health capability must remain authorized")
    updated_watch, updated_widget = deepcopy(watch), deepcopy(widget)
    updated_watch["TennisSharedAppGroup"] = group
    updated_widget["TennisSharedAppGroup"] = group
    updated_widget["CFBundleIdentifier"] = widget_id
    return updated_watch, updated_widget


def decode_profile(path, openssl):
    result = subprocess.run([str(openssl), "cms", "-verify", "-inform", "DER", "-noverify"],
                            input=path.read_bytes(), capture_output=True, check=True)
    return plistlib.loads(result.stdout)


def main(args):
    widgets = list((args.watch_app / "PlugIns").glob("*.appex"))
    if len(widgets) != 1:
        raise ValueError("Exactly one Watch widget extension is required")
    watch_file, widget_file = args.watch_app / "Info.plist", widgets[0] / "Info.plist"
    watch, widget = prepare_metadata(plistlib.loads(watch_file.read_bytes()), plistlib.loads(widget_file.read_bytes()),
        decode_profile(args.watch_profile, args.openssl), decode_profile(args.widget_profile, args.openssl),
        args.watch_id, args.widget_id, args.group)
    watch_file.write_bytes(plistlib.dumps(watch, sort_keys=False))
    widget_file.write_bytes(plistlib.dumps(widget, sort_keys=False))
    print("Widget identity, shared container and retained Health capability validated before signing.")


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    for name in ("watch-app", "watch-profile", "widget-profile", "openssl"):
        parser.add_argument("--" + name, type=Path, required=True)
    for name in ("watch-id", "widget-id", "group"):
        parser.add_argument("--" + name, required=True)
    main(parser.parse_args())
