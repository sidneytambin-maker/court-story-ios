import io
import hashlib
from pathlib import Path
import plistlib
import unittest
import zipfile
from verify_app_icons import compiled_icons, source_icons


class AppIconTests(unittest.TestCase):
    def archive(self, missing=""):
        raw = io.BytesIO()
        with zipfile.ZipFile(raw, "w") as archive:
            for root in ("Payload/TennisTracker.app/", "Payload/TennisTracker.app/Watch/TennisTrackerWatchApp.app/"):
                info = {"CFBundleIcons": {"CFBundlePrimaryIcon": {"CFBundleIconName": "AppIcon"}}}
                if missing == root + "metadata": info = {}
                archive.writestr(root + "Info.plist", plistlib.dumps(info))
                names = ["Assets.car"] if "/Watch/" in root else ["AppIcon60x60@2x.png", "Assets.car"]
                for name in names:
                    if missing != root + name: archive.writestr(root + name, b"compiled-test-fixture")
        return zipfile.ZipFile(raw)

    def evidence(self):
        return {component: {"assets_sha256": hashlib.sha256(b"compiled-test-fixture").hexdigest(),
                            "icon_renditions": [{"AssetType": "Icon Image", "Name": "AppIcon",
                            "Idiom": idiom, "Opaque": True, "PixelWidth": 1024, "PixelHeight": 1024,
                            "ColorModel": "RGB", "Colorspace": "srgb"}]}
                for component, idiom in (("iPhone", "phone"), ("Watch", "watch"))}

    def testBothSourceIconsHaveCorrectSizeFormatAndMatchingBrand(self):
        source_icons(Path(__file__).resolve().parents[1])

    def testCompiledPhoneAndWatchIconsAreRequired(self):
        with self.archive() as archive:
            result = compiled_icons(archive, self.evidence())
            self.assertEqual(len(result["components"]), 2)
            self.assertEqual(result["components"][1]["compiled_pngs"], [])

    def testMissingWatchArtworkFails(self):
        with self.archive("Payload/TennisTracker.app/Watch/TennisTrackerWatchApp.app/Assets.car") as archive:
            with self.assertRaises(ValueError): compiled_icons(archive, self.evidence())

    def testMissingPhoneMetadataFails(self):
        with self.archive("Payload/TennisTracker.app/metadata") as archive:
            with self.assertRaises(ValueError): compiled_icons(archive, self.evidence())

    def testMissingCompiledAssetCatalogueFails(self):
        with self.archive("Payload/TennisTracker.app/Assets.car") as archive:
            with self.assertRaises(ValueError): compiled_icons(archive, self.evidence())

    def testChangedCatalogueDoesNotReuseEvidence(self):
        proof = self.evidence(); proof["Watch"]["assets_sha256"] = "different"
        with self.archive() as archive:
            with self.assertRaises(ValueError): compiled_icons(archive, proof)

    def testMissingNativeEvidenceFails(self):
        with self.archive() as archive:
            with self.assertRaises(ValueError): compiled_icons(archive, {})

    def testTransparentIconFails(self):
        proof = self.evidence(); proof["Watch"]["icon_renditions"][0]["Opaque"] = False
        with self.archive() as archive:
            with self.assertRaises(ValueError): compiled_icons(archive, proof)

    def testWrongRenditionPlatformFails(self):
        proof = self.evidence(); proof["Watch"]["icon_renditions"][0]["Idiom"] = "phone"
        with self.archive() as archive:
            with self.assertRaises(ValueError): compiled_icons(archive, proof)

    def testWrongIconNameFails(self):
        proof = self.evidence(); proof["Watch"]["icon_renditions"][0]["Name"] = "Other"
        with self.archive() as archive:
            with self.assertRaises(ValueError): compiled_icons(archive, proof)


if __name__ == "__main__": unittest.main()
