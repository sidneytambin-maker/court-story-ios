import unittest
from create_apple_test_simulator import select_runtime, version


class SimulatorSelectionTests(unittest.TestCase):
    def test_only_available_compatible_runtime_is_selected(self):
        def runtime(value, available=True):
            return {"identifier": "com.apple.CoreSimulator.SimRuntime.iOS-" + value.replace(".", "-"),
                    "version": value, "isAvailable": available}
        choices = [runtime("27.0"), runtime("26.0"), runtime("26.6"), runtime("26.7"), runtime("26.6.1", False)]
        self.assertEqual(select_runtime(choices, "iOS", "26.6")["version"], "26.6")
        self.assertEqual(version("26.6"), version("26.6.0"))

    def test_missing_compatible_runtime_is_an_explicit_failure(self):
        with self.assertRaises(RuntimeError):
            select_runtime([], "watchOS", "26.6")


if __name__ == "__main__":
    unittest.main()
