"""Trim five independently sourced CC0 tennis recordings to short PCM cues."""
from array import array
import hashlib
import json
from pathlib import Path
import subprocess
import sys
import wave

ROOT = Path(__file__).resolve().parents[1]
DESTINATION = ROOT / "TennisTrackerShared/Sounds"
SOURCES = [
    ("bounce", "Tennis bounce", "tennis-bounce.wav", "tennis-bounces-original.wav", 0.045, 0.28,
     "Joseph SARDIN", "https://lasonotheque.org/balle-de-tennis-rebonds-s0584.html", "https://lasonotheque.org/UPLOAD/bwf-fr/0584.wav"),
    ("racketStrike", "Racket strike", "tennis-racket-strike.wav", "racket-strike-original.mp3", 4.015, 0.36,
     "jacklilley", "https://freesound.org/people/jacklilley/sounds/338122/", "https://cdn.freesound.org/previews/338/338122_2527347-hq.mp3"),
    ("racketSwing", "Racket swoosh", "tennis-racket-swoosh.wav", "racket-swing-original.mp3", 19.78, 0.55,
     "MIKEJONESBONES", "https://freesound.org/people/MIKEJONESBONES/sounds/511825/", "https://cdn.freesound.org/previews/511/511825_2686281-hq.mp3"),
    ("ballCan", "New ball can", "tennis-ball-can.wav", "ball-can-original.mp3", 0, 0.72,
     "tomschuetz", "https://freesound.org/people/tomschuetz/sounds/649763/", "https://cdn.freesound.org/previews/649/649763_5828489-hq.mp3"),
    ("applause", "Court applause", "tennis-applause.wav", "tennis-applause-original.mp3", 21.55, 1.2,
     "muse88", "https://freesound.org/people/muse88/sounds/490341/", "https://cdn.freesound.org/previews/490/490341_371140-hq.mp3"),
]


def build():
    import imageio_ffmpeg
    ffmpeg = imageio_ffmpeg.get_ffmpeg_exe()
    DESTINATION.mkdir(parents=True, exist_ok=True)
    report = {"license": "CC0-1.0", "license_url": "https://creativecommons.org/publicdomain/zero/1.0/",
              "verified_on": "2026-09-10", "sounds": []}
    for identifier, title, filename, original, start, length, author, page, url in SOURCES:
        source = ROOT / "Branding/Audio" / original
        raw = subprocess.check_output([ffmpeg, "-v", "error", "-i", str(source), "-ss", str(start), "-t", str(length),
                                       "-f", "s16le", "-ac", "1", "-ar", "48000", "-"])
        values = array("h", raw)
        if sys.byteorder != "little": values.byteswap()
        # A short fade and moderate peak leave headroom for VoiceOver and avoid clicks.
        fade = min(2400 if identifier == "applause" else 480, len(values) // 2)
        gain = 10000 / max(abs(value) for value in values)
        pcm = array("h", [round(value * gain * min(1, i / fade, (len(values) - 1 - i) / fade)) for i, value in enumerate(values)])
        if sys.byteorder != "little": pcm.byteswap()
        destination = DESTINATION / filename
        with wave.open(str(destination), "wb") as output:
            output.setparams((1, 2, 48000, 0, "NONE", "not compressed"))
            output.writeframes(pcm.tobytes())
        report["sounds"].append({"id": identifier, "title": title, "filename": filename, "seconds": len(values) / 48000,
            "sha256": hashlib.sha256(destination.read_bytes()).hexdigest(), "original": original,
            "source_sha256": hashlib.sha256(source.read_bytes()).hexdigest(), "author": author,
            "source_page": page, "download_url": url, "start_seconds": start,
            "edits": "One excerpt, mono PCM conversion, reduced peak and edge fades. No repeated, pitch-shifted or reused bounce variants."})
    (ROOT / "Branding/Audio/manifest.json").write_text(json.dumps(report, indent=2) + "\n", encoding="utf-8")
    print(json.dumps(report, indent=2))


if __name__ == "__main__": build()
