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
    ironbar var set tray_arrow '' >/dev/null
  else
    ironbar var set tray_open true >/dev/null
    ironbar var set tray_arrow '' >/dev/null
  fi
  exit 0
fi

close_popup
case "$action" in
  bar-toggle) exec ironbar bar main toggle-visible ;;
  launcher|clipboard|wallpaper|power) exec "$session_scripts/menu-control.sh" "$action" ;;
  terminal) exec niri msg action spawn -- kitty ;;
  files) exec niri msg action spawn -- thunar ;;
  wifi) exec ironbar bar main show-popup wifi ;;
  bluetooth) exec ironbar bar main show-popup bluetooth ;;
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
