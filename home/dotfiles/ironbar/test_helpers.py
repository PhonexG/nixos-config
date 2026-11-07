"""Run with PYTHONDONTWRITEBYTECODE=1 python3 test_helpers.py."""

import hashlib
import json
from pathlib import Path
import re
import subprocess
import tempfile
import time
import unittest
from unittest.mock import patch
import urllib.error
import tomllib

import notifications
import updates
import importlib.util
spec = importlib.util.spec_from_file_location("panel_status", Path(__file__).with_name("panel-status.py"))
panel_status = importlib.util.module_from_spec(spec)
spec.loader.exec_module(panel_status)
spec = importlib.util.spec_from_file_location("osd_watch", Path(__file__).parent.parent / "swayosd/watch.py")
osd_watch = importlib.util.module_from_spec(spec)
spec.loader.exec_module(osd_watch)


def fixture():
    return {
        "root": "root", "nodes": {
            "root": {"inputs": {"nixpkgs": "nixpkgs", "home-manager": "home-manager",
                                "pinned": "pinned", "follows": ["nixpkgs"]}},
            "nixpkgs": {"original": {"type": "github", "owner": "NixOS", "repo": "nixpkgs", "ref": "nixos-25.11"},
                        "locked": {"rev": "a" * 40}},
            "home-manager": {"original": {"type": "github", "owner": "nix-community", "repo": "home-manager"},
                             "locked": {"rev": "b" * 40}},
            "pinned": {"original": {"type": "github", "owner": "example", "repo": "example", "rev": "c" * 40},
                       "locked": {"rev": "c" * 40}},
        },
    }


class UpdateTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory(prefix="ironbar-tests-", dir="/tmp/opencode")
        self.addCleanup(self.temporary.cleanup)
        self.flake = Path(self.temporary.name) / "flake"
        self.flake.mkdir()
        self.lock = self.flake / "flake.lock"
        self.lock.write_text(json.dumps(fixture()))
        self.cache = Path(self.temporary.name) / "cache" / "updates.json"

    def test_branch_and_default_branch_and_pinned_inputs(self):
        items = updates.github_inputs(fixture())
        self.assertEqual([(item["name"], item["ref"]) for item in items],
                         [("nixpkgs", "nixos-25.11"), ("home-manager", "HEAD")])

    def test_check_is_read_only_and_counts_inputs_not_packages(self):
        before = self.lock.read_bytes()
        state = updates.check(self.flake, self.cache, lambda item: "d" * 40 if item["name"] == "nixpkgs" else item["current"])
        self.assertEqual(self.lock.read_bytes(), before)
        self.assertEqual(state["fingerprint"], hashlib.sha256(before).hexdigest())
        self.assertEqual(state["status"], "available")
        self.assertEqual(sum(item["available"] for item in state["inputs"]), 1)
        self.assertEqual(state, json.loads(self.cache.read_text()))
        self.assertEqual("", updates.render(state, updates.fingerprint(self.flake))[0])
        self.assertIn("nixpkgs: aaaaaaa → ddddddd", updates.render(state, updates.fingerprint(self.flake))[1])

    def test_all_current(self):
        state = updates.check(self.flake, self.cache, lambda item: item["current"])
        self.assertEqual(state["status"], "current")
        self.assertEqual("", updates.render(state, updates.fingerprint(self.flake))[0])

    def test_pending_update_check_has_no_indicator(self):
        self.assertEqual(updates.render({}, updates.fingerprint(self.flake))[0], "")

    def test_update_visibility_tracks_nonempty_indicator(self):
        for label, expected in [("", "false"), ("", "true")]:
            with self.subTest(label=label), patch.object(updates.subprocess, "run") as run:
                updates.publish_status(label, "details")
                self.assertEqual(run.call_args_list[0].args[0],
                                 ["ironbar", "var", "set", "updates_status", "details"])
                self.assertEqual(run.call_args_list[1].args[0],
                                 ["ironbar", "var", "set", "updates_visible", expected])

    def test_offline_is_not_reported_as_current(self):
        def offline(_item):
            raise urllib.error.URLError("offline")
        state = updates.check(self.flake, self.cache, offline)
        self.assertEqual(state["status"], "error")
        self.assertEqual(len(state["errors"]), 2)
        self.assertIn("Could not", updates.render(state, updates.fingerprint(self.flake))[1])

    def test_partial_failure_still_reports_known_update(self):
        def partial(item):
            if item["name"] == "home-manager":
                raise urllib.error.HTTPError("https://example.invalid", 429, "rate limited", {}, None)
            return "d" * 40
        state = updates.check(self.flake, self.cache, partial)
        self.assertEqual(state["status"], "available")
        self.assertEqual(len(state["errors"]), 1)
        self.assertIn("rate limit", state["errors"][0])

    def test_cache_invalidates_when_lock_changes(self):
        state = updates.check(self.flake, self.cache, lambda item: item["current"])
        self.lock.write_text(json.dumps({"root": "root", "nodes": {}}))
        self.assertTrue(updates.needs_refresh(state, self.flake))
        self.assertIn("waiting", updates.render(state, updates.fingerprint(self.flake))[1])

    def test_changed_lock_during_check_does_not_publish_stale_result(self):
        def change_lock(item):
            self.lock.write_text("{}")
            return item["current"]
        self.assertEqual(updates.check(self.flake, self.cache, change_lock), {})
        self.assertFalse(self.cache.exists())

    def test_check_interval_and_offline_retry(self):
        now = time.time()
        state = {"fingerprint": updates.fingerprint(self.flake), "checked_at": now - 3600, "errors": []}
        self.assertFalse(updates.needs_refresh(state, self.flake, now))
        state["errors"] = ["offline"]
        self.assertTrue(updates.needs_refresh(state, self.flake, now))

    def test_cancelled_apply_never_updates_or_rebuilds(self):
        with patch.object(updates, "confirm", return_value=False), patch.object(updates.subprocess, "run") as run:
            run.return_value = subprocess.CompletedProcess([], 0)
            self.assertEqual(updates.apply(self.flake, self.cache), 0)
        self.assertEqual([call.args[0][:2] for call in run.call_args_list], [["git", "status"]])

    def test_current_only_requires_confirmation_and_does_not_update_inputs(self):
        with patch.object(updates, "confirm", return_value=True), patch.object(updates.subprocess, "run") as run:
            run.return_value = subprocess.CompletedProcess([], 1)
            self.assertEqual(updates.apply(self.flake, self.cache, current_only=True), 1)
        commands = [call.args[0] for call in run.call_args_list]
        self.assertEqual(commands[1], ["sudo", "nixos-rebuild", "switch", "--flake",
                                      f"path:{self.flake}#nixos", "--no-update-lock-file"])
        self.assertFalse(any(command[:3] == ["nix", "flake", "update"] for command in commands))


class NotificationTests(unittest.TestCase):
    def test_count_and_no_count(self):
        self.assertEqual(notifications.render({"count": 0, "dnd": False})[0], "󰂚")
        label, tooltip = notifications.render({"count": 3, "dnd": False})
        self.assertEqual(label, "󰂞")
        self.assertIn("Notifications: 3", tooltip)

    def test_dnd_is_visible_even_with_no_notifications(self):
        label, tooltip = notifications.render({"count": 0, "dnd": True})
        self.assertIn("#a55555", label)
        self.assertIn("󰂛", label)
        self.assertIn("enabled", tooltip)

    def test_notification_tooltip_is_published_without_extra_notifications(self):
        with patch.object(notifications.subprocess, "run") as run:
            notifications.publish_tooltip("details")
            self.assertEqual(run.call_count, 1)
            self.assertEqual(run.call_args.args[0],
                             ["ironbar", "var", "set", "notifications_status", "details"])


class LauncherTests(unittest.TestCase):
    def test_original_fuzzel_behavior_and_dimensions_are_preserved(self):
        # Generation 62 baseline; independent of the upcoming Git history squash.
        original_hash = "f0d776b16134052bb27155f2affb6f2faa6e4bb63cd60ad3487da38c78744951"
        path = Path(__file__).parent.parent / "fuzzel/fuzzel.ini"
        self.assertEqual(hashlib.sha256(path.read_bytes()).hexdigest(), original_hash)

    def test_niri_shortcuts_use_original_fast_launcher(self):
        config = (Path(__file__).parent.parent / "niri/config.kdl").read_text()
        for key, mode in [("Mod+D", "launcher"), ("Mod+C", "clipboard"),
                          ("Mod+X", "power"), ("Mod+W", "wallpaper")]:
            self.assertIn(f'{key} {{ spawn "~/.config/niri/scripts/menu-control.sh" "{mode}"; }}', config)
        self.assertNotIn("org\\.omarchy", config)


class PanelConfigTests(unittest.TestCase):
    def setUp(self):
        self.base = Path(__file__).parent
        self.config = json.loads((self.base / "config.json").read_text())

    def test_native_hover_autohide_does_not_reserve_screen_space(self):
        self.assertEqual(self.config["autohide"], 350)
        self.assertTrue(self.config["start_hidden"])
        self.assertFalse(self.config["exclusive_zone"])
        self.assertFalse(self.config["anchor_to_edges"])
        self.assertNotIn("margin-top: -", (self.base / "style.css").read_text())
        home_config = (self.base.parents[1] / "oni.nix").read_text()
        self.assertIn("systemd.user.services.ironbar", home_config)
        self.assertIn('KillMode = "control-group"', home_config)
        self.assertNotIn("LD_PRELOAD", home_config)

    def test_requested_modules_and_battery_actions_remain_present(self):
        def walk(value):
            if isinstance(value, dict):
                yield value
                for child in value.values():
                    yield from walk(child)
            elif isinstance(value, list):
                for child in value:
                    yield from walk(child)

        widgets = {node["name"]: node for node in walk(self.config) if "type" in node and "name" in node}
        for name in ["tray", "notifications", "speaker", "battery", "wifi", "cpu"]:
            self.assertIn(name, widgets)
        self.assertEqual(widgets["battery"]["type"], "custom")
        self.assertEqual(widgets["battery-btn"]["on_click"], "popup:toggle")
        self.assertTrue(widgets["battery"]["popup"])
        self.assertEqual(widgets["wifi"]["type"], "network_manager")
        self.assertTrue(widgets["cpu"]["popup"])
        self.assertEqual(widgets["speaker"]["type"], "volume")
        self.assertIn("on_scroll_up", widgets["speaker"])
        self.assertIn("on_scroll_down", widgets["speaker"])
        self.assertEqual(widgets["speaker"]["smooth_scroll_speed"], 10)

    def test_compact_icon_only_layout_has_no_management_menu(self):
        modules = {node["name"]: node for section in ["start", "center", "end"]
                   for node in self.config[section]}
        self.assertEqual(self.config["height"], 26)
        self.assertEqual(modules["speaker"]["format"], "{icon}")
        self.assertIn("battery-status.sh --icon", modules["battery"]["bar"][0]["label"])
        self.assertEqual(modules["cpu"]["bar"][0]["label"], "󰍛")
        self.assertNotIn("updates", modules)
        self.assertEqual(modules["clock"]["format"], "%H:%M")
        self.assertNotIn("brightness", modules)
        self.assertNotIn("mic", modules)
        self.assertNotIn("menu", modules)
        self.assertFalse(modules["speaker"].get("disable_popup", False))
        self.assertNotIn("on_click_left", modules["speaker"])
        self.assertFalse(modules["bluetooth"].get("disable_popup", False))
        stylesheet = (self.base / "style.css").read_text()
        self.assertIn("#bar .bar-icon", stylesheet)
        self.assertNotIn(".bar-pill", stylesheet)
        self.assertNotIn("min-width: 48px", stylesheet)

    def test_click_only_tray_filters_duplicate_network_applets(self):
        self.assertEqual([module["name"] for module in self.config["center"]],
                          ["tray-expander", "notifications", "bluetooth", "wifi", "speaker", "cpu", "battery", "clock"])
        tray = self.config["center"][0]
        self.assertNotIn("on_mouse_enter", tray)
        self.assertNotIn("on_mouse_exit", tray)
        self.assertIn("tray-toggle", tray["bar"][0]["on_click"])
        self.assertEqual(tray["bar"][1]["transition_type"], "none")
        self.assertEqual(tray["bar"][1]["exclude"], ["nm-applet", "blueman"])
        self.assertNotIn("empty_label", tray["bar"][1])

    def test_all_controls_share_a_compact_centered_strip(self):
        self.assertEqual(self.config["start"], [])
        self.assertEqual(self.config["end"], [])
        self.assertFalse(self.config["anchor_to_edges"])
        self.assertEqual(self.config["center"][0]["bar"][1]["icon_size"], 16)
        bluetooth = next(module for module in self.config["center"] if module["name"] == "bluetooth")
        self.assertEqual(bluetooth["icon_size"], 16)
        stylesheet = (self.base / "style.css").read_text()
        self.assertIn("font-size: 16px", stylesheet)
        self.assertIn("min-width: 28px", stylesheet)
        self.assertIn("margin: 0 1px", stylesheet)
        self.assertNotIn("margin-right: 17px", stylesheet)
        self.assertNotIn("#bar button:hover,", stylesheet)

    def test_hotspot_tracks_bar_allocation_instead_of_full_screen_width(self):
        source = (self.base / "prepare-source.py").read_text()
        self.assertIn("content.connect_size_allocate", source)
        self.assertIn("autohide_hotspot_size(orientation, bar_length, limit)", source)
        self.assertIn("hotspot_window.resize(size.0, size.1)", source)
        self.assertIn("hotspot_window.connect_show(move |_|", source)
        self.assertIn("hotspot_window.connect_hide(move |_|", source)
        self.assertIn("horizontal_hotspot_matches_the_centered_strip_not_the_monitor", source)

    def test_device_lists_show_more_rows_without_widening_or_empty_stretch(self):
        wifi = (self.base / "networkmanager.rs").read_text()
        bluetooth = (self.base / "prepare-source.py").read_text()
        for source, widget in [(wifi, "scroll"), (bluetooth, "devices")]:
            self.assertIn(f"{widget}.set_max_content_height(420)", source)
            self.assertIn(f"{widget}.set_propagate_natural_height(true)", source)
        self.assertIn("scroll.set_min_content_height(80)", wifi)
        self.assertIn("devices.set_min_content_height(60)", bluetooth)
        self.assertIn("root.set_width_request(340)", wifi)
        stylesheet = (self.base / "style.css").read_text()
        self.assertIn(".popup-network_manager {\n    min-width: 340px;", stylesheet)
        self.assertIn(".popup-bluetooth {\n    min-width: 300px;", stylesheet)
        bluetooth_config = next(module for module in self.config["center"]
                                if module["name"] == "bluetooth")
        self.assertTrue(bluetooth_config["popup"]["scrollable"])

    def test_popup_focus_loss_is_scoped_to_the_current_opening(self):
        source = (self.base / "prepare-source.py").read_text()
        self.assertIn("if !win.is_visible() || !focused_since_map.get()", source)
        self.assertIn("if focus_epoch.get() != epoch || !win.is_visible()", source)
        self.assertIn("win.connect_show(move |_|", source)
        self.assertIn("focused_since_map.set(false)", source)
        self.assertIn("if win.is_visible() { focused_since_map.set(true); }", source)

    def test_workspace_indicators_are_removed(self):
        self.assertNotIn('"workspaces"', json.dumps(self.config))
        self.assertNotIn(".workspaces", (self.base / "style.css").read_text())
        self.assertEqual(self.config["start"], [])

    def test_notifications_use_one_palette_and_font(self):
        stylesheet = (self.base.parent / "swaync/style.css").read_text()
        self.assertNotIn("font-size: 14px", stylesheet)
        self.assertNotIn("font-family: sans-serif", stylesheet)

    def test_panel_and_feedback_text_are_english_without_changing_session_locale(self):
        for name in ["config.json", "networkmanager.rs", "prepare-source.py",
                     "panel-status.py", "battery-status.sh", "speaker-status.sh",
                     "wifi-status.sh", "controls.sh", "notifications.py", "updates.py"]:
            with self.subTest(file=name):
                self.assertIsNone(re.search(r"[\u0400-\u04ff]", (self.base / name).read_text()))
        self.assertIsNone(re.search(r"[\u0400-\u04ff]",
                                    (self.base.parent / "swayosd/watch.py").read_text()))
        home = (self.base.parents[1] / "oni.nix").read_text()
        self.assertIn('"LC_TIME=en_US.UTF-8"', home)
        self.assertIn('"LC_MESSAGES=en_US.UTF-8"', home)
        self.assertNotIn("home.sessionVariables", home)


class StatusTests(unittest.TestCase):
    def test_cpu_guest_time_is_not_counted_twice(self):
        with tempfile.TemporaryDirectory(dir="/tmp/opencode") as directory:
            path = Path(directory) / "stat"
            path.write_text("cpu 100 0 50 800 50 0 0 0 20 0\n")
            self.assertEqual(panel_status.cpu_counters(path), {"cpu": (1000, 850)})
        self.assertEqual(panel_status.utilization((1000, 850), (1100, 925)), 25)
        self.assertEqual(panel_status.utilization((1000, 850), (1000, 850)), 0)

    def test_battery_charge_units_and_charging_time(self):
        with tempfile.TemporaryDirectory(dir="/tmp/opencode") as directory:
            root = Path(directory)
            battery = root / "BAT0"
            battery.mkdir()
            values = {"status": "Charging", "capacity": "50", "voltage_now": "12000000",
                      "current_now": "1000000", "charge_now": "2000000",
                      "charge_full": "4000000", "charge_full_design": "5000000"}
            for name, value in values.items():
                (battery / name).write_text(value)
            result = panel_status.battery_text(root)
            self.assertIn("12.0 W", result)
            self.assertIn("Until full: 2 h 0 min", result)
            self.assertIn("48.0 Wh", result)
            self.assertIn("80%", result)


class OsdTests(unittest.TestCase):
    def test_first_audio_event_is_not_delayed_after_idle(self):
        schedule = osd_watch.AudioReadSchedule()
        schedule.queue(10.0)
        self.assertEqual(schedule.deadline, 10.0)
        schedule.complete(10.01)
        schedule.queue(11.0)
        self.assertEqual(schedule.deadline, 11.0)

    def test_rapid_audio_events_are_coalesced_without_trailing_debounce(self):
        schedule = osd_watch.AudioReadSchedule()
        schedule.complete(10.0)
        schedule.queue(10.001)
        expected = 10.0 + osd_watch.AUDIO_INTERVAL
        self.assertEqual(schedule.deadline, expected)
        for now in [10.005, 10.010, 10.019]:
            schedule.queue(now)
            self.assertEqual(schedule.deadline, expected)
        schedule.complete(expected)
        self.assertIsNone(schedule.deadline)
        schedule.queue(expected + 0.001)
        self.assertEqual(schedule.deadline, expected + osd_watch.AUDIO_INTERVAL)

    def test_feedback_is_compact_and_brightness_sampling_is_fast(self):
        self.assertLessEqual(osd_watch.BRIGHTNESS_INTERVAL, 0.04)
        self.assertEqual(osd_watch.AUDIO_INTERVAL, 0.02)
        stylesheet = (Path(__file__).parent.parent / "swayosd/style.css").read_text()
        self.assertIn("min-width: 220px", stylesheet)
        self.assertIn("margin: 5px 10px", stylesheet)
        self.assertIn("min-width: 112px", stylesheet)
        self.assertIn("min-height: 4px", stylesheet)

    def test_compact_renderer_shortens_timeout_and_icons_without_touching_controls(self):
        home_dir = Path(__file__).parents[2]
        home = (home_dir / "oni.nix").read_text()
        self.assertIn('swayosd = import ./swayosd-package.nix', home)
        self.assertIn("package = swayosd;", home)
        package = (home_dir / "swayosd-package.nix").read_text()
        self.assertIn("pkgs.swayosd.overrideAttrs", package)
        patch_text = (home_dir / "dotfiles/swayosd/swayosd-0.2.1-compact.patch").read_text()
        self.assertIn("+const ICON_SIZE: i32 = 20;", patch_text)
        self.assertIn("+\t\twindow.set_width_request(220);", patch_text)
        self.assertIn("+\t\t\tDuration::from_millis(600),", patch_text)
        removed_lines = [line for line in patch_text.splitlines()
                         if line.startswith("-") and not line.startswith("---")]
        self.assertEqual(len(removed_lines), 4)
        self.assertNotIn("set_input_region", patch_text)
        self.assertNotIn("set_keyboard_mode", patch_text)

    def test_audio_feedback_shows_volume_and_mute_without_modifying_them(self):
        self.assertEqual(osd_watch.audio_feedback((0.40, False)),
                         ("sink-volume-medium-symbolic", 0.40, "40%"))
        self.assertEqual(osd_watch.audio_feedback((0.40, True)),
                          ("sink-volume-muted-symbolic", 0.0, "Muted"))
        self.assertEqual(osd_watch.audio_feedback((0.0, False)),
                         ("sink-volume-muted-symbolic", 0.0, "0%"))

    def test_audio_state_reads_actual_wpctl_value(self):
        for stdout, expected in [("Volume: 0.40\n", (0.40, False)),
                                 ("Volume: 0.40 [MUTED]\n", (0.40, True)),
                                 ("No device found\n", None)]:
            with self.subTest(stdout=stdout), patch.object(osd_watch.subprocess, "run") as run:
                run.return_value = subprocess.CompletedProcess([], 0, stdout)
                self.assertEqual(osd_watch.audio_state(), expected)
                self.assertEqual(run.call_args.args[0],
                                 ["wpctl", "get-volume", "@DEFAULT_AUDIO_SINK@"])

    def test_brightness_reads_screen_backlight_not_keyboard_leds(self):
        with tempfile.TemporaryDirectory(dir="/tmp/opencode") as directory:
            root = Path(directory)
            device = root / "amdgpu_bl1"
            device.mkdir()
            for name, value in [("type", "raw"), ("brightness", "52"), ("max_brightness", "255")]:
                (device / name).write_text(value)
            self.assertEqual(osd_watch.backlight_device(root), device)
            self.assertEqual(osd_watch.brightness_state(device), (52, 255))
            icon, fraction, text = osd_watch.brightness_feedback((52, 255))
            self.assertEqual((icon, text), ("display-brightness-symbolic", "20%"))
            self.assertAlmostEqual(fraction, 52 / 255)

    def test_display_is_passive_and_clamps_progress(self):
        with patch.object(osd_watch.subprocess, "run") as run:
            run.return_value = subprocess.CompletedProcess([], 0, "", "")
            osd_watch.show_feedback(("sink-volume-high-symbolic", 1.2, "120%"))
            self.assertEqual(run.call_args.args[0],
                             ["swayosd-client", "--custom-icon", "sink-volume-high-symbolic",
                              "--custom-progress", "1.0000", "--custom-progress-text", "120%"])

    def test_zero_volume_or_brightness_still_dispatches_osd_progress(self):
        with patch.object(osd_watch.subprocess, "run") as run:
            run.return_value = subprocess.CompletedProcess([], 0, "", "")
            osd_watch.show_feedback(("sink-volume-muted-symbolic", 0.0, "Muted"))
            self.assertEqual(run.call_args.args[0],
                             ["swayosd-client", "--custom-icon", "sink-volume-muted-symbolic",
                               "--custom-progress", "0.0001", "--custom-progress-text", "Muted"])

    def test_only_master_audio_events_trigger_reads(self):
        self.assertIsNotNone(osd_watch.AUDIO_EVENT.search(b"Event 'change' on sink #42"))
        self.assertIsNotNone(osd_watch.AUDIO_EVENT.search(b"Event 'change' on server #4294967295"))
        self.assertIsNone(osd_watch.AUDIO_EVENT.search(b"Event 'change' on sink-input #42"))
        self.assertIsNone(osd_watch.AUDIO_EVENT.search(b"Event 'change' on source #42"))

    def test_osd_is_session_managed_and_placed_below_the_work_area(self):
        base = Path(__file__).parent
        home = (base.parents[1] / "oni.nix").read_text()
        self.assertIn("services.swayosd", home)
        self.assertIn("systemd.user.services.desktop-osd", home)
        config = tomllib.loads((base.parent / "swayosd/config.toml").read_text())
        self.assertEqual(config["server"]["top_margin"], 0.85)
        self.assertEqual(config["server"]["max_volume"], 100)
        self.assertTrue(config["server"]["show_percentage"])

    def test_osd_unit_uses_only_the_stylesheet_store_path(self):
        home = (Path(__file__).parents[2] / "oni.nix").read_text()
        self.assertIn('stylePath = "${./dotfiles/swayosd/style.css}";', home)
        self.assertNotIn("force = true", home)


if __name__ == "__main__":
    unittest.main(verbosity=2)
