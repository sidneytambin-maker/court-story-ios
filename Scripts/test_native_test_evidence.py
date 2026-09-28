import unittest
from verify_native_test_evidence import REQUIRED, validate


class NativeEvidenceTests(unittest.TestCase):
    def run_data(self):
        return {"status": "completed", "workflowName": "iOS free development build", "headSha": "tested",
                "jobs": [{"name": "Build unsigned iOS IPA", "steps": [
                    {"name": name, "conclusion": "success"} for name in REQUIRED | {"Compile Watch complication"}]}]}

    def testPackagingOnlyChangesReusePassingTests(self):
        self.assertTrue(validate(self.run_data(), ["Scripts/verify_app_icons.py"], "widgets")["native_tests_reused"])

    def testAppChangesRequireNewNativeTests(self):
        with self.assertRaises(ValueError): validate(self.run_data(), ["TennisTrackerWatchApp/WatchRootView.swift"], "widgets")

    def testIconChangesRequireNewNativeTests(self):
        with self.assertRaises(ValueError): validate(self.run_data(), ["TennisTracker/Assets.xcassets/AppIcon.appiconset/AppIcon.png"], "widgets")

    def testRunningEvidenceRejected(self):
        run = self.run_data(); run["status"] = "in_progress"
        with self.assertRaises(ValueError): validate(run, [], "widgets")

    def testFailedNativeStepRejected(self):
        run = self.run_data(); run["jobs"][0]["steps"][0]["conclusion"] = "failure"
        with self.assertRaises(ValueError): validate(run, [], "widgets")

    def testMissingNativeStepRejected(self):
        run = self.run_data(); run["jobs"][0]["steps"] = []
        with self.assertRaises(ValueError): validate(run, [], "widgets")


if __name__ == "__main__": unittest.main()
