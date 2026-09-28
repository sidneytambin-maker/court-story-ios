import unittest
from verify_tennis_sounds import verify


class TennisSoundTests(unittest.TestCase):
    def test_five_independent_licensed_recordings_and_short_pcm_assets(self):
        self.assertEqual(verify()["independent_cc0_sources"], 5)


if __name__ == "__main__":
    unittest.main()
