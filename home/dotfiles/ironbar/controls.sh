#!/usr/bin/env bash
set -euo pipefail

base="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
session_scripts="$HOME/.config/niri/scripts"
runtime_dir="${XDG_RUNTIME_DIR:-/tmp}"
wifi_slots_file="$runtime_dir/ironbar-wifi-slots.json"
bt_slots_file="$runtime_dir/ironbar-bt-slots.json"
action="${1:-}"

close_popup() {
  ironbar bar main hide-popup >/dev/null 2>&1 || true
}

run_popup_helper() {
  command -v python3 >/dev/null 2>&1 || return 0
  WIFI_SLOTS_FILE="$wifi_slots_file" BT_SLOTS_FILE="$bt_slots_file" python3 - "$@" <<'PY'
import html
import json
import os
import shutil
import subprocess
import sys
import tempfile
import time


def truncate_name(name, limit=20):
    if len(name) <= limit:
        return name
    return name[: limit - 1] + "…"


def pango_escape(text):
    return html.escape(text, quote=True)


def run_cmd(cmd, timeout=5):
    try:
        return subprocess.run(
            cmd,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            encoding="utf-8",
            timeout=timeout,
            check=False,
        )
    except (OSError, subprocess.TimeoutExpired):
        return None


def write_json_atomic(path, data):
    parent = os.path.dirname(path) or "/tmp"
    os.makedirs(parent, exist_ok=True)
    fd, tmp_path = tempfile.mkstemp(prefix=".ironbar-", suffix=".tmp", dir=parent)
    try:
        with os.fdopen(fd, "w", encoding="utf-8") as fh:
            json.dump(data, fh, ensure_ascii=False)
        os.replace(tmp_path, path)
    except OSError:
        try:
            os.unlink(tmp_path)
        except OSError:
            pass


def read_json(path):
    try:
        with open(path, "r", encoding="utf-8") as fh:
            return json.load(fh)
    except (OSError, ValueError):
        return {}


def apply_ironvars(ordered_pairs, prefix):
    existing = {}
    res = run_cmd(["ironbar", "-f", "json", "var", "list"], timeout=2)
    if res is not None and res.returncode == 0 and res.stdout.strip():
        try:
            raw = json.loads(res.stdout).get("value", "")
            for line in raw.splitlines():
                if line.startswith(prefix) and ": " in line:
                    k, v = line.split(": ", 1)
                    existing[k] = v
        except (ValueError, AttributeError):
            existing = {}

    for key, val in ordered_pairs:
        if existing.get(key) != val:
            run_cmd(["ironbar", "var", "set", key, val], timeout=2)


def set_var(key, val):
    run_cmd(["ironbar", "var", "set", key, val], timeout=2)


def split_nmcli_terse(line):
    fields = []
    buf = []
    i = 0
    n = len(line)
    while i < n:
        ch = line[i]
        if ch == "\\" and i + 1 < n:
            buf.append(line[i + 1])
            i += 2
        elif ch == ":":
            fields.append("".join(buf))
            buf = []
            i += 1
        else:
            buf.append(ch)
            i += 1
    fields.append("".join(buf))
    return fields


def sync_wifi_vars():
    slots_file = os.environ["WIFI_SLOTS_FILE"]
    if not shutil.which("nmcli"):
        pairs = [
            ("wifi_toggle_label", "Off"),
            ("wifi_status_msg", "NetworkManager unavailable"),
            ("wifi_status_show", "true"),
        ]
        for idx in range(1, 7):
            pairs.append((f"wifi_item_{idx}_show", "false"))
            pairs.append((f"wifi_item_{idx}_label", ""))
        write_json_atomic(slots_file, {})
        apply_ironvars(pairs, "wifi_")
        return

    radio_res = run_cmd(["nmcli", "radio", "wifi"], timeout=3)
    radio = radio_res.stdout.strip() if radio_res and radio_res.returncode == 0 else ""

    if radio == "disabled":
        pairs = [
            ("wifi_toggle_label", "Off"),
            ("wifi_status_msg", "Wi-Fi is turned off"),
            ("wifi_status_show", "true"),
        ]
        for idx in range(1, 7):
            pairs.append((f"wifi_item_{idx}_show", "false"))
            pairs.append((f"wifi_item_{idx}_label", ""))
        write_json_atomic(slots_file, {})
        apply_ironvars(pairs, "wifi_")
        return

    list_res = run_cmd(
        ["nmcli", "-t", "-f", "IN-USE,SSID,SECURITY,SIGNAL,BARS", "dev", "wifi", "list", "--rescan", "no"],
        timeout=4,
    )
    networks = {}
    if list_res and list_res.returncode == 0:
        for raw_line in list_res.stdout.splitlines():
            if not raw_line:
                continue
            parts = split_nmcli_terse(raw_line)
            if len(parts) < 4:
                continue
            in_use_raw, ssid, security, sig_raw = parts[0], parts[1], parts[2], parts[3]
            if not ssid or not ssid.strip():
                continue
            in_use = in_use_raw.strip() == "*"
            try:
                signal = int(sig_raw.strip())
            except ValueError:
                signal = 0
            prev = networks.get(ssid)
            if prev is None:
                networks[ssid] = {
                    "ssid": ssid,
                    "in_use": in_use,
                    "security": security.strip(),
                    "signal": signal,
                }
            else:
                if in_use:
                    prev["in_use"] = True
                if signal > prev["signal"]:
                    prev["signal"] = signal
                    if security.strip():
                        prev["security"] = security.strip()

    sorted_nets = sorted(
        networks.values(),
        key=lambda item: (1 if item["in_use"] else 0, item["signal"]),
        reverse=True,
    )[:6]

    pairs = [("wifi_toggle_label", "On")]
    slots = {}
    if not sorted_nets:
        pairs.append(("wifi_status_msg", "No Wi-Fi networks found"))
        pairs.append(("wifi_status_show", "true"))
    else:
        pairs.append(("wifi_status_show", "false"))
        pairs.append(("wifi_status_msg", ""))

    for idx in range(1, 7):
        if idx <= len(sorted_nets):
            net = sorted_nets[idx - 1]
            sig = net["signal"]
            sig_icon = "󰤨" if sig >= 75 else "󰤥" if sig >= 50 else "󰤢" if sig >= 25 else "󰤟"
            short = pango_escape(truncate_name(net["ssid"], 20))
            sec = net["security"]
            lock = '  <span foreground="#8b95a7">󰌾</span>' if sec and sec != "--" else ""
            if net["in_use"]:
                label = f'<span foreground="#88a4d4">{sig_icon}</span>  <b>{short}</b>  <span foreground="#a3be8c">●</span>'
            else:
                label = f'<span foreground="#8b95a7">{sig_icon}</span>  {short}{lock}'
            pairs.append((f"wifi_item_{idx}_label", label))
            pairs.append((f"wifi_item_{idx}_show", "true"))
            slots[str(idx)] = {"ssid": net["ssid"], "in_use": net["in_use"]}
        else:
            pairs.append((f"wifi_item_{idx}_show", "false"))
            pairs.append((f"wifi_item_{idx}_label", ""))

    write_json_atomic(slots_file, slots)
    apply_ironvars(pairs, "wifi_")


def wifi_toggle_power():
    if not shutil.which("nmcli"):
        sync_wifi_vars()
        return
    radio_res = run_cmd(["nmcli", "radio", "wifi"], timeout=3)
    radio = radio_res.stdout.strip() if radio_res and radio_res.returncode == 0 else ""
    if radio == "enabled":
        run_cmd(["nmcli", "radio", "wifi", "off"], timeout=5)
    else:
        run_cmd(["nmcli", "radio", "wifi", "on"], timeout=5)
        time.sleep(0.3)
    sync_wifi_vars()


def wifi_refresh():
    if not shutil.which("nmcli"):
        sync_wifi_vars()
        return
    radio_res = run_cmd(["nmcli", "radio", "wifi"], timeout=3)
    radio = radio_res.stdout.strip() if radio_res and radio_res.returncode == 0 else ""
    if radio == "disabled":
        sync_wifi_vars()
        return
    set_var("wifi_status_msg", "Scanning networks…")
    set_var("wifi_status_show", "true")
    res = run_cmd(["nmcli", "dev", "wifi", "list", "--rescan", "yes"], timeout=8)
    if res is None or res.returncode != 0:
        run_cmd(["nmcli", "dev", "wifi", "rescan"], timeout=4)
        time.sleep(0.4)
    sync_wifi_vars()


def wifi_connect(idx_str):
    if idx_str not in {"1", "2", "3", "4", "5", "6"}:
        return
    slots = read_json(os.environ["WIFI_SLOTS_FILE"])
    entry = slots.get(idx_str)
    if not entry or not entry.get("ssid"):
        sync_wifi_vars()
        return
    ssid = entry["ssid"]
    if entry.get("in_use"):
        sync_wifi_vars()
        return

    short = truncate_name(ssid, 18)
    set_var("wifi_status_msg", f"Connecting to {short}…")
    set_var("wifi_status_show", "true")
    res = run_cmd(["nmcli", "dev", "wifi", "connect", ssid], timeout=20)
    if res is None or res.returncode != 0:
        err = (res.stderr.strip() if res and res.stderr else "Connection failed")
        if shutil.which("notify-send"):
            run_cmd(["notify-send", "Wi-Fi", f"{short}: {err}"], timeout=3)
        if "Secrets were required" in err:
            sync_wifi_vars()
            run_cmd(["ironbar", "bar", "main", "hide-popup"], timeout=2)
            if shutil.which("nm-connection-editor"):
                subprocess.Popen(["niri", "msg", "action", "spawn", "--", "nm-connection-editor"])
            else:
                subprocess.Popen(["niri", "msg", "action", "spawn", "--", "kitty", "--class", "nmtui-float", "-e", "nmtui"])
            return
    sync_wifi_vars()


def parse_bluetooth_devices(output):
    devices = []
    for line in output.splitlines():
        if line.startswith("Device "):
            rest = line[len("Device "):]
            parts = rest.split(" ", 1)
            mac = parts[0].strip()
            name = parts[1].strip() if len(parts) > 1 else mac
            if mac:
                devices.append((mac, name or mac))
    return devices


def sync_bt_vars():
    slots_file = os.environ["BT_SLOTS_FILE"]
    if not shutil.which("bluetoothctl"):
        pairs = [
            ("bt_toggle_label", "Off"),
            ("bt_status_msg", "Bluetooth unavailable"),
            ("bt_status_show", "true"),
        ]
        for idx in range(1, 7):
            pairs.append((f"bt_item_{idx}_show", "false"))
            pairs.append((f"bt_item_{idx}_label", ""))
        write_json_atomic(slots_file, {})
        apply_ironvars(pairs, "bt_")
        return

    show_res = run_cmd(["bluetoothctl", "show"], timeout=3)
    bt_show = show_res.stdout if show_res and show_res.returncode == 0 else ""
    if "Controller " not in bt_show:
        pairs = [
            ("bt_toggle_label", "Off"),
            ("bt_status_msg", "No Bluetooth adapter found"),
            ("bt_status_show", "true"),
        ]
        for idx in range(1, 7):
            pairs.append((f"bt_item_{idx}_show", "false"))
            pairs.append((f"bt_item_{idx}_label", ""))
        write_json_atomic(slots_file, {})
        apply_ironvars(pairs, "bt_")
        return

    if "Powered: yes" not in bt_show:
        pairs = [
            ("bt_toggle_label", "Off"),
            ("bt_status_msg", "Bluetooth is turned off"),
            ("bt_status_show", "true"),
        ]
        for idx in range(1, 7):
            pairs.append((f"bt_item_{idx}_show", "false"))
            pairs.append((f"bt_item_{idx}_label", ""))
        write_json_atomic(slots_file, {})
        apply_ironvars(pairs, "bt_")
        return

    paired_res = run_cmd(["bluetoothctl", "devices", "Paired"], timeout=3)
    if paired_res is None or paired_res.returncode != 0:
        paired_res = run_cmd(["bluetoothctl", "paired-devices"], timeout=3)
    paired = parse_bluetooth_devices(paired_res.stdout if paired_res and paired_res.returncode == 0 else "")

    conn_res = run_cmd(["bluetoothctl", "devices", "Connected"], timeout=3)
    connected_macs = {
        mac for mac, _ in parse_bluetooth_devices(conn_res.stdout if conn_res and conn_res.returncode == 0 else "")
    }

    items = [
        {"mac": mac, "name": name, "connected": mac in connected_macs}
        for mac, name in paired
    ]
    items.sort(key=lambda item: (0 if item["connected"] else 1, item["name"].lower()))
    items = items[:6]

    pairs = [("bt_toggle_label", "On")]
    slots = {}
    if not items:
        pairs.append(("bt_status_msg", "No paired devices"))
        pairs.append(("bt_status_show", "true"))
    else:
        pairs.append(("bt_status_show", "false"))
        pairs.append(("bt_status_msg", ""))

    for idx in range(1, 7):
        if idx <= len(items):
            dev = items[idx - 1]
            short = pango_escape(truncate_name(dev["name"], 20))
            if dev["connected"]:
                label = f'<span foreground="#88a4d4">󰂱</span>  <b>{short}</b>  <span foreground="#a3be8c">●</span>'
            else:
                label = f'<span foreground="#8b95a7">󰂯</span>  {short}'
            pairs.append((f"bt_item_{idx}_label", label))
            pairs.append((f"bt_item_{idx}_show", "true"))
            slots[str(idx)] = {
                "mac": dev["mac"],
                "name": dev["name"],
                "connected": dev["connected"],
            }
        else:
            pairs.append((f"bt_item_{idx}_show", "false"))
            pairs.append((f"bt_item_{idx}_label", ""))

    write_json_atomic(slots_file, slots)
    apply_ironvars(pairs, "bt_")


def bt_toggle_power():
    if not shutil.which("bluetoothctl"):
        sync_bt_vars()
        return
    show_res = run_cmd(["bluetoothctl", "show"], timeout=3)
    bt_show = show_res.stdout if show_res and show_res.returncode == 0 else ""
    if "Powered: yes" in bt_show:
        run_cmd(["bluetoothctl", "power", "off"], timeout=4)
    else:
        run_cmd(["bluetoothctl", "power", "on"], timeout=4)
    time.sleep(0.2)
    sync_bt_vars()


def bt_device_toggle(idx_str):
    if idx_str not in {"1", "2", "3", "4", "5", "6"}:
        return
    slots = read_json(os.environ["BT_SLOTS_FILE"])
    entry = slots.get(idx_str)
    if not entry or not entry.get("mac"):
        sync_bt_vars()
        return
    mac = entry["mac"]
    name = entry.get("name") or mac
    short = truncate_name(name, 16)

    conn_res = run_cmd(["bluetoothctl", "devices", "Connected"], timeout=3)
    connected_macs = {
        m for m, _ in parse_bluetooth_devices(conn_res.stdout if conn_res and conn_res.returncode == 0 else "")
    }
    currently_connected = mac in connected_macs

    if currently_connected:
        set_var("bt_status_msg", f"Disconnecting {short}…")
        set_var("bt_status_show", "true")
        res = run_cmd(["bluetoothctl", "disconnect", mac], timeout=10)
    else:
        set_var("bt_status_msg", f"Connecting {short}…")
        set_var("bt_status_show", "true")
        res = run_cmd(["bluetoothctl", "connect", mac], timeout=12)

    if res is None or res.returncode != 0:
        if shutil.which("notify-send"):
            verb = "disconnect from" if currently_connected else "connect to"
            run_cmd(["notify-send", "Bluetooth", f"Failed to {verb} {short}"], timeout=3)
    sync_bt_vars()


cmd = sys.argv[1] if len(sys.argv) > 1 else ""
arg = sys.argv[2] if len(sys.argv) > 2 else ""

if cmd == "wifi-sync":
    sync_wifi_vars()
elif cmd == "wifi-toggle-power":
    wifi_toggle_power()
elif cmd == "wifi-refresh":
    wifi_refresh()
elif cmd == "wifi-connect":
    wifi_connect(arg)
elif cmd == "bt-sync":
    sync_bt_vars()
elif cmd == "bt-toggle-power":
    bt_toggle_power()
elif cmd == "bt-device-toggle":
    bt_device_toggle(arg)
PY
}

# A click-only drawer cannot change size under a merely hovering pointer.
if [[ "$action" == tray-toggle ]]; then
  state="$(ironbar var get tray_open 2>/dev/null || true)"
  if [[ "$state" == true ]]; then
    ironbar var set tray_open false >/dev/null
    ironbar var set tray_arrow '󰅀' >/dev/null
  else
    ironbar var set tray_open true >/dev/null
    ironbar var set tray_arrow '󰅃' >/dev/null
  fi
  exit 0
fi

case "$action" in
  wifi-icon)
    radio="$(nmcli radio wifi 2>/dev/null || true)"
    devs="$(nmcli -t -f TYPE,STATE,CONNECTION device status 2>/dev/null || true)"
    if [[ "$radio" == "disabled" ]]; then
      printf '<span foreground="#8b95a7">󰤮</span>\n'
    elif grep -Eq '^(802-11-wireless|wifi):connected:' <<<"$devs"; then
      printf '󰤨\n'
    elif grep -Eq '^(802-3-ethernet|ethernet):connected:' <<<"$devs"; then
      printf '󰈀\n'
    else
      printf '<span foreground="#8b95a7">󰤯</span>\n'
    fi
    run_popup_helper wifi-sync >/dev/null 2>&1 || true
    exit 0
    ;;
  wifi-summary)
    radio="$(nmcli radio wifi 2>/dev/null || true)"
    devs="$(nmcli -t -f TYPE,STATE,CONNECTION device status 2>/dev/null || true)"
    wifi_conn="$(awk -F: '($1=="802-11-wireless" || $1=="wifi") && $2=="connected" {print $3; exit}' <<<"$devs")"
    eth_conn="$(awk -F: '($1=="802-3-ethernet" || $1=="ethernet") && $2=="connected" {print $3; exit}' <<<"$devs")"
    if [[ "$radio" == "disabled" && -z "$eth_conn" ]]; then
      printf 'Wi-Fi: Disabled\nLeft click: Wi-Fi popup · Right click: toggle Wi-Fi\n'
    elif [[ -n "$wifi_conn" && -n "$eth_conn" ]]; then
      printf 'Wi-Fi: %s (connected) · Ethernet: %s\nLeft click: Wi-Fi popup · Right click: toggle Wi-Fi\n' "$wifi_conn" "$eth_conn"
    elif [[ -n "$wifi_conn" ]]; then
      printf 'Wi-Fi: %s (connected)\nLeft click: Wi-Fi popup · Right click: toggle Wi-Fi\n' "$wifi_conn"
    elif [[ -n "$eth_conn" ]]; then
      printf 'Ethernet: %s (connected)\nLeft click: Wi-Fi popup · Right click: toggle Wi-Fi\n' "$eth_conn"
    else
      printf 'Network: Disconnected\nLeft click: Wi-Fi popup · Right click: toggle Wi-Fi\n'
    fi
    exit 0
    ;;
  wifi-sync|wifi-toggle-power|wifi-refresh|wifi-connect)
    run_popup_helper "$action" "${2:-}" >/dev/null
    exit 0
    ;;
  bluetooth-icon)
    bt_show="$(bluetoothctl show 2>/dev/null || true)"
    if ! grep -Fq 'Powered: yes' <<<"$bt_show"; then
      printf '<span foreground="#8b95a7">󰂲</span>\n'
    else
      bt_devs="$(bluetoothctl devices Connected 2>/dev/null || true)"
      if grep -Fq 'Device ' <<<"$bt_devs"; then
        printf '<span foreground="#88a4d4">󰂱</span>\n'
      else
        printf '󰂯\n'
      fi
    fi
    run_popup_helper bt-sync >/dev/null 2>&1 || true
    exit 0
    ;;
  bluetooth-summary)
    bt_show="$(bluetoothctl show 2>/dev/null || true)"
    if ! grep -Fq 'Powered: yes' <<<"$bt_show"; then
      printf 'Bluetooth: Off\nLeft click: Bluetooth popup · Right click: toggle Bluetooth\n'
    else
      bt_devs="$(bluetoothctl devices Connected 2>/dev/null | sed -n 's/^Device [^ ]* //p' | paste -sd ', ' - || true)"
      if [[ -n "$bt_devs" ]]; then
        printf 'Bluetooth: %s (connected)\nLeft click: Bluetooth popup · Right click: toggle Bluetooth\n' "$bt_devs"
      else
        printf 'Bluetooth: On (no devices connected)\nLeft click: Bluetooth popup · Right click: toggle Bluetooth\n'
      fi
    fi
    exit 0
    ;;
  bt-sync|bt-toggle-power|bt-device-toggle)
    run_popup_helper "$action" "${2:-}" >/dev/null
    exit 0
    ;;
esac

close_popup
case "$action" in
  bar-toggle) exec ironbar bar main toggle-visible ;;
  launcher|clipboard|wallpaper|theme|power) exec "$session_scripts/menu-control.sh" "$action" ;;
  terminal) exec niri msg action spawn -- kitty ;;
  files) exec niri msg action spawn -- thunar ;;
  wifi|wifi-advanced)
    if command -v nm-connection-editor >/dev/null 2>&1; then
      exec niri msg action spawn -- nm-connection-editor
    else
      exec niri msg action spawn -- kitty --class nmtui-float -e nmtui
    fi
    ;;
  wifi-tui) exec niri msg action spawn -- kitty --class nmtui-float -e nmtui ;;
  bluetooth|bluetooth-advanced) exec niri msg action spawn -- blueman-manager ;;
  audio) exec ironbar bar main show-popup speaker ;;
  monitor) exec ironbar bar main show-popup cpu ;;
  notifications) exec swaync-client --toggle-panel ;;
  dnd) exec swaync-client --toggle-dnd ;;
  battery-info)
    summary="$("$base/battery-status.sh" --summary)"
    exec notify-send --urgency=low 'Battery' "$summary"
    ;;
  *)
    printf 'Unknown Ironbar action: %s\n' "$action" >&2
    exit 2
    ;;
esac
