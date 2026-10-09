"""Capture bounded thread samples from this runner's fictional Watch UI tests."""
import argparse
from pathlib import Path
import subprocess
import time


def watch_processes(output):
    result = []
    for line in output.splitlines():
        fields = line.strip().split(maxsplit=1)
        if len(fields) != 2 or not fields[0].isdigit():
            continue
        executable = fields[1]
        if ('/CoreSimulator/Devices/' in executable and
                executable.endswith('/TennisTrackerWatchApp.app/TennisTrackerWatchApp')):
            result.append(int(fields[0]))
    return result


def sample(directory, duration):
    directory.mkdir(parents=True, exist_ok=True)
    deadline = time.monotonic() + duration
    counts = {}
    while time.monotonic() < deadline:
        processes = subprocess.run(['ps', '-axo', 'pid=,comm='], capture_output=True, text=True,
                                   timeout=10, check=True)
        for pid in watch_processes(processes.stdout):
            count = counts.get(pid, 0)
            if count >= 4:
                continue
            counts[pid] = count + 1
            subprocess.run(['/usr/bin/sample', str(pid), '2', '-file', str(directory / f'watch-{pid}-{count}.txt')],
                           stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, timeout=15, check=False)
        time.sleep(20)


if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('--output', type=Path, required=True)
    parser.add_argument('--seconds', type=int, default=1800)
    args = parser.parse_args()
    if not 20 <= args.seconds <= 1800:
        raise ValueError('Sampling must be bounded to 30 minutes')
    sample(args.output, args.seconds)
