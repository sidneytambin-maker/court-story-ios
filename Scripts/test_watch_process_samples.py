import unittest
from sample_watch_test_process import watch_processes


class WatchProcessSamplesTests(unittest.TestCase):
    def test_only_watch_application_in_simulator_is_sampled(self):
        rows = '\n'.join([
            '123 /Users/runner/Library/Developer/CoreSimulator/Devices/fixture/data/Containers/Bundle/Application/fixture/TennisTrackerWatchApp.app/TennisTrackerWatchApp',
            '124 /Applications/TennisTrackerWatchApp.app/TennisTrackerWatchApp',
            '125 /Users/runner/Library/Developer/CoreSimulator/Devices/fixture/TennisTracker.app/TennisTracker',
            '126 /usr/bin/sample',
            'bad /Users/runner/Library/Developer/CoreSimulator/Devices/fixture/TennisTrackerWatchApp.app/TennisTrackerWatchApp'])
        self.assertEqual(watch_processes(rows), [123])
