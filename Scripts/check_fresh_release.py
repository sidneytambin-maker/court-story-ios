"""Exercise first launch in two disposable simulator containers, never an owner's device."""
import argparse
import json
import plistlib
import subprocess
import time
import uuid
from pathlib import Path


def run(*args):
    return subprocess.check_output(["xcrun", "simctl", *map(str, args)], text=True).strip()


def check_empty(data):
    for key in ("players", "matches", "trainingSessions", "tournaments", "deletedRecordIDs"):
        if data.get(key) != []: raise ValueError("Fresh installation contains unexpected " + key)
    if any(data.get("setup", {}).get(key) != [] for key in ("coaches", "venues", "locations", "tournamentTemplates")):
        raise ValueError("Fresh setup contains prepopulated people or places")
    if data.get("selectedPlayerID") is not None: raise ValueError("Fresh installation has a selected player")
    for key in ("knownVenues", "achievementHistory", "achievementRecords"):
        if data.get(key, []) != []: raise ValueError("Fresh installation contains unexpected " + key)


def check_watch_preferences(preferences):
    for key in ("activeHealthTrainingID", "pendingHealthTrainingIDs", "activeTournamentID", "pendingIntentRoute"):
        if preferences.get(key): raise ValueError("Fresh Watch contains previous activity state")
    if preferences.get("queuedWatchCommands"):
        queue = json.loads(preferences["queuedWatchCommands"])
        commands = queue.get("commands")
        # A new, unpaired Watch may queue a data-free request for its first phone snapshot.
        if not isinstance(commands, list) or any(command != {"requestSnapshot": {}} for command in commands) or queue.get("libraryID") is not None:
            raise ValueError("Fresh Watch contains another library's queued commands")


def compatible_simulator(inventory, platform):
    runtimes = [r for r in inventory["runtimes"] if r.get("isAvailable") and platform in r["identifier"]]
    types = [t for t in inventory["devicetypes"] if (t["name"].startswith("iPhone") if platform == "iOS" else "Apple Watch Ultra" in t["name"])]
    for runtime in sorted(runtimes, key=lambda r: tuple(int(x) for x in r["version"].split(".")), reverse=True):
        for device in inventory.get("devices", {}).get(runtime["identifier"], []):
            if not device.get("isAvailable"):
                continue
            for device_type in types:
                if device.get("deviceTypeIdentifier", device.get("name")) == device_type["identifier"] or (
                    not device.get("deviceTypeIdentifier") and device.get("name") == device_type["name"]
                ):
                    return device_type["identifier"], runtime["identifier"]
    raise ValueError("No available compatible " + platform + " simulator model/runtime pair")


def main(app, platform):
    inventory = json.loads(run("list", "--json"))
    device_type, runtime = compatible_simulator(inventory, platform)
    identifier = "com.inclusophy.tennistracker" + (".watchkitapp" if platform == "watchOS" else "")
    reports = []
    for index in range(2):
        device = run("create", "TennisPrivacy-" + str(uuid.uuid4()), device_type, runtime)
        try:
            run("bootstatus", device, "-b")
            run("install", device, app)
            # Release must ignore all fixture/reset arguments.
            run("launch", device, identifier, "-ui-testing-reset-store", "-ui-testing-venue-dashboard", "-ui-testing-watch")
            container = Path(run("get_app_container", device, identifier, "data"))
            path = container / ("Library/Preferences/" + identifier + ".plist" if platform == "watchOS" else "Library/Application Support/TennisTracker/tennis-tracker-data.json")
            data = None
            for _ in range(30):
                try:
                    raw = path.read_bytes()
                    if platform == "watchOS":
                        preferences = plistlib.loads(raw)
                        data = json.loads(preferences["watchSnapshot"])
                    else:
                        data = json.loads(raw)
                    break
                except (FileNotFoundError, KeyError, ValueError): time.sleep(1)
            if data is None: raise ValueError("Fresh application did not persist its initial state")
            check_empty(data)
            if platform == "watchOS": check_watch_preferences(preferences)
            if platform == "iOS" and data.get("onboardingCompleted") is not False:
                raise ValueError("Fresh iPhone did not enter onboarding")
            if platform == "watchOS" and data.get("achievementHistory") != []:
                raise ValueError("Fresh Watch contains achievement history")
            if platform == "iOS": uuid.UUID(data["libraryID"])
            reports.append({"container": index + 1, "empty": True, "libraryID": data.get("libraryID")})
        finally:
            subprocess.run(["xcrun", "simctl", "shutdown", device], check=False, capture_output=True)
            run("delete", device)
    if platform == "iOS" and (not reports[0]["libraryID"] or reports[0]["libraryID"] == reports[1]["libraryID"]):
        raise ValueError("Independent installations must have distinct library identities")
    print(json.dumps({"platform": platform, "fresh_installations": reports}, indent=2))


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--app", required=True, type=Path)
    parser.add_argument("--platform", required=True, choices=["iOS", "watchOS"])
    args = parser.parse_args()
    main(args.app.resolve(), args.platform)
