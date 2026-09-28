import copy
import contextlib
import datetime as dt
import io
from pathlib import Path
import subprocess
import unittest
from unittest.mock import patch

from verify_testflight_signing import GROUP_ID, PHONE_ID, TEAM_ID, allowed_value, check_profile, command, extract_signing_certificate


class TestFlightSigningTests(unittest.TestCase):
    def setUp(self):
        self.identifier = PHONE_ID + ".watchkitapp"
        self.entitlements = {
            "application-identifier": TEAM_ID + "." + self.identifier,
            "com.apple.developer.team-identifier": TEAM_ID,
            "get-task-allow": False,
            "com.apple.security.application-groups": [GROUP_ID],
            "com.apple.developer.healthkit": True,
            "keychain-access-groups": [TEAM_ID + "." + self.identifier],
        }
        self.profile = {
            "ExpirationDate": dt.datetime(2030, 1, 1),
            "TeamIdentifier": [TEAM_ID],
            "Entitlements": copy.deepcopy(self.entitlements),
            "DeveloperCertificates": [b"test-certificate"],
        }
        self.profile["Entitlements"]["keychain-access-groups"] = [TEAM_ID + ".*"]

    def verify(self):
        return check_profile(self.profile, self.entitlements, self.identifier, b"test-certificate", dt.datetime(2026, 9, 10, tzinfo=dt.timezone.utc))

    def test_app_store_watch_profile_with_required_capabilities_passes(self):
        self.assertEqual(self.verify()["profile_type"], "app-store")

    def test_development_or_ad_hoc_profile_is_rejected(self):
        self.profile["ProvisionedDevices"] = ["test-device"]
        with self.assertRaises(ValueError): self.verify()

    def test_enterprise_profile_is_rejected(self):
        self.profile["ProvisionsAllDevices"] = True
        with self.assertRaises(ValueError): self.verify()

    def test_expired_profile_is_rejected(self):
        self.profile["ExpirationDate"] = dt.datetime(2025, 1, 1)
        with self.assertRaises(ValueError): self.verify()

    def test_wrong_team_is_rejected(self):
        self.profile["TeamIdentifier"] = ["WRONGTEAM0"]
        with self.assertRaises(ValueError): self.verify()

    def test_wrong_signing_certificate_is_rejected(self):
        self.profile["DeveloperCertificates"] = [b"another-certificate"]
        with self.assertRaises(ValueError): self.verify()

    def test_debuggable_signature_is_rejected(self):
        self.entitlements["get-task-allow"] = True
        with self.assertRaises(ValueError): self.verify()

    def test_wrong_bundle_identity_is_rejected(self):
        self.entitlements["application-identifier"] += ".dev"
        with self.assertRaises(ValueError): self.verify()

    def test_missing_health_grant_is_rejected(self):
        self.profile["Entitlements"].pop("com.apple.developer.healthkit")
        with self.assertRaises(ValueError): self.verify()

    def test_missing_health_claim_is_rejected(self):
        self.entitlements.pop("com.apple.developer.healthkit")
        with self.assertRaises(ValueError): self.verify()

    def test_preview_app_group_is_rejected_even_if_authorized(self):
        self.entitlements["com.apple.security.application-groups"] = [GROUP_ID + ".preview"]
        self.profile["Entitlements"]["com.apple.security.application-groups"] = [GROUP_ID + ".preview"]
        with self.assertRaises(ValueError): self.verify()

    def test_entitlement_matching_keeps_types_and_checks_every_array_item(self):
        self.assertFalse(allowed_value(True, 1))
        self.assertFalse(allowed_value([TEAM_ID + ".app", "OTHER.app"], [TEAM_ID + ".*"]))
        self.assertTrue(allowed_value([TEAM_ID + ".app"], [TEAM_ID + ".*"]))

    def test_certificate_prefix_is_an_option_value_not_a_bundle_operand(self):
        def native(stage, *args):
            self.assertEqual(args[:2], ("codesign", "-d"))
            self.assertTrue(args[2].startswith("--extract-certificates="))
            self.assertEqual(args[3:], ("Example.app",))
            Path(args[2].split("=", 1)[1] + "0").write_bytes(b"actual-leaf-certificate")
            return b""
        with patch("verify_testflight_signing.command", side_effect=native):
            self.assertEqual(extract_signing_certificate("Example.app"), b"actual-leaf-certificate")

    def test_command_failure_identifies_stage_without_private_native_output(self):
        result = subprocess.CompletedProcess([], 1, stdout=b"private account", stderr=b"private profile")
        output = io.StringIO()
        with patch("verify_testflight_signing.subprocess.run", return_value=result), contextlib.redirect_stdout(output):
            with self.assertRaisesRegex(ValueError, "Inspect component") as failure:
                command("Inspect component", "codesign", "-d", "private-path")
        exposed = output.getvalue() + str(failure.exception)
        for value in ("private account", "private profile", "private-path"):
            self.assertNotIn(value, exposed)


if __name__ == "__main__": unittest.main()
