import unittest

from verify_project_resources import verify


class ProjectResourceTests(unittest.TestCase):
    def project(self, path, phase="PBXResourcesBuildPhase"):
        return {"objects": {
            "phase": {"isa": phase, "files": ["entry"]},
            "entry": {"isa": "PBXBuildFile", "fileRef": "file"},
            "file": {"isa": "PBXFileReference", "path": path},
        }}

    def test_old_or_generated_info_is_not_a_resource(self):
        for path in ("Info.plist", "TennisTracker/Info.plist", "Distribution/Generated/Watch-Info.plist"):
            with self.subTest(path=path), self.assertRaises(ValueError):
                verify(self.project(path))

    def test_entitlements_are_not_resources(self):
        with self.assertRaises(ValueError):
            verify(self.project("Watch/HealthAndWidgets.entitlements"))

    def test_actual_resources_remain_allowed(self):
        for path in ("PrivacyInfo.xcprivacy", "Assets.xcassets", "tennis-bounce.wav"):
            self.assertEqual(verify(self.project(path))["resource_entries_checked"], 1)

    def test_configuration_reference_outside_resources_is_allowed(self):
        self.assertTrue(verify(self.project("Info.plist", "PBXGroup"))["configuration_resources_absent"])


if __name__ == "__main__":
    unittest.main()
