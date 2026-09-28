import json
import plistlib
import tempfile
import unittest
from pathlib import Path
from verify_testflight_release import verify, PHONE_ID, GROUP_ID, APP_NAME, BUILD


class ReleasePrivacyTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.app = Path(self.temp.name) / "Phone.app"
        self.watch = self.app / "Watch" / "Watch.app"
        self.widget = self.watch / "PlugIns" / "Widget.appex"
        for path, bundle in ((self.app, PHONE_ID), (self.watch, PHONE_ID + ".watchkitapp"), (self.widget, PHONE_ID + ".watchkitapp.widgets")):
            path.mkdir(parents=True, exist_ok=True)
            info = {"CFBundleIdentifier": bundle, "CFBundleExecutable": "Main", "CFBundleShortVersionString": "0.1.0", "CFBundleVersion": BUILD, "CFBundleDisplayName": APP_NAME, "CFBundleName": APP_NAME, "TennisSharedAppGroup": GROUP_ID,
                    "WKCompanionAppBundleIdentifier": PHONE_ID, "WKApplication": True, "UIFileSharingEnabled": True, "LSSupportsOpeningDocumentsInPlace": True,
                    "NSExtension": {"NSExtensionPointIdentifier": "com.apple.widgetkit-extension"}}
            if path == self.app:
                info["UIDeviceFamily"] = [1, 2]
                info["UISupportedInterfaceOrientations"] = ["UIInterfaceOrientationPortrait", "UIInterfaceOrientationLandscapeLeft", "UIInterfaceOrientationLandscapeRight"]
                info["UISupportedInterfaceOrientations~ipad"] = info["UISupportedInterfaceOrientations"] + ["UIInterfaceOrientationPortraitUpsideDown"]
            (path / "Info.plist").write_bytes(plistlib.dumps(info))
            (path / "PrivacyInfo.xcprivacy").write_bytes(plistlib.dumps({"NSPrivacyTracking": False, "NSPrivacyCollectedDataTypes": []}))
            (path / "Main").write_bytes(b"compiled-test-placeholder")

    def test_clean_structure_passes(self):
        self.assertEqual(len(verify(self.app)["components"]), 3)

    def test_full_spoken_name_is_required_on_every_component(self):
        for bundle in (self.app, self.watch, self.widget):
            path = bundle / "Info.plist"
            original = plistlib.loads(path.read_bytes())
            for key in ("CFBundleDisplayName", "CFBundleName"):
                for old_name in ("CS", "Tennis Tracker", ""):
                    info = dict(original, **{key: old_name})
                    path.write_bytes(plistlib.dumps(info))
                    with self.subTest(bundle=bundle.name, key=key, name=old_name), self.assertRaisesRegex(ValueError, "full Court Story"):
                        verify(self.app)
            path.write_bytes(plistlib.dumps(original))

    def test_old_spoken_strings_and_company_branding_block_release(self):
        for name in (b"Tennis Tracker", b"Inclusophy"):
            (self.watch / "Main").write_bytes(b"compiled " + name + b" ready")
            with self.subTest(name=name), self.assertRaisesRegex(ValueError, "Old public branding"):
                verify(self.app)

    def test_old_permission_wording_blocks_release(self):
        path = self.app / "Info.plist"
        info = plistlib.loads(path.read_bytes())
        info["NSCalendarsFullAccessUsageDescription"] = "Tennis Tracker adds your events."
        path.write_bytes(plistlib.dumps(info))
        with self.assertRaisesRegex(ValueError, "permission descriptions"):
            verify(self.app)

    def test_private_database_blocks_release(self):
        (self.watch / "tennis-tracker-data.json").write_text("{}")
        with self.assertRaises(ValueError): verify(self.app)

    def test_missing_orientations_are_rejected_before_apple_upload(self):
        path = self.app / "Info.plist"
        info = plistlib.loads(path.read_bytes())
        del info["UISupportedInterfaceOrientations"]
        path.write_bytes(plistlib.dumps(info))
        with self.assertRaisesRegex(ValueError, "orientations"):
            verify(self.app)

    def test_partial_ipad_orientations_are_rejected_before_apple_upload(self):
        path = self.app / "Info.plist"
        info = plistlib.loads(path.read_bytes())
        info["UISupportedInterfaceOrientations~ipad"].remove("UIInterfaceOrientationPortraitUpsideDown")
        path.write_bytes(plistlib.dumps(info))
        with self.assertRaisesRegex(ValueError, "all four"):
            verify(self.app)

    def test_xcode_app_intents_version_metadata_is_allowed(self):
        for bundle in (self.app, self.watch, self.widget):
            folder = bundle / "Metadata.appintents"
            folder.mkdir()
            (folder / "version.json").write_text(json.dumps({"toolsVersion": "17F113", "version": "3.0"}))
        self.assertEqual(len(verify(self.app)["components"]), 3)

    def test_app_intents_exception_does_not_allow_personal_fields(self):
        folder = self.app / "Metadata.appintents"
        folder.mkdir()
        for metadata in ({"toolsVersion": "17F113", "version": "3.0", "players": []},
                         {"toolsVersion": "Player Name", "version": "3.0"},
                         {"toolsVersion": "17F113", "version": "private notes"},
                         {"toolsVersion": 17, "version": "3.0"}):
            (folder / "version.json").write_text(json.dumps(metadata))
            with self.subTest(metadata=metadata), self.assertRaises(ValueError): verify(self.app)

    def test_version_json_outside_the_known_metadata_location_is_rejected(self):
        folder = self.app / "Unreviewed" / "Metadata.appintents"
        folder.mkdir(parents=True)
        (folder / "version.json").write_text(json.dumps({"toolsVersion": "17F113", "version": "3.0"}))
        with self.assertRaises(ValueError): verify(self.app)

    def test_test_hooks_block_release(self):
        (self.app / "Main").write_bytes(b"-ui-testing-reset-store")
        with self.assertRaises(ValueError): verify(self.app)

    def test_temporary_identifier_blocks_release(self):
        path = self.watch / "Info.plist"
        info = plistlib.loads(path.read_bytes()); info["CFBundleIdentifier"] += ".dev"
        path.write_bytes(plistlib.dumps(info))
        with self.assertRaises(ValueError): verify(self.app)

    def test_wrong_watch_location_blocks_release(self):
        (self.app / "PlugIns").mkdir()
        self.watch.rename(self.app / "PlugIns" / "Watch.app")
        with self.assertRaises(ValueError): verify(self.app)

    def test_missing_complication_blocks_release(self):
        (self.widget / "Info.plist").unlink()
        with self.assertRaises(FileNotFoundError): verify(self.app)

    def test_missing_private_restore_route_blocks_release(self):
        path = self.app / "Info.plist"
        info = plistlib.loads(path.read_bytes()); info["UIFileSharingEnabled"] = False
        path.write_bytes(plistlib.dumps(info))
        with self.assertRaises(ValueError): verify(self.app)


if __name__ == "__main__": unittest.main()
