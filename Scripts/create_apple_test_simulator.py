"""Create an isolated simulator compatible with the selected Xcode SDK."""
import argparse
import json
import subprocess
import sys


def run(*args):
    return subprocess.check_output(args, text=True).strip()


def version(text):
    parts = [int(part) for part in text.split(".") if part.isdigit()]
    return tuple((parts + [0, 0, 0])[:3])


def select_runtime(runtimes, platform, sdk):
    supported = [item for item in runtimes if item.get("isAvailable")
                 and f".{platform}-" in item["identifier"]
                 and version(item["version"])[:1] == version(sdk)[:1]
                 and version(item["version"])[:2] <= version(sdk)[:2]]
    if not supported:
        raise RuntimeError(f"No available {platform} runtime compatible with SDK {sdk}")
    return max(supported, key=lambda item: version(item["version"]))


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("kind", choices=["phone", "small-phone", "watch", "small-watch"])
    args = parser.parse_args()
    watch = "watch" in args.kind
    sdk = run("xcrun", "--sdk", "watchsimulator" if watch else "iphonesimulator", "--show-sdk-version")
    runtimes = json.loads(run("xcrun", "simctl", "list", "runtimes", "--json"))["runtimes"]
    runtime = select_runtime(runtimes, "watchOS" if watch else "iOS", sdk)
    types = json.loads(run("xcrun", "simctl", "list", "devicetypes", "--json"))["devicetypes"]
    devices = [item for item in types if item["name"].startswith("Apple Watch" if watch else "iPhone")
               and version(item.get("minRuntimeVersionString", "0")) <= version(runtime["version"])
               and version(item.get("maxRuntimeVersionString", "65535")) >= version(runtime["version"])]
    if args.kind == "small-phone":
        preferred = [item for item in devices if "SE (3rd generation)" in item["name"]]
        if not preferred:
            preferred = [item for item in devices if "mini" in item["name"]]
        if not preferred:
            preferred = [item for item in devices if "Pro Max" not in item["name"] and "Plus" not in item["name"]]
    elif args.kind == "small-watch":
        preferred = [item for item in devices if any(size in item["name"] for size in ["40mm", "41mm", "42mm"])]
    elif watch:
        preferred = [item for item in devices if "Ultra" in item["name"]]
    else:
        preferred = [item for item in devices if "Pro" in item["name"]]
    if not preferred:
        raise RuntimeError(f"No supported simulator model for {args.kind}")
    device = preferred[-1]
    print(json.dumps({"xcode": run("xcodebuild", "-version"), "sdk": sdk,
                      "runtime": runtime["identifier"], "device": device["name"]}), file=sys.stderr)
    print(run("xcrun", "simctl", "create", "Court-" + args.kind, device["identifier"], runtime["identifier"]))


if __name__ == "__main__":
    main()
