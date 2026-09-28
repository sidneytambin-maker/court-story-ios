import json
import unittest

from check_fresh_release import check_empty, check_watch_preferences, compatible_simulator


class FreshReleaseTests(unittest.TestCase):
    def empty(self):
        return {"players": [], "matches": [], "trainingSessions": [], "tournaments": [], "deletedRecordIDs": [],
                "setup": {"coaches": [], "venues": [], "locations": [], "tournamentTemplates": []}}

    def test_fresh_state_is_accepted(self):
        check_empty(self.empty())
        check_watch_preferences({})

    def test_missing_library_table_is_not_treated_as_empty(self):
        data = self.empty()
        data.pop("trainingSessions")
        with self.assertRaises(ValueError): check_empty(data)

    def test_prepopulated_catalogue_is_rejected(self):
        for key in ("coaches", "venues", "locations", "tournamentTemplates"):
            data = self.empty()
            data["setup"][key] = [{"name": "Another tester's entry"}]
            with self.assertRaises(ValueError): check_empty(data)

    def test_derived_venues_or_achievements_cannot_leak(self):
        for key in ("knownVenues", "achievementHistory", "achievementRecords"):
            data = self.empty()
            data[key] = [{"id": "old-record"}]
            with self.assertRaises(ValueError): check_empty(data)

    def test_health_and_pending_activity_state_is_rejected(self):
        for key in ("activeHealthTrainingID", "pendingHealthTrainingIDs", "activeTournamentID", "pendingIntentRoute"):
            with self.assertRaises(ValueError): check_watch_preferences({key: "old-state"})

    def test_watch_queue_allows_only_an_unassociated_empty_handshake(self):
        check_watch_preferences({"queuedWatchCommands": json.dumps({"commands": []}).encode()})
        check_watch_preferences({"queuedWatchCommands": json.dumps({"commands": [{"requestSnapshot": {}}]}).encode()})
        for queue in ({"commands": ["old-command"]}, {"commands": [], "libraryID": "old-library"}):
            with self.assertRaises(ValueError): check_watch_preferences({"queuedWatchCommands": json.dumps(queue).encode()})

    def inventory(self):
        return {"runtimes": [{"identifier": "runtime.iOS-26", "version": "26.5", "isAvailable": True},
                             {"identifier": "runtime.watchOS-26", "version": "26.5", "isAvailable": True}],
                "devicetypes": [{"identifier": "phone-new", "name": "iPhone 17 Pro"},
                                {"identifier": "watch", "name": "Apple Watch Ultra 2"},
                                {"identifier": "phone-old", "name": "iPhone 6s Plus"}],
                "devices": {"runtime.iOS-26": [{"name": "iPhone 17 Pro", "deviceTypeIdentifier": "phone-new", "isAvailable": True}],
                            "runtime.watchOS-26": [{"name": "Apple Watch Ultra 2", "deviceTypeIdentifier": "watch", "isAvailable": True}]}}

    def test_fresh_simulator_uses_a_known_compatible_pair_not_last_model(self):
        self.assertEqual(compatible_simulator(self.inventory(), "iOS"), ("phone-new", "runtime.iOS-26"))
        self.assertEqual(compatible_simulator(self.inventory(), "watchOS"), ("watch", "runtime.watchOS-26"))

    def test_simulator_pair_can_use_exact_existing_device_name(self):
        inventory = self.inventory()
        del inventory["devices"]["runtime.iOS-26"][0]["deviceTypeIdentifier"]
        self.assertEqual(compatible_simulator(inventory, "iOS"), ("phone-new", "runtime.iOS-26"))

    def test_unavailable_or_mismatched_simulator_pairs_fail_closed(self):
        for change in ({"isAvailable": False}, {"deviceTypeIdentifier": "unknown"}):
            inventory = self.inventory()
            inventory["devices"]["runtime.iOS-26"][0].update(change)
            with self.subTest(change=change), self.assertRaises(ValueError): compatible_simulator(inventory, "iOS")

    def test_runtime_without_available_devices_is_not_guessed(self):
        inventory = self.inventory()
        inventory["devices"] = {}
        with self.assertRaises(ValueError): compatible_simulator(inventory, "iOS")


if __name__ == "__main__": unittest.main()
