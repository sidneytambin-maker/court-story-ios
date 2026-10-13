"""Prepare Firebase Hosting files with verified native app identities.

Usage: python prepare_links.py NEW_DIRECTORY PLAY_APP_SIGNING_SHA256
The fingerprint must come from Play App Integrity, not the local upload key.
No credentials or invitation codes are included in the output.
"""
import json
from pathlib import Path
import re
import shutil
import sys

if len(sys.argv) != 3:
    raise SystemExit("Supply a new output directory and the Play app-signing SHA-256 fingerprint.")
fingerprint = sys.argv[2].replace(":", "").upper()
if not re.fullmatch(r"[0-9A-F]{64}", fingerprint):
    raise SystemExit("Expected the complete Play app-signing SHA-256 fingerprint.")
fingerprint = ":".join(fingerprint[i:i + 2] for i in range(0, 64, 2))
target = Path(sys.argv[1]).resolve()
target.mkdir(parents=True, exist_ok=False)
public = target / "public"
well_known = public / ".well-known"
well_known.mkdir(parents=True)
source = Path(__file__).resolve().parents[1] / "link-site"
for name in ("index.html", "invite.js", "invite.css"):
    shutil.copyfile(source / name, public / name)

def write(path, value):
    path.write_text(json.dumps(value, indent=2) + "\n", encoding="utf-8")

write(well_known / "apple-app-site-association", {
    "applinks": {"details": [{
        "appIDs": ["HT5X86Q4DD.com.inclusophy.tennistracker"],
        "components": [{"/": "/connect/invite", "comment": "Court Story Connect invitations"}]
    }]}
})
write(well_known / "assetlinks.json", [{
    "relation": ["delegate_permission/common.handle_all_urls"],
    "target": {"namespace": "android_app", "package_name": "com.courtstory.app",
               "sha256_cert_fingerprints": [fingerprint]}
}])
headers = {
    "Referrer-Policy": "no-referrer", "X-Content-Type-Options": "nosniff",
    "X-Frame-Options": "DENY", "Cache-Control": "no-store",
    "Permissions-Policy": "camera=(), microphone=(), geolocation=()",
    "Content-Security-Policy": "default-src 'none'; script-src 'self'; style-src 'self'; base-uri 'none'; form-action 'none'; connect-src 'none'; frame-ancestors 'none'"
}
write(target / "firebase.json", {"hosting": {
    "site": "court-story-connect", "public": "public",
    "ignore": ["firebase.json", "**/node_modules/**"],
    "headers": [
        {"source": "**", "headers": [{"key": key, "value": value} for key, value in headers.items()]},
        {"source": "/.well-known/**", "headers": [{"key": "Content-Type", "value": "application/json"}]}
    ],
    "rewrites": [{"source": "/connect/invite", "destination": "/index.html"}]
}})
write(target / ".firebaserc", {"projects": {"default": "court-story-connect"}})
print("Prepared invitation hosting and native association files. No deployment performed.")
