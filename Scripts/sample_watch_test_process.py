"""Capture bounded thread samples from this runner's fictional Watch UI tests."""
import argparse
import json
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
        try:
            processes = subprocess.run(['ps', '-axo', 'pid=,comm='], capture_output=True, text=True,
                                       timeout=10, check=True)
        except (subprocess.TimeoutExpired, subprocess.CalledProcessError):
            time.sleep(20)
            continue
        for pid in watch_processes(processes.stdout):
            count = counts.get(pid, 0)
            if count >= 8:
                continue
            counts[pid] = count + 1
            capture_sample(pid, directory / f'watch-{pid}-{count}.txt')
        time.sleep(20)


def capture_sample(pid, path):
    # Tests intentionally terminate their app. A vanished process or slow symbol
    # lookup must not prevent later captures of the actual unresponsive process.
    try:
        result = subprocess.run(['/usr/bin/sample', str(pid), '2', '10', '-mayDie', '-file', str(path)],
                                stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, timeout=45, check=False)
        status = {'pid': pid, 'returncode': result.returncode, 'timed_out': False}
    except subprocess.TimeoutExpired:
        status = {'pid': pid, 'returncode': None, 'timed_out': True}
    path.with_suffix('.status.json').write_text(json.dumps(status) + '\n', encoding='utf-8')
    return status


if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('--output', type=Path, required=True)
    parser.add_argument('--seconds', type=int, default=1800)
    args = parser.parse_args()
    if not 20 <= args.seconds <= 5400:
        raise ValueError('Sampling must be bounded to 90 minutes')
    sample(args.output, args.seconds)
