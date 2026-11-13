"""Exercise the rclone wrapper without accessing the real home or network."""

import fcntl
import json
import os
from pathlib import Path
import shutil
import stat
import subprocess
import sys
import tempfile
import unittest


SCRIPT = (
    Path(__file__).resolve().parents[2]
    / "home/dotfiles/rclone/rclone-autofix.sh"
)
BASH = shutil.which("bash")
REAL_TEE = shutil.which("tee")

MOCK_COMMAND = """import json
import os
from pathlib import Path
import sys

command = Path(sys.argv[0]).name
if command == "rclone":
    with open(os.environ["TEST_RCLONE_LOG"], "a") as log:
        log.write(json.dumps(sys.argv[1:]) + "\\n")
    if sys.argv[1] == "listremotes":
        sys.stdout.write(os.environ.get("TEST_REMOTE_NAMES", "gdrive:\\n"))
        sys.exit(int(os.environ.get("TEST_LISTREMOTES_EXIT_CODE", "0")))
    if sys.argv[1] != "bisync":
        sys.exit(99)
    sys.stdout.write(os.environ.get("TEST_SYNC_STDOUT", "Mock bisync output\\n"))
    sys.stderr.write(os.environ.get("TEST_SYNC_STDERR", ""))
    sys.exit(int(os.environ.get("TEST_SYNC_EXIT_CODE", "0")))
elif command == "notify-send":
    with open(os.environ["TEST_NOTIFY_LOG"], "a") as log:
        log.write(json.dumps(sys.argv[1:]) + "\\n")
    sys.exit(int(os.environ.get("TEST_NOTIFY_EXIT_CODE", "0")))
elif command in ("ping", "curl"):
    with open(os.environ["TEST_NETWORK_LOG"], "a") as log:
        log.write(json.dumps([command, *sys.argv[1:]]) + "\\n")
    sys.exit(int(os.environ.get("TEST_" + command.upper() + "_EXIT_CODE", "0")))
else:
    sys.exit(99)
"""


class RcloneWrapperTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(
            prefix="rclone-wrapper-test.", dir="/tmp/opencode"
        )
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.home = self.root / "home"
        self.bin = self.root / "bin"
        self.home.mkdir()
        self.bin.mkdir()
        self.local = self.home / "GDriveOffline"
        self.local.mkdir()
        self.config = self.home / ".config/rclone/rclone.conf"
        self.filters = self.config.with_name("bisync-filters.txt")
        self.config.parent.mkdir(parents=True)
        self.config.write_text("[gdrive]\ntype = drive\n")
        self.config.chmod(0o644)
        self.filters.write_text("- **/*.tmp\n")
        self.cache = self.home / ".cache/rclone/bisync"
        self.cache.mkdir(parents=True)
        self.rclone_lock = self.cache / "test-paths.lck"
        self.rclone_lock.write_text("another process owns this lock\n")
        self.state = self.home / ".local/state/rclone"
        self.log = self.state / "rclone-bisync.log"

        # Only the disposable copy uses this PATH. No real rclone, curl, ping,
        # or desktop notification executable is reachable by the test script.
        lines = SCRIPT.read_text().splitlines(keepends=True)
        path_lines = [i for i, line in enumerate(lines) if line.startswith("export PATH=")]
        self.assertEqual(len(path_lines), 1)
        lines[path_lines[0]] = 'export PATH="$RCLONE_TEST_BIN"\n'
        self.script = self.root / "rclone-autofix.sh"
        self.script.write_text("".join(lines))

        for command in ("mkdir", "touch", "chmod", "tee", "mktemp", "grep", "rm", "date", "flock"):
            executable = shutil.which(command)
            self.assertIsNotNone(executable, command)
            (self.bin / command).symlink_to(executable)
        for command in ("rclone", "notify-send", "ping", "curl"):
            self.write_command(command, MOCK_COMMAND)

        self.env = {
            key: value
            for key, value in os.environ.items()
            if not key.startswith(("RCLONE_", "TEST_", "XDG_"))
        }
        self.env.update(
            HOME=str(self.home),
            USER="rclone-test",
            RCLONE_TEST_BIN=str(self.bin),
            TEST_RCLONE_LOG=str(self.root / "rclone-calls.jsonl"),
            TEST_NOTIFY_LOG=str(self.root / "notifications.jsonl"),
            TEST_NETWORK_LOG=str(self.root / "network-calls.jsonl"),
            TEST_REAL_TEE=REAL_TEE,
        )

    def write_command(self, name, code):
        command = self.bin / name
        if command.is_symlink():
            command.unlink()
        command.write_text(f"#!{sys.executable}\n{code}")
        command.chmod(0o755)

    def run_wrapper(self, *args, **env):
        result = subprocess.run(
            [BASH, str(self.script), *args],
            env={**self.env, **env},
            cwd=self.home,
            stdin=subprocess.DEVNULL,
            capture_output=True,
            text=True,
            timeout=10,
        )
        self.assertEqual(
            self.rclone_lock.read_text(), "another process owns this lock\n"
        )
        self.assertEqual(list(self.state.glob("rclone-run.*")), [])
        return result

    def calls(self, key="TEST_RCLONE_LOG"):
        path = Path(self.env[key])
        return [json.loads(line) for line in path.read_text().splitlines()] if path.exists() else []

    def sync_calls(self):
        return [args for args in self.calls() if args[0] == "bisync"]

    def test_success_keeps_safeguards_and_private_files(self):
        result = self.run_wrapper()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("Синхронізація успішна.", result.stdout)
        calls = self.sync_calls()
        self.assertEqual(len(calls), 1)
        args = calls[0]
        self.assertNotIn("--force", args)
        self.assertNotIn("--resync", args)
        self.assertIn("--recover", args)
        self.assertIn("--resilient", args)
        self.assertEqual(args[args.index("--color") + 1], "NEVER")
        self.assertEqual(args[args.index("--workdir") + 1], str(self.cache))
        self.assertEqual(args[args.index("--conflict-loser") + 1], "num")
        self.assertEqual(stat.S_IMODE(self.config.stat().st_mode), 0o600)
        self.assertEqual(stat.S_IMODE(self.log.stat().st_mode), 0o600)
        self.assertIn("Mock bisync output", self.log.read_text())
        self.assertEqual(self.calls("TEST_NOTIFY_LOG"), [])

    def test_failure_preserves_exit_code_and_does_not_resync(self):
        result = self.run_wrapper(
            TEST_SYNC_EXIT_CODE="7",
            TEST_SYNC_STDERR="Bisync aborted. Must run --resync to recover.\n",
        )
        self.assertEqual(result.returncode, 7)
        self.assertEqual(len(self.sync_calls()), 1)
        self.assertNotIn("--resync", self.sync_calls()[0])
        self.assertIn("Автоматичний --resync вимкнено", result.stdout)
        self.assertIn("Must run --resync", self.log.read_text())
        self.assertEqual(len(self.calls("TEST_NOTIFY_LOG")), 1)

    def test_notification_failure_does_not_mask_sync_failure(self):
        result = self.run_wrapper(TEST_SYNC_EXIT_CODE="7", TEST_NOTIFY_EXIT_CODE="1")
        self.assertEqual(result.returncode, 7)
        self.assertEqual(len(self.sync_calls()), 1)

    def test_oauth_error_is_found_in_current_run_and_uses_remote_name(self):
        result = self.run_wrapper(
            RCLONE_REMOTE="backup:folder",
            TEST_REMOTE_NAMES="backup:\n",
            TEST_SYNC_EXIT_CODE="7",
            TEST_SYNC_STDERR="invalid_grant\n" + "later log line\n" * 30,
        )
        self.assertEqual(result.returncode, 7)
        notices = self.calls("TEST_NOTIFY_LOG")
        self.assertEqual(len(notices), 1)
        self.assertIn("reconnect 'backup:'", notices[0][-1])
        self.assertEqual(len(self.sync_calls()), 1)

    def test_old_oauth_error_does_not_fail_a_successful_run(self):
        self.state.mkdir(parents=True)
        self.log.write_text("old error: invalid_grant\n")
        result = self.run_wrapper()
        self.assertEqual(result.returncode, 0)
        self.assertEqual(self.calls("TEST_NOTIFY_LOG"), [])

    def test_missing_local_directory_is_not_created(self):
        self.local.rmdir()
        result = self.run_wrapper()
        self.assertEqual(result.returncode, 2)
        self.assertFalse(self.local.exists())
        self.assertEqual(self.calls(), [])

    def test_missing_filters_are_not_replaced_with_empty_filters(self):
        self.filters.unlink()
        result = self.run_wrapper()
        self.assertEqual(result.returncode, 2)
        self.assertFalse(self.filters.exists())
        self.assertEqual(self.calls(), [])

    def test_missing_rclone_aborts(self):
        (self.bin / "rclone").unlink()
        result = self.run_wrapper()
        self.assertEqual(result.returncode, 127)
        self.assertEqual(self.calls(), [])

    def test_missing_remote_aborts(self):
        result = self.run_wrapper(TEST_REMOTE_NAMES="other:\n")
        self.assertEqual(result.returncode, 2)
        self.assertEqual(self.sync_calls(), [])

    def test_unreadable_rclone_configuration_aborts(self):
        result = self.run_wrapper(TEST_LISTREMOTES_EXIT_CODE="1")
        self.assertEqual(result.returncode, 2)
        self.assertEqual(self.sync_calls(), [])

    def test_offline_run_skips_sync_and_bounds_http_probe(self):
        result = self.run_wrapper(TEST_PING_EXIT_CODE="1", TEST_CURL_EXIT_CODE="1")
        self.assertEqual(result.returncode, 0)
        self.assertIn("синхронізацію пропущено", result.stdout)
        self.assertEqual(self.sync_calls(), [])
        curl = self.calls("TEST_NETWORK_LOG")[1]
        self.assertEqual(curl[0], "curl")
        self.assertEqual(curl[curl.index("--max-time") + 1], "5")

    def test_failed_ping_can_fall_back_to_http(self):
        result = self.run_wrapper(TEST_PING_EXIT_CODE="1", TEST_CURL_EXIT_CODE="0")
        self.assertEqual(result.returncode, 0)
        self.assertEqual(len(self.sync_calls()), 1)

    def test_held_wrapper_lock_skips_sync(self):
        with (self.cache / "rclone-bisync-wrapper.lock").open("w") as lock:
            fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
            result = self.run_wrapper()
        self.assertEqual(result.returncode, 0)
        self.assertIn("already running", result.stdout)
        self.assertEqual(self.calls(), [])

    def test_lock_error_is_not_reported_as_success(self):
        self.write_command("flock", "import sys\nsys.exit(70)\n")
        result = self.run_wrapper()
        self.assertEqual(result.returncode, 70)
        self.assertEqual(self.calls(), [])

    def test_unsafe_or_unknown_arguments_are_rejected(self):
        for arg in ("--force", "--resync", "--resync-mode=newer", "--unknown"):
            with self.subTest(arg=arg):
                result = self.run_wrapper(arg)
                self.assertEqual(result.returncode, 2)
                self.assertEqual(self.calls(), [])

    def test_dry_run_argument_is_forwarded(self):
        for arg in ("--dry-run", "-n"):
            with self.subTest(arg=arg):
                result = self.run_wrapper(arg)
                self.assertEqual(result.returncode, 0)
                self.assertIn("Файли не змінено", result.stdout)
                self.assertEqual(self.sync_calls()[-1].count("--dry-run"), 1)

    def test_logging_error_is_not_reported_as_success(self):
        self.write_command(
            "tee",
            "import os, sys\n"
            "if len(sys.argv) == 4:\n"
            "    sys.stdin.read()\n"
            "    sys.exit(74)\n"
            "os.execv(os.environ['TEST_REAL_TEE'], sys.argv)\n",
        )
        result = self.run_wrapper()
        self.assertEqual(result.returncode, 1)
        self.assertNotIn("Синхронізація успішна.", result.stdout)
        self.assertEqual(len(self.sync_calls()), 1)


if __name__ == "__main__":
    unittest.main()
