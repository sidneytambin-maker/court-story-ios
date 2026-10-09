from pathlib import Path
import plistlib
import tempfile
import unittest
from verify_paired_test_app import verify


class PairedTestAppTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.app = Path(self.temporary.name) / 'Phone.app'
        self.watch = self.app / 'Watch' / 'Watch.app'
        self.watch.mkdir(parents=True)
        self.phone_info = dict(CFBundleIdentifier='example.court', CFBundleVersion='34',
                               CFBundleShortVersionString='0.1.0', CFBundleExecutable='Phone')
        self.watch_info = dict(CFBundleIdentifier='example.court.watchkitapp', CFBundleVersion='34',
                               CFBundleShortVersionString='0.1.0', CFBundleExecutable='Watch',
                               WKCompanionAppBundleIdentifier='example.court', WKApplication=True,
                               TennisHealthEnabled=True)
        self.write()
        (self.app / 'Phone').write_bytes(b'fictional simulator executable')
        (self.watch / 'Watch').write_bytes(b'fictional simulator executable')

    def write(self):
        (self.app / 'Info.plist').write_bytes(plistlib.dumps(self.phone_info))
        (self.watch / 'Info.plist').write_bytes(plistlib.dumps(self.watch_info))

    def test_matching_companion_passes(self):
        self.assertTrue(verify(self.app)['paired_companion_verified'])

    def test_phone_without_embedded_watch_fails(self):
        self.watch.rename(self.app / 'Detached.app')
        with self.assertRaises(ValueError):
            verify(self.app)

    def test_wrong_owner_version_health_and_missing_binary_fail(self):
        for key, value in [('WKCompanionAppBundleIdentifier', 'example.other'),
                           ('CFBundleVersion', '33'), ('TennisHealthEnabled', False)]:
            with self.subTest(key=key):
                original = self.watch_info[key]
                self.watch_info[key] = value
                self.write()
                with self.assertRaises(ValueError):
                    verify(self.app)
                self.watch_info[key] = original
        self.write()
        (self.watch / 'Watch').unlink()
        with self.assertRaises(ValueError):
            verify(self.app)


if __name__ == '__main__':
    unittest.main()
