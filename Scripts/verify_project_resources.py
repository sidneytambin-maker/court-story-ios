"""Reject configuration files accidentally copied as Xcode bundle resources."""
import argparse
import json
from pathlib import PurePosixPath
import subprocess


def verify(project):
    objects = project["objects"]
    checked = 0
    for phase in objects.values():
        if phase.get("isa") != "PBXResourcesBuildPhase":
            continue
        for identifier in phase.get("files", []):
            resource = objects[objects[identifier]["fileRef"]]
            name = PurePosixPath(resource.get("path", resource.get("name", ""))).name.lower()
            if name == "info.plist" or name.endswith(("-info.plist", ".entitlements")):
                raise ValueError("Configuration file incorrectly copied as a resource: " + name)
            checked += 1
    return {"configuration_resources_absent": True, "resource_entries_checked": checked}


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--project", default="TennisTrackeriOS.xcodeproj/project.pbxproj")
    args = parser.parse_args()
    project = json.loads(subprocess.check_output(["plutil", "-convert", "json", "-o", "-", args.project]))
    print(json.dumps(verify(project), indent=2))
