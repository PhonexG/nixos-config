#!/usr/bin/env python3
"""Read-only flake-input update checks, with explicitly confirmed application."""

import argparse
import concurrent.futures
import fcntl
import hashlib
import json
import os
from pathlib import Path
import re
import signal
import subprocess
import sys
import tempfile
import threading
import time
import urllib.error
import urllib.parse
import urllib.request


CHECK_INTERVAL = 6 * 60 * 60
ERROR_INTERVAL = 30 * 60
DEFAULT_FLAKE = Path("/etc/nixos")
DEFAULT_CACHE = Path(os.environ.get("XDG_CACHE_HOME", Path.home() / ".cache")) / "ironbar" / "nixos-updates.json"


def read_json(path):
    try:
        value = json.loads(path.read_text())
        return value if isinstance(value, dict) else {}
    except (OSError, ValueError):
        return {}


def fingerprint(flake):
    try:
        return hashlib.sha256((flake / "flake.lock").read_bytes()).hexdigest()
    except OSError:
        return ""


def github_inputs(lock):
    """Follow the branches named in the existing lock; skip pinned revisions."""
    nodes = lock.get("nodes", {})
    root = nodes.get(lock.get("root", "root"), {})
    result = []
    for name, node_name in root.get("inputs", {}).items():
        if not isinstance(node_name, str):
            continue
        node = nodes.get(node_name, {})
        original, locked = node.get("original", {}), node.get("locked", {})
        if original.get("type") != "github" or original.get("rev") or not locked.get("rev"):
            continue
        owner, repo = original.get("owner", ""), original.get("repo", "")
        if not re.fullmatch(r"[\w.-]+", owner) or not re.fullmatch(r"[\w.-]+", repo):
            continue
        result.append({"name": name, "owner": owner, "repo": repo,
                       "ref": original.get("ref") or "HEAD", "current": locked["rev"]})
    return result


def latest_revision(item):
    reference = urllib.parse.quote(item["ref"], safe="")
    url = f"https://api.github.com/repos/{item['owner']}/{item['repo']}/commits/{reference}"
    request = urllib.request.Request(url, headers={
        "Accept": "application/vnd.github+json", "User-Agent": "Oni-Ironbar-Updates"})
    with urllib.request.urlopen(request, timeout=15) as response:
        revision = json.load(response).get("sha", "")
    if not re.fullmatch(r"[0-9a-fA-F]{40}", revision):
        raise ValueError("GitHub returned an invalid revision")
    return revision


def atomic_json(path, value):
    path.parent.mkdir(parents=True, exist_ok=True)
    fd, temporary = tempfile.mkstemp(prefix=".updates-", dir=path.parent)
    try:
        with os.fdopen(fd, "w", encoding="utf-8") as output:
            json.dump(value, output, ensure_ascii=False)
        os.replace(temporary, path)
    finally:
        Path(temporary).unlink(missing_ok=True)


def check(flake=DEFAULT_FLAKE, cache=DEFAULT_CACHE, fetch_revision=latest_revision):
    """Only read flake.lock and GitHub; write results under the user's cache."""
    cache.parent.mkdir(parents=True, exist_ok=True)
    with cache.with_suffix(".check-lock").open("a") as guard:
        try:
            fcntl.flock(guard, fcntl.LOCK_EX | fcntl.LOCK_NB)
        except BlockingIOError:
            return read_json(cache)
        digest = fingerprint(flake)
        lock = read_json(flake / "flake.lock")
        items = github_inputs(lock)
        state = {"checked_at": time.time(), "fingerprint": digest, "inputs": [], "errors": []}
        if not items:
            state["errors"].append("No checkable GitHub inputs in flake.lock.")
        with concurrent.futures.ThreadPoolExecutor(max_workers=3) as executor:
            pending = {executor.submit(fetch_revision, item): item for item in items}
            for future in concurrent.futures.as_completed(pending):
                item = dict(pending[future])
                try:
                    item["latest"] = future.result()
                    item["available"] = item["latest"] != item["current"]
                    state["inputs"].append(item)
                except Exception as error:
                    if isinstance(error, urllib.error.HTTPError):
                        detail = f"GitHub HTTP {error.code}"
                        if error.code in (403, 429):
                            detail += " (rate limit or temporarily restricted access)"
                    elif isinstance(error, (urllib.error.URLError, TimeoutError)):
                        detail = "network unavailable or request timed out"
                    else:
                        detail = "could not retrieve the revision"
                    state["errors"].append(f"{item['name']}: {detail}")
        state["inputs"].sort(key=lambda item: item["name"])
        available = sum(item["available"] for item in state["inputs"])
        state["status"] = "available" if available else "error" if state["errors"] else "current"
        # Don't attribute responses to a lock that changed during the request.
        if fingerprint(flake) != digest:
            return read_json(cache)
        atomic_json(cache, state)
        return state


def render(state, digest):
    if not state or state.get("fingerprint") != digest:
        return "", "NixOS updates: waiting for a check."
    items = state.get("inputs", [])
    available = [item for item in items if item.get("available")]
    if available:
        label = ""
        lines = [f"New input revisions: {len(available)}"]
        lines += [f"{item['name']}: {item['current'][:7]} → {item['latest'][:7]}" for item in available]
    elif state.get("errors"):
        label, lines = '<span foreground="#e0af68">󰅙</span>', ["Could not fully check for updates."]
    else:
        label, lines = "", ["GitHub inputs in flake.lock are up to date."]
    lines.extend(state.get("errors", []))
    timestamp = time.strftime("%d.%m %H:%M", time.localtime(state.get("checked_at", 0)))
    lines += [f"Checked: {timestamp}", "Checks do not modify flake.lock or install packages."]
    return label, "\n".join(lines)


def needs_refresh(state, flake, now=None):
    interval = ERROR_INTERVAL if state.get("errors") else CHECK_INTERVAL
    return (not state or state.get("fingerprint") != fingerprint(flake)
            or (time.time() if now is None else now) - state.get("checked_at", 0) >= interval)


def publish_status(label, text):
    try:
        subprocess.run(["ironbar", "var", "set", "updates_status", text],
                       stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, timeout=3, check=False)
        subprocess.run(["ironbar", "var", "set", "updates_visible", "true" if label else "false"],
                       stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, timeout=3, check=False)
    except (OSError, subprocess.TimeoutExpired):
        pass


def notify(text):
    subprocess.run(["notify-send", "--urgency=low", "NixOS updates", text], check=False)


def watch(flake=DEFAULT_FLAKE, cache=DEFAULT_CACHE):
    stopped = threading.Event()
    signal.signal(signal.SIGTERM, lambda *_: stopped.set())
    signal.signal(signal.SIGINT, lambda *_: stopped.set())

    def refresh():
        while not stopped.is_set():
            if needs_refresh(read_json(cache), flake):
                try:
                    check(flake, cache)
                except OSError:
                    pass
            stopped.wait(60)

    threading.Thread(target=refresh, daemon=True).start()
    previous = None
    while not stopped.is_set():
        value = render(read_json(cache), fingerprint(flake))
        if value != previous:
            print(value[0], flush=True)
            publish_status(*value)
            previous = value
        stopped.wait(2)


def confirm(text):
    return input(f"\n{text}\nType \"yes\" to confirm: ").strip().lower() == "yes"


def apply(flake=DEFAULT_FLAKE, cache=DEFAULT_CACHE, current_only=False):
    """Reachable only from the explicitly chosen terminal action, never watch."""
    print("NixOS updates\nALL current configuration changes will be applied from", flake)
    subprocess.run(["git", "status", "--short"], cwd=flake, check=False)
    if not current_only:
        if not confirm("Update inputs? This changes flake.lock; the old copy will be saved in the cache."):
            print("Cancelled. flake.lock was not changed.")
            return 0
        cache.parent.mkdir(parents=True, exist_ok=True)
        fd, backup = tempfile.mkstemp(prefix="flake-lock-", suffix=".json", dir=cache.parent)
        with os.fdopen(fd, "wb") as output:
            output.write((flake / "flake.lock").read_bytes())
        print("flake.lock backup:", backup, flush=True)
        result = subprocess.run(["nix", "flake", "update", "--flake", f"path:{flake}"], check=False)
        if result.returncode:
            print("Input update failed. The saved copy has NOT been restored automatically.")
            return result.returncode
        subprocess.run(["git", "diff", "--", "flake.lock"], cwd=flake, check=False)
    if not confirm("Build and apply the current configuration? sudo will ask for your password."):
        print("Activation cancelled.")
        return 0
    result = subprocess.run(["sudo", "nixos-rebuild", "switch", "--flake", f"path:{flake}#nixos",
                             "--no-update-lock-file"], check=False)
    if result.returncode == 0:
        subprocess.run(["systemctl", "--user", "restart", "ironbar.service"], check=False)
        check(flake, cache)
    return result.returncode


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--flake-dir", type=Path, default=DEFAULT_FLAKE)
    parser.add_argument("--cache-file", type=Path, default=DEFAULT_CACHE)
    commands = parser.add_subparsers(dest="mode", required=True)
    commands.add_parser("watch")
    commands.add_parser("details")
    checker = commands.add_parser("check")
    checker.add_argument("--notify", action="store_true")
    application = commands.add_parser("apply")
    application.add_argument("--current-only", action="store_true")
    args = parser.parse_args()
    if args.mode == "watch":
        watch(args.flake_dir, args.cache_file)
    elif args.mode == "details":
        notify(render(read_json(args.cache_file), fingerprint(args.flake_dir))[1])
    elif args.mode == "check":
        state = check(args.flake_dir, args.cache_file)
        label, tooltip = render(state, fingerprint(args.flake_dir))
        publish_status(label, tooltip)
        if args.notify:
            notify(tooltip)
        else:
            print(tooltip)
        return 1 if state.get("status") == "error" else 0
    else:
        return apply(args.flake_dir, args.cache_file, args.current_only)
    return 0


if __name__ == "__main__":
    try:
        sys.exit(main())
    except (BrokenPipeError, KeyboardInterrupt):
        sys.exit(0)
