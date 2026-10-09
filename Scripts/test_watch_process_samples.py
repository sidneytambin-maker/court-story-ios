import unittest
from pathlib import Path
import subprocess
import tempfile
from unittest.mock import patch, Mock
from sample_watch_test_process import watch_processes, capture_sample, sample


class WatchProcessSamplesTests(unittest.TestCase):
    def test_only_watch_application_in_simulator_is_sampled(self):
        rows = '\n'.join([
            '123 /Users/runner/Library/Developer/CoreSimulator/Devices/fixture/data/Containers/Bundle/Application/fixture/TennisTrackerWatchApp.app/TennisTrackerWatchApp',
            '124 /Applications/TennisTrackerWatchApp.app/TennisTrackerWatchApp',
            '125 /Users/runner/Library/Developer/CoreSimulator/Devices/fixture/TennisTracker.app/TennisTracker',
            '126 /usr/bin/sample',
            'bad /Users/runner/Library/Developer/CoreSimulator/Devices/fixture/TennisTrackerWatchApp.app/TennisTrackerWatchApp'])
        self.assertEqual(watch_processes(rows), [123])

    def test_terminated_process_does_not_stop_later_sampling(self):
        with tempfile.TemporaryDirectory() as folder, patch('sample_watch_test_process.subprocess.run') as run:
            run.side_effect = [subprocess.TimeoutExpired('sample', 45), Mock(returncode=0)]
            first = capture_sample(123, Path(folder) / 'first.txt')
            second = capture_sample(124, Path(folder) / 'second.txt')
            self.assertTrue(first['timed_out'])
            self.assertEqual(second['returncode'], 0)
            self.assertTrue((Path(folder) / 'first.status.json').is_file())
            self.assertIn('-mayDie', run.call_args.args[0])
            self.assertEqual(run.call_args.kwargs['timeout'], 45)

    def test_nonzero_sample_result_is_recorded(self):
        with tempfile.TemporaryDirectory() as folder, patch('sample_watch_test_process.subprocess.run', return_value=Mock(returncode=1)):
            result = capture_sample(123, Path(folder) / 'gone.txt')
            self.assertEqual(result['returncode'], 1)
            self.assertFalse(result['timed_out'])

    def test_process_listing_timeout_does_not_end_monitor(self):
        with tempfile.TemporaryDirectory() as folder, \
                patch('sample_watch_test_process.time.monotonic', side_effect=[0, 1, 2, 100]), \
                patch('sample_watch_test_process.time.sleep'), \
                patch('sample_watch_test_process.subprocess.run') as run:
            run.side_effect = [subprocess.TimeoutExpired('ps', 10), Mock(stdout='')]
            sample(Path(folder), 50)
            self.assertEqual(run.call_count, 2)
