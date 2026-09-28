import copy
import unittest

from verify_testflight_recovery import ALLOWED_REPAIR_FILES, BRANCH, verify_evidence


class RecoveryEvidenceTests(unittest.TestCase):
    def setUp(self):
        self.evidence = {"headBranch": BRANCH, "workflowName": "TestFlight beta validation",
            "jobs": [{"name": name, "conclusion": "success"} for name in ("iphone-tests", "watch-tests", "release-privacy")]}

    def test_signing_tool_only_repair_reuses_identical_native_product(self):
        verify_evidence(self.evidence, ALLOWED_REPAIR_FILES)

    def test_any_application_resource_or_project_change_requires_full_tests(self):
        for name in ("Shared/TennisStore.swift", "project-testflight.yml", "TennisTracker/Assets.xcassets/icon.png",
                     ".github/workflows/testflight-beta.yml", "Scripts/check_fresh_release.py", "Scripts/verify_testflight_release.py"):
            with self.subTest(path=name), self.assertRaises(ValueError):
                verify_evidence(self.evidence, [name])

    def test_failed_missing_or_cancelled_native_gate_rejected(self):
        for conclusion in ("failure", "cancelled", "", "skipped"):
            evidence = copy.deepcopy(self.evidence)
            evidence["jobs"][0]["conclusion"] = conclusion
            with self.subTest(conclusion=conclusion), self.assertRaises(ValueError):
                verify_evidence(evidence, [])
        with self.assertRaises(ValueError):
            verify_evidence({**self.evidence, "jobs": []}, [])

    def test_other_workflow_or_branch_rejected(self):
        for field in ("headBranch", "workflowName"):
            with self.subTest(field=field), self.assertRaises(ValueError):
                verify_evidence({**self.evidence, field: "other"}, [])


if __name__ == "__main__":
    unittest.main()
