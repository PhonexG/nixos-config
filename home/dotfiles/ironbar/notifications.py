#!/usr/bin/env python3
"""Event-driven SwayNC button: count, Do Not Disturb, and a live tooltip."""

import json
import signal
import subprocess
import threading


def render(event):
    count = max(0, int(event.get("count", 0)))
    dnd = bool(event.get("dnd", False))
    label = "󰂛" if dnd else "󰂞" if count else "󰂚"
    if dnd:
        label = f'<span foreground="#a55555">{label}</span>'
    tooltip = f"Notifications: {count}\nDo Not Disturb: {'enabled' if dnd else 'disabled'}"
    return label, tooltip


def publish_tooltip(text):
    try:
        subprocess.run(
            ["ironbar", "var", "set", "notifications_status", text],
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
            timeout=3,
            check=False,
        )
    except (OSError, subprocess.TimeoutExpired):
        pass


def watch():
    stopped = threading.Event()
    process = None

    def stop(_signum, _frame):
        stopped.set()
        if process is not None and process.poll() is None:
            process.terminate()

    signal.signal(signal.SIGTERM, stop)
    signal.signal(signal.SIGINT, stop)
    last = None
    while not stopped.is_set():
        try:
            process = subprocess.Popen(
                ["swaync-client", "--skip-wait", "--subscribe"],
                stdout=subprocess.PIPE,
                stderr=subprocess.DEVNULL,
                text=True,
                encoding="utf-8",
            )
            for line in process.stdout:
                if stopped.is_set():
                    break
                try:
                    label, tooltip = render(json.loads(line))
                except (ValueError, TypeError, AttributeError):
                    continue
                if (label, tooltip) != last:
                    print(label, flush=True)
                    publish_tooltip(tooltip)
                    last = (label, tooltip)
        except OSError:
            pass
        finally:
            if process is not None:
                if process.poll() is None:
                    process.terminate()
                try:
                    process.wait(timeout=3)
                except subprocess.TimeoutExpired:
                    process.kill()
                    process.wait()
                process = None
        if not stopped.is_set():
            offline = ('<span foreground="#787c99">󰂛</span>', "SwayNC unavailable")
            if last != offline:
                print(offline[0], flush=True)
                publish_tooltip(offline[1])
                last = offline
        stopped.wait(1)


if __name__ == "__main__":
    try:
        watch()
    except BrokenPipeError:
        pass
