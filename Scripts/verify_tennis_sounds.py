"""Verify independently sourced, short PCM sounds in source and both app bundles."""
import argparse
import hashlib
import io
import json
from pathlib import Path
import wave
import zipfile

ROOT = Path(__file__).resolve().parents[1]


def check_audio(content, expected):
    assert hashlib.sha256(content).hexdigest() == expected["sha256"], expected["filename"]
    with wave.open(io.BytesIO(content)) as audio:
        assert audio.getnchannels() == 1 and audio.getsampwidth() == 2
        assert audio.getframerate() == 48000 and audio.getcomptype() == "NONE"
        assert 0.1 < audio.getnframes() / audio.getframerate() < 2
        assert abs(audio.getnframes() / audio.getframerate() - expected["seconds"]) < 0.001
        assert any(audio.readframes(audio.getnframes())), "Silent cue"


def verify(ipa=None):
    manifest = json.loads((ROOT / "Branding/Audio/manifest.json").read_text(encoding="utf-8"))
    sounds = manifest["sounds"]
    assert manifest["license"] == "CC0-1.0" and len(sounds) == 5
    for key in ["id", "filename", "sha256", "source_sha256", "source_page", "original"]:
        assert len({sound[key] for sound in sounds}) == 5, "Reused sound or source: " + key
    expected_names = {sound["filename"] for sound in sounds}
    assert {path.name for path in (ROOT / "TennisTrackerShared/Sounds").glob("*.wav")} == expected_names
    for sound in sounds:
        source = ROOT / "Branding/Audio" / sound["original"]
        assert hashlib.sha256(source.read_bytes()).hexdigest() == sound["source_sha256"]
        check_audio((ROOT / "TennisTrackerShared/Sounds" / sound["filename"]).read_bytes(), sound)
    bundles = []
    if ipa:
        with zipfile.ZipFile(ipa) as archive:
            roots = [name[:-len("Info.plist")] for name in archive.namelist()
                     if name.startswith("Payload/") and name.endswith(".app/Info.plist")]
            phone = [root for root in roots if root.count("/") == 2]
            watch = [root for root in roots if "/Watch/" in root and root.count("/") == 4]
            assert len(phone) == len(watch) == 1, "Missing or misplaced phone/Watch app"
            for root in phone + watch:
                for sound in sounds:
                    check_audio(archive.read(root + sound["filename"]), sound)
                bundles.append(root)
    return {"independent_cc0_sources": 5, "verified_cues": 5, "bundles": bundles,
            "custom_notification_sound": "iPhone only; Watch uses foreground preview and feedback"}


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--ipa", type=Path)
    print(json.dumps(verify(parser.parse_args().ipa), indent=2))
