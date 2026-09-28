import contextlib
import datetime as dt
import io
import plistlib
from pathlib import Path
import subprocess
import tempfile
import unittest
import uuid
from unittest.mock import patch

from upload_testflight import REQUIRED, TARGETS, encrypt_failure_diagnostic, export_options, failure_categories, profile_identifier, require_credentials, run
import test_testflight_signing as signing_fixtures


class TestFlightUploadTests(unittest.TestCase):
    def credentials(self):
        values = {key: "private-test-value" for key in REQUIRED}
        values["TENNIS_ASC_KEY_ID"] = "ABC123DEF4"
        values["TENNIS_ASC_ISSUER_ID"] = str(uuid.uuid4())
        return values

    def test_missing_credentials_stop_before_native_signing(self):
        for name in REQUIRED:
            values = self.credentials()
            values.pop(name)
            with self.assertRaisesRegex(ValueError, name): require_credentials(values)

    def test_valid_identifier_format_is_accepted(self):
        require_credentials(self.credentials())

    def test_invalid_key_identifier_is_rejected(self):
        values = self.credentials()
        values["TENNIS_ASC_KEY_ID"] = "../invalid"
        with self.assertRaises(ValueError): require_credentials(values)

    def test_export_maps_three_distinct_profiles_and_preserves_build_number(self):
        profiles = {identifier: str(uuid.uuid4()) for identifier, _ in TARGETS.values()}
        options = export_options(profiles)
        self.assertEqual(options["method"], "app-store-connect")
        self.assertEqual(options["destination"], "export")
        self.assertFalse(options["manageAppVersionAndBuildNumber"])
        self.assertEqual(plistlib.loads(plistlib.dumps(options))["provisioningProfiles"], profiles)

    def test_missing_or_reused_component_profile_blocks_export(self):
        profiles = {identifier: "same-profile" for identifier, _ in TARGETS.values()}
        with self.assertRaises(ValueError): export_options(profiles)
        profiles.pop(next(iter(profiles)))
        with self.assertRaises(ValueError): export_options(profiles)

    def test_profile_preflight_checks_actual_identity_and_app_store_type(self):
        fixture = signing_fixtures.TestFlightSigningTests()
        fixture.setUp()
        fixture.profile["UUID"] = str(uuid.uuid4())
        now = dt.datetime(2026, 9, 10, tzinfo=dt.timezone.utc)
        self.assertEqual(profile_identifier(fixture.profile, fixture.identifier, now), fixture.profile["UUID"])
        fixture.profile["ProvisionedDevices"] = ["test-device"]
        with self.assertRaises(ValueError): profile_identifier(fixture.profile, fixture.identifier, now)

    def test_signing_errors_do_not_print_private_native_output(self):
        captured = io.StringIO()
        result = subprocess.CompletedProcess(["native-tool"], 1, stdout=b"private account", stderr=b"private certificate")
        with contextlib.redirect_stdout(captured), patch("upload_testflight.subprocess.run", return_value=result), self.assertRaises(RuntimeError) as error:
            run("Sign package", "native-tool")
        self.assertNotIn("private account", captured.getvalue() + str(error.exception))
        self.assertNotIn("private certificate", captured.getvalue() + str(error.exception))

    def test_subprocesses_do_not_inherit_ci_signing_secrets(self):
        result = subprocess.CompletedProcess(["native-tool"], 0, stdout=b"ok")
        with patch.dict("os.environ", self.credentials()), patch("upload_testflight.subprocess.run", return_value=result) as call, contextlib.redirect_stdout(io.StringIO()):
            self.assertEqual(run("Native check", "native-tool"), b"ok")
        environment = call.call_args.kwargs["env"]
        self.assertTrue(all(key not in environment for key in REQUIRED))

    def test_failure_categories_expose_no_native_profile_or_account_values(self):
        message = b'error: Team "private team" doesn\'t have a provisioning profile matching "private profile".'
        self.assertEqual(failure_categories(message, b""), ["profile_not_found"])
        self.assertEqual(failure_categories(b"private secret", b"unknown private message"), [])

    def test_certificate_and_entitlement_failures_are_distinguished(self):
        self.assertEqual(failure_categories(b'Provisioning profile "secret" doesn\'t include signing certificate "secret"', b""), ["profile_certificate_mismatch"])
        self.assertEqual(failure_categories(b'Provisioning profile "secret" doesn\'t support HealthKit', b""), ["profile_entitlement_mismatch"])

    def test_native_singular_profile_lookup_failure_is_classified(self):
        self.assertEqual(failure_categories(b"error: No profile for team 'private' matching 'private' found", b""), ["profile_not_found"])

    def test_diagnostic_writes_only_encrypted_output_and_excludes_signing_secrets(self):
        with tempfile.TemporaryDirectory() as directory:
            environment = {**self.credentials(), "RUNNER_TEMP": directory, "TENNIS_DIAGNOSTIC_RECIPIENT": "public recipient"}
            result = subprocess.CompletedProcess([], 0, stdout=b"encrypted-cms", stderr=b"")
            with patch.dict("os.environ", environment), patch("upload_testflight.subprocess.run", return_value=result) as call, contextlib.redirect_stdout(io.StringIO()):
                encrypt_failure_diagnostic("Apple check", b"private diagnostic", b"private error")
            self.assertEqual((Path(directory) / "tennis-private-diagnostics/Apple-check.cms").read_bytes(), b"encrypted-cms")
            self.assertTrue(all(key not in call.call_args.kwargs["env"] for key in REQUIRED))
            self.assertEqual(len(list(Path(directory).rglob("*.*"))), 1)

    def test_diagnostic_encryption_failure_never_exposes_raw_output(self):
        captured = io.StringIO()
        with tempfile.TemporaryDirectory() as directory, patch.dict("os.environ", {"RUNNER_TEMP": directory, "TENNIS_DIAGNOSTIC_RECIPIENT": "public"}):
            result = subprocess.CompletedProcess([], 1, stdout=b"", stderr=b"private failure")
            with patch("upload_testflight.subprocess.run", return_value=result), contextlib.redirect_stdout(captured):
                encrypt_failure_diagnostic("Apple check", b"private diagnostic", b"private error")
            self.assertEqual(list(Path(directory).iterdir()), [])
        self.assertNotIn("private diagnostic", captured.getvalue())
        self.assertNotIn("private error", captured.getvalue())


if __name__ == "__main__": unittest.main()
