"""Validate source artwork and the actual compiled icons in both app bundles."""
import argparse
import hashlib
import json
from pathlib import Path
import plistlib
import struct
import subprocess
import tempfile
import zipfile

COMPONENTS = (("iPhone", "Payload/TennisTracker.app/", "phone"),
              ("Watch", "Payload/TennisTracker.app/Watch/TennisTrackerWatchApp.app/", "watch"))


def source_icons(root):
    identity = json.loads((root / "Branding/AppIcon-identity.json").read_bytes())
    if identity.get("appName") != "Court Story" or identity.get("spokenName") != "Court Story" or identity.get("visualMonogram") != "CS":
        raise ValueError("The icon identity must retain the full spoken Court Story name")
    images = []
    for target, platform in (("TennisTracker", "ios"), ("TennisTrackerWatchApp", "watchos")):
        folder = root / target / "Assets.xcassets/AppIcon.appiconset"
        contents = json.loads((folder / "Contents.json").read_bytes())
        entry, = contents["images"]
        if (entry["idiom"], entry["platform"], entry["size"]) != ("universal", platform, "1024x1024"):
            raise ValueError("Incorrect single-size app icon catalogue")
        raw = (folder / entry["filename"]).read_bytes()
        if hashlib.sha256(raw).hexdigest() != identity.get("sha256"):
            raise ValueError("App icon is not the reviewed Court Story CS artwork")
        if raw[:8] != b"\x89PNG\r\n\x1a\n" or raw[12:16] != b"IHDR":
            raise ValueError("App icon must be PNG")
        width, height, depth, colour = struct.unpack(">IIBB", raw[16:26])
        if (width, height, depth, colour) != (1024, 1024, 8, 2):
            raise ValueError("App icon must be opaque 1024-square 8-bit RGB artwork")
        images.append(raw)
    if images[0] != images[1]:
        raise ValueError("iPhone and Watch must share the same brand artwork")


def native_catalogues(archive):
    evidence = {}
    with tempfile.TemporaryDirectory() as directory:
        for component, root, _ in COMPONENTS:
            raw = archive.read(root + "Assets.car")
            path = Path(directory) / (component + ".car")
            path.write_bytes(raw)
            rows = json.loads(subprocess.check_output(["xcrun", "assetutil", "--info", str(path)]))
            evidence[component] = {"assets_sha256": hashlib.sha256(raw).hexdigest(), "icon_renditions": rows}
    return evidence


def compiled_icons(archive, evidence):
    results = []
    for component, root, idiom in COMPONENTS:
        info = plistlib.loads(archive.read(root + "Info.plist"))
        primary = info.get("CFBundleIcons", {}).get("CFBundlePrimaryIcon", {})
        name = primary.get("CFBundleIconName", info.get("CFBundleIconName"))
        if name != "AppIcon":
            raise ValueError(component + " has no compiled primary AppIcon metadata")
        files = [n.removeprefix(root) for n in archive.namelist() if n.startswith(root)
                 and "/" not in n.removeprefix(root) and n.removeprefix(root).startswith("AppIcon") and n.endswith(".png")]
        if (component == "iPhone" and not files) or root + "Assets.car" not in archive.namelist():
            raise ValueError(component + " is missing its compiled app icon images")
        proof = evidence.get(component, {})
        digest = hashlib.sha256(archive.read(root + "Assets.car")).hexdigest()
        if proof.get("assets_sha256") != digest:
            raise ValueError(component + " catalogue is not the one inspected by Apple's native tool")
        renditions = [row for row in proof.get("icon_renditions", [])
                      if row.get("AssetType") == "Icon Image" and row.get("Name") == name]
        if not any(row.get("Idiom") == idiom and row.get("Opaque") is True
                   and row.get("PixelWidth") == 1024 and row.get("PixelHeight") == 1024
                   and row.get("ColorModel") == "RGB" and row.get("Colorspace") == "srgb"
                   for row in renditions):
            raise ValueError(component + " has no opaque full-size native sRGB app icon rendition")
        results.append({"component": component, "primary_icon": name, "compiled_pngs": sorted(files),
                        "assets_sha256": digest, "icon_renditions": renditions})
    return {"app_icons_verified": True, "components": results}


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--ipa", type=Path)
    mode = parser.add_mutually_exclusive_group()
    mode.add_argument("--native", action="store_true")
    mode.add_argument("--evidence", type=Path)
    args = parser.parse_args()
    source_icons(Path(__file__).resolve().parents[1])
    if args.ipa:
        with zipfile.ZipFile(args.ipa) as archive:
            if args.native:
                proof = native_catalogues(archive)
            elif args.evidence:
                proof = {row["component"]: row for row in json.loads(args.evidence.read_bytes())["components"]}
            else:
                parser.error("IPA checks require --native or the native --evidence report")
            print(json.dumps(compiled_icons(archive, proof), indent=2))
