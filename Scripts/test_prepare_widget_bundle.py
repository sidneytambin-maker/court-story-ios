import copy
import unittest
from prepare_widget_bundle import prepare_metadata


class WidgetSigningTests(unittest.TestCase):
    def setUp(self):
        self.watch = {"CFBundleVersion": "23", "TennisHealthEnabled": True, "WKApplication": True}
        self.widget = {"CFBundleVersion": "23", "NSExtension": {"NSExtensionPointIdentifier": "com.apple.widgetkit-extension"}}
        self.watch_profile = {"TeamIdentifier": ["TEAM"], "Entitlements": {"application-identifier": "TEAM.app.watch", "com.apple.developer.healthkit": True, "com.apple.security.application-groups": ["group.tennis"]}}
        self.widget_profile = copy.deepcopy(self.watch_profile)
        self.widget_profile["Entitlements"]["application-identifier"] = "TEAM.app.watch.widgets"

    def prepare(self, group="group.tennis"):
        return prepare_metadata(self.watch, self.widget, self.watch_profile, self.widget_profile, "app.watch", "app.watch.widgets", group)

    def testAuthorizedMetadataIsPreparedWithoutMutatingOriginals(self):
        watch, widget = self.prepare()
        self.assertTrue(watch["WKApplication"])
        self.assertTrue(watch["TennisHealthEnabled"])
        self.assertEqual(widget["CFBundleIdentifier"], "app.watch.widgets")
        self.assertEqual(watch["TennisSharedAppGroup"], widget["TennisSharedAppGroup"])
        self.assertNotIn("TennisSharedAppGroup", self.watch)

    def testMissingContainerPermissionIsRejected(self):
        self.widget_profile["Entitlements"].pop("com.apple.security.application-groups")
        with self.assertRaises(ValueError): self.prepare()

    def testWrongExtensionIdentityIsRejected(self):
        self.widget_profile["Entitlements"]["application-identifier"] = "TEAM.app.other"
        with self.assertRaises(ValueError): self.prepare()

    def testLosingHealthPermissionIsRejected(self):
        self.watch_profile["Entitlements"].pop("com.apple.developer.healthkit")
        with self.assertRaises(ValueError): self.prepare()

    def testMismatchedVersionsOrPreviewGroupAreRejected(self):
        self.widget["CFBundleVersion"] = "22"
        with self.assertRaises(ValueError): self.prepare()
        self.widget["CFBundleVersion"] = "23"
        with self.assertRaises(ValueError): self.prepare(group="group.tennis.preview")


if __name__ == "__main__":
    unittest.main()
