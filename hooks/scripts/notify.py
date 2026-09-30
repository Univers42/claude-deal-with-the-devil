"""notify.py: the notification job. A sound per event, if sounds are installed."""

import subprocess

from kit import HOOK_DIR
from process import which


def play_sound(event, data):
    """Best effort. No sounds ship with this repo — see hooks/sounds/README.md."""
    try:
        sounds = HOOK_DIR / "sounds" / event.lower()
        if not sounds.is_dir():
            return
        for ext in (".wav", ".mp3"):
            for f in sorted(sounds.glob(f"*{ext}")):
                for player in ("paplay", "aplay", "afplay", "ffplay"):
                    if which(player):
                        args = [player, str(f)]
                        if player == "ffplay":
                            args = [
                                "ffplay",
                                "-nodisp",
                                "-autoexit",
                                "-loglevel",
                                "quiet",
                                str(f),
                            ]
                        subprocess.Popen(
                            args, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL
                        )
                        return
    except Exception:
        return
