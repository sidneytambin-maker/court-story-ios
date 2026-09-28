import unittest
from deployment_preflight import permits, validate_architecture


class DeploymentPreflightTests(unittest.TestCase):
    def setUp(self):
        self.phone = "Payload/TennisTracker.app/"
        self.watch = self.phone + "Watch/TennisTrackerWatchApp.app/"
        self.infos = {self.phone: {"CFBundleIdentifier": "test.phone"},
                      self.watch: {"CFBundleIdentifier": "test.phone.watch", "WKCompanionAppBundleIdentifier": "test.phone", "WKApplication": True}}

    def testWorkingLocationIsAccepted(self):
        self.assertEqual(validate_architecture(self.infos), (self.phone, self.watch))

    def testMovingWatchToPluginsIsRejected(self):
        self.infos[self.watch.replace("/Watch/", "/PlugIns/")] = self.infos.pop(self.watch)
        with self.assertRaises(ValueError):
            validate_architecture(self.infos)

    def testLegacyMixedWatchMetadataIsRejected(self):
        self.infos[self.watch]["WKWatchKitApp"] = True
        with self.assertRaises(ValueError):
            validate_architecture(self.infos)

    def testWidgetNeedsSeparateStageAndStaysInsideWatch(self):
        self.infos[self.watch]["TennisSharedAppGroup"] = "group.tennis"
        self.infos[self.watch + "PlugIns/Tennis.appex/"] = {
            "CFBundleIdentifier": "test.phone.watch.widgets", "TennisSharedAppGroup": "group.tennis",
            "NSExtension": {"NSExtensionPointIdentifier": "com.apple.widgetkit-extension"}}
        with self.assertRaises(ValueError):
            validate_architecture(self.infos)
        self.assertEqual(validate_architecture(self.infos, allow_widgets=True), (self.phone, self.watch))

    def testWidgetWithUnrelatedContainerIsRejected(self):
        self.infos[self.watch]["TennisSharedAppGroup"] = "group.tennis"
        self.infos[self.watch + "PlugIns/Tennis.appex/"] = {
            "CFBundleIdentifier": "test.phone.watch.widgets", "TennisSharedAppGroup": "group.other",
            "NSExtension": {"NSExtensionPointIdentifier": "com.apple.widgetkit-extension"}}
        with self.assertRaises(ValueError):
            validate_architecture(self.infos, allow_widgets=True)

    def testProfileMustGrantEveryRequestedGroupAndHealth(self):
        self.assertTrue(permits(["group.tennis"], ["group.tennis"]))
        self.assertFalse(permits(["group.tennis"], ["group.tennis", "group.other"]))
        self.assertFalse(permits(None, True))
        self.assertTrue(permits(True, True))
        self.assertTrue(permits("TEAM.*", "TEAM.app"))
        self.assertFalse(permits("TEAM.app", "OTHER.app"))


if __name__ == "__main__":
    unittest.main()
