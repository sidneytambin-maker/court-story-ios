import unittest
from create_apple_test_simulator import select_runtime, select_device, version


class SimulatorSelectionTests(unittest.TestCase):
    def test_only_available_compatible_runtime_is_selected(self):
        def runtime(value, available=True):
            return {"identifier": "com.apple.CoreSimulator.SimRuntime.iOS-" + value.replace(".", "-"),
                    "version": value, "isAvailable": available}
        choices = [runtime("27.0"), runtime("26.0"), runtime("26.6"), runtime("26.7"), runtime("26.6.1", False)]
        self.assertEqual(select_runtime(choices, "iOS", "26.6")["version"], "26.6")
        self.assertEqual(version("26.6"), version("26.6.0"))

    def test_device_selection_does_not_depend_on_simctl_order(self):
        devices = [{"name": "iPhone 17 Pro", "minRuntimeVersionString": "26.0"},
                   {"name": "iPhone 11 Pro Max", "minRuntimeVersionString": "13.0"}]
        self.assertEqual(select_device(devices)["name"], "iPhone 17 Pro")
        self.assertEqual(select_device(list(reversed(devices)))["name"], "iPhone 17 Pro")

    def test_missing_compatible_runtime_is_an_explicit_failure(self):
        with self.assertRaises(RuntimeError):
            select_runtime([], "watchOS", "26.6")


if __name__ == "__main__":
    unittest.main()
