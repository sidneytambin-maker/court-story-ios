import re
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]


class CourtStoryBrandingTests(unittest.TestCase):
    def test_no_retired_visible_name_or_company_attribution_is_shipped(self):
        paths = [ROOT / name for name in ("project.yml", "project-tests.yml", "project-health.yml", "project-widgets.yml", "project-testflight.yml", "docs/privacy.html")]
        for folder in ("TennisTracker", "TennisTrackerShared", "TennisTrackerWatchApp", "TennisTrackerWatchWidgets"):
            paths.extend((ROOT / folder).rglob("*.swift"))
        for path in paths:
            with self.subTest(path=str(path.relative_to(ROOT))):
                self.assertNotRegex(path.read_text(encoding="utf-8"), r"Tennis Tracker|Inclusophy|Tennis-Tracker-Private-Backup")

    def test_all_home_screen_names_are_spoken_in_full(self):
        for name, components in (("project.yml", 2), ("project-tests.yml", 1), ("project-widgets.yml", 1)):
            text = (ROOT / name).read_text()
            for key in ("CFBundleDisplayName", "CFBundleName"):
                self.assertEqual(re.findall(key + r": (.+)", text), ["Court Story"] * components)

    def test_existing_library_and_widget_identities_are_not_renamed(self):
        store = (ROOT / "TennisTracker/Store/TennisStore.swift").read_text()
        self.assertIn('.appendingPathComponent("TennisTracker", isDirectory: true)', store)
        self.assertIn('directory.appendingPathComponent("tennis-tracker-data.json")', store)
        spec = (ROOT / "project-testflight.yml").read_text()
        for suffix in ("", ".watchkitapp", ".watchkitapp.widgets"):
            self.assertIn("PRODUCT_BUNDLE_IDENTIFIER: com.inclusophy.tennistracker" + suffix + "\n", spec)
        self.assertIn("TENNIS_APP_GROUP: group.com.inclusophy.tennistracker", spec)
        kinds = (ROOT / "TennisTrackerShared/TennisGlanceKind.swift").read_text()
        self.assertIn('return "TennisTrackerComplication"', kinds)


if __name__ == "__main__":
    unittest.main()
