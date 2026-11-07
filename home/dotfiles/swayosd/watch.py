"""Show master-volume/backlight changes without replacing any existing controls.

PulseAudio events drive audio reads; cheap sysfs reads track screen brightness.
SwayOSD only renders feedback: this observer never writes audio or backlight state.
"""

import math
import os
from pathlib import Path
import re
import selectors
import subprocess
import sys
import time


AUDIO_EVENT = re.compile(rb"Event '(?:change|new|remove)' on (?:sink|server) #")
BRIGHTNESS_INTERVAL = 0.04
AUDIO_INTERVAL = 0.02


class AudioReadSchedule:
    """Read the first event immediately; coalesce rapid changes without postponing them."""

    def __init__(self):
        self.deadline = None
        self.ready_at = 0.0

    def queue(self, now):
        if self.deadline is None:
            self.deadline = max(now, self.ready_at)

    def complete(self, now):
        self.deadline = None
        self.ready_at = now + AUDIO_INTERVAL


def audio_state():
    result = subprocess.run(
        ["wpctl", "get-volume", "@DEFAULT_AUDIO_SINK@"],
        capture_output=True, text=True, timeout=2, check=False,
    )
    match = re.fullmatch(r"Volume:\s+([0-9]+(?:\.[0-9]+)?)(\s+\[MUTED\])?\s*", result.stdout)
    if result.returncode or not match:
        return None
    volume = float(match[1])
    return (volume, bool(match[2])) if math.isfinite(volume) else None


def backlight_device(root=Path("/sys/class/backlight")):
    devices = sorted(path for path in root.glob("*")
                     if (path / "brightness").is_file() and (path / "max_brightness").is_file())
    return next((path for path in devices if read_text(path / "type") == "raw"),
                next(iter(devices), None))


def read_text(path):
    try:
        return path.read_text().strip()
    except OSError:
        return ""


def brightness_state(device):
    if device is None:
        return None
    try:
        current = int(read_text(device / "brightness"))
        maximum = int(read_text(device / "max_brightness"))
        return (current, maximum) if maximum > 0 else None
    except ValueError:
        return None


def audio_feedback(state):
    volume, muted = state
    percent = round(volume * 100)
    level = "muted" if muted or percent == 0 else (
        "low" if percent <= 33 else "medium" if percent <= 66 else "high")
    return (f"sink-volume-{level}-symbolic", 0.0 if muted else volume,
            "Muted" if muted else f"{percent}%")


def brightness_feedback(state):
    current, maximum = state
    fraction = current / maximum
    return ("display-brightness-symbolic", fraction, f"{round(fraction * 100)}%")


def show_feedback(feedback):
    icon, fraction, text = feedback
    # SwayOSD 0.2.1/GLib omits a zero-valued double from its parsed options.
    # A visually empty positive fraction still dispatches the progress action.
    progress = min(1.0, max(0.0001, fraction))
    result = subprocess.run(
        ["swayosd-client", "--custom-icon", icon,
         "--custom-progress", f"{progress:.4f}",
         "--custom-progress-text", text],
        capture_output=True, text=True, timeout=2, check=False,
    )
    if result.returncode:
        print(f"OSD unavailable: {result.stderr.strip()}", file=sys.stderr, flush=True)


def main():
    device = backlight_device()
    previous_audio = audio_state()
    previous_brightness = brightness_state(device)
    next_brightness = time.monotonic() + BRIGHTNESS_INTERVAL
    audio_reads = AudioReadSchedule()
    buffer = b""
    env = dict(os.environ, LC_ALL="C")
    with subprocess.Popen(["pactl", "subscribe"], stdout=subprocess.PIPE, env=env) as events:
        try:
            with selectors.DefaultSelector() as selector:
                selector.register(events.stdout, selectors.EVENT_READ)
                while True:
                    now = time.monotonic()
                    deadline = min(next_brightness, audio_reads.deadline
                                   if audio_reads.deadline is not None else next_brightness)
                    for key, _ in selector.select(max(0.0, deadline - now)):
                        data = os.read(key.fd, 65536)
                        if not data:
                            raise RuntimeError("PulseAudio event subscription disconnected")
                        buffer += data
                        lines = buffer.split(b"\n")
                        buffer = lines.pop()
                        if any(AUDIO_EVENT.search(line) for line in lines):
                            audio_reads.queue(time.monotonic())
                    now = time.monotonic()
                    feedback = None
                    if audio_reads.deadline is not None and now >= audio_reads.deadline:
                        state = audio_state()
                        audio_reads.complete(time.monotonic())
                        if state is not None and state != previous_audio:
                            # Initial discovery is silent; later changes reset the OSD timer.
                            if previous_audio is not None:
                                feedback = audio_feedback(state)
                            previous_audio = state
                    if now >= next_brightness:
                        next_brightness = now + BRIGHTNESS_INTERVAL
                        state = brightness_state(device)
                        if state is not None and state != previous_brightness:
                            if previous_brightness is not None:
                                feedback = brightness_feedback(state)
                            previous_brightness = state
                        elif state is None:
                            device = backlight_device()
                            previous_brightness = brightness_state(device)
                    if feedback is not None:
                        show_feedback(feedback)
        finally:
            events.terminate()
            try:
                events.wait(timeout=2)
            except subprocess.TimeoutExpired:
                events.kill()
                events.wait()


if __name__ == "__main__":
    try:
        main()
    except (OSError, RuntimeError, subprocess.TimeoutExpired) as error:
        print(error, file=sys.stderr, flush=True)
        sys.exit(1)
