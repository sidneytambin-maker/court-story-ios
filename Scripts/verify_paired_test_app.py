"""Reject an iPhone simulator fixture that cannot own its installed Watch app."""
import argparse
from pathlib import Path
import plistlib


def verify(app):
    phone = plistlib.loads((app / 'Info.plist').read_bytes())
    if any(not isinstance(phone.get(key), str) or not phone[key] for key in
           ('CFBundleIdentifier', 'CFBundleVersion', 'CFBundleShortVersionString')):
        raise ValueError('Paired test iPhone identity or version missing')
    watches = list((app / 'Watch').glob('*.app'))
    if len(watches) != 1:
        raise ValueError('The paired test iPhone app must embed exactly one Watch app')
    watch = plistlib.loads((watches[0] / 'Info.plist').read_bytes())
    if (watch.get('WKCompanionAppBundleIdentifier') != phone.get('CFBundleIdentifier') or
            watch.get('CFBundleIdentifier') != phone.get('CFBundleIdentifier', '') + '.watchkitapp' or
            watch.get('CFBundleVersion') != phone.get('CFBundleVersion') or
            watch.get('CFBundleShortVersionString') != phone.get('CFBundleShortVersionString') or
            watch.get('WKApplication') is not True or watch.get('TennisHealthEnabled') is not True):
        raise ValueError('Paired test bundle identities, versions or Health configuration do not match')
    for directory, info in ((app, phone), (watches[0], watch)):
        executable = info.get('CFBundleExecutable', '')
        if not executable or Path(executable).name != executable or not (directory / executable).is_file():
            raise ValueError('Paired test app executable missing')
    return {'paired_companion_verified': True}


if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('--app', type=Path, required=True)
    print(verify(parser.parse_args().app))
