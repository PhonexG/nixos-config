#!/usr/bin/env bash
set -euo pipefail

base="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
session_scripts="$HOME/.config/niri/scripts"
action="${1:-}"

close_popup() {
  ironbar bar main hide-popup >/dev/null 2>&1 || true
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
    exit 0
    ;;
  wifi-summary)
    radio="$(nmcli radio wifi 2>/dev/null || true)"
    devs="$(nmcli -t -f TYPE,STATE,CONNECTION device status 2>/dev/null || true)"
    wifi_conn="$(awk -F: '($1=="802-11-wireless" || $1=="wifi") && $2=="connected" {print $3; exit}' <<<"$devs")"
    eth_conn="$(awk -F: '($1=="802-3-ethernet" || $1=="ethernet") && $2=="connected" {print $3; exit}' <<<"$devs")"
    if [[ "$radio" == "disabled" && -z "$eth_conn" ]]; then
      printf 'Wi-Fi: Disabled\nLeft click: Network Manager · Right click: nmtui\n'
    elif [[ -n "$wifi_conn" && -n "$eth_conn" ]]; then
      printf 'Wi-Fi: %s (connected) · Ethernet: %s\nLeft click: Network Manager · Right click: nmtui\n' "$wifi_conn" "$eth_conn"
    elif [[ -n "$wifi_conn" ]]; then
      printf 'Wi-Fi: %s (connected)\nLeft click: Network Manager · Right click: nmtui\n' "$wifi_conn"
    elif [[ -n "$eth_conn" ]]; then
      printf 'Ethernet: %s (connected)\nLeft click: Network Manager · Right click: nmtui\n' "$eth_conn"
    else
      printf 'Network: Disconnected\nLeft click: Network Manager · Right click: nmtui\n'
    fi
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
    exit 0
    ;;
  bluetooth-summary)
    bt_show="$(bluetoothctl show 2>/dev/null || true)"
    if ! grep -Fq 'Powered: yes' <<<"$bt_show"; then
      printf 'Bluetooth: Off\nLeft click: Blueman Manager\n'
    else
      bt_devs="$(bluetoothctl devices Connected 2>/dev/null | sed -n 's/^Device [^ ]* //p' | paste -sd ', ' - || true)"
      if [[ -n "$bt_devs" ]]; then
        printf 'Bluetooth: %s (connected)\nLeft click: Blueman Manager\n' "$bt_devs"
      else
        printf 'Bluetooth: On (no devices connected)\nLeft click: Blueman Manager\n'
      fi
    fi
    exit 0
    ;;
esac

close_popup
case "$action" in
  bar-toggle) exec ironbar bar main toggle-visible ;;
  launcher|clipboard|wallpaper|theme|power) exec "$session_scripts/menu-control.sh" "$action" ;;
  terminal) exec niri msg action spawn -- kitty ;;
  files) exec niri msg action spawn -- thunar ;;
  wifi)
    if command -v nm-connection-editor >/dev/null 2>&1; then
      exec niri msg action spawn -- nm-connection-editor
    else
      exec niri msg action spawn -- kitty --class nmtui-float -e nmtui
    fi
    ;;
  wifi-tui) exec niri msg action spawn -- kitty --class nmtui-float -e nmtui ;;
  bluetooth) exec niri msg action spawn -- blueman-manager ;;
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
