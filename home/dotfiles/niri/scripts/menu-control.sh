#!/usr/bin/env bash
set -euo pipefail

mode="${1:-launcher}"
user="${USER:-$(id -un)}"
state_file="${XDG_RUNTIME_DIR:-/tmp}/fuzzel-${user}.mode"

is_fuzzel_running() {
  pkill -0 -u "$user" -x fuzzel 2>/dev/null
}

kill_fuzzel() {
  pkill -u "$user" -x fuzzel 2>/dev/null || true
}

# If an instance of fuzzel is already running
if is_fuzzel_running; then
  current_mode=""
  [[ -f "$state_file" ]] && current_mode="$(< "$state_file" 2>/dev/null || true)"

  # Kill previous instance immediately
  kill_fuzzel

  # Wait up to 250ms for process to exit cleanly
  for _ in {1..25}; do
    is_fuzzel_running || break
    sleep 0.01
  done

  # If triggered with the exact same mode, toggle it off
  if [[ -n "$current_mode" && "$current_mode" == "$mode" ]]; then
    rm -f "$state_file" 2>/dev/null || true
    exit 0
  fi
fi

# Track the new active mode
echo "$mode" > "$state_file"
trap 'rm -f "$state_file" 2>/dev/null || true' EXIT INT TERM

run_launcher() {
  fuzzel
}

run_power() {
  local choice answer
  choice="$(printf '%s\n' \
    '  Lock' \
    '󰍃  Logout' \
    '󰤄  Suspend' \
    '󰜉  Reboot' \
    '  Shutdown' \
    | fuzzel --dmenu --prompt 'Power  ' --width 28 --lines 5 || true)"

  confirm() {
    local action="$1"
    answer="$(printf 'No\nYes\n' | fuzzel --dmenu --prompt "Confirm $action  " --width 26 --lines 2 || true)"
    [[ "$answer" == "Yes" ]]
  }

  case "$choice" in
    '  Lock') "$HOME/.config/niri/scripts/lock.sh" ;;
    '󰍃  Logout') confirm 'Logout' && niri msg action quit ;;
    '󰤄  Suspend') confirm 'Suspend' && "$HOME/.config/niri/scripts/suspend.sh" ;;
    '󰜉  Reboot') confirm 'Reboot' && systemctl reboot ;;
    '  Shutdown') confirm 'Shutdown' && systemctl poweroff ;;
  esac
}

run_wallpaper() {
  local dirs=()
  for dir in "$HOME/Pictures/wallpapers" "$HOME/Pictures/Wallpapers" "$HOME/.config/niri/wallpapers"; do
    [[ -d "$dir" ]] && dirs+=("$dir")
  done

  (( ${#dirs[@]} > 0 )) || { notify-send 'Wallpaper' 'Put images into ~/Pictures/wallpapers' || true; exit 0; }

  local list choice wall base
  list="$(find "${dirs[@]}" -maxdepth 1 -type f \( -iname '*.jpg' -o -iname '*.jpeg' -o -iname '*.png' -o -iname '*.webp' \) 2>/dev/null | while IFS= read -r wall; do
    base="${wall##*/}"
    case "$base" in current|selected-wallpaper*) continue ;; esac
    printf '%s\n' "$base"
  done | sort -u)"

  [[ -n "$list" ]] || { notify-send 'Wallpaper' 'No wallpaper images found' || true; exit 0; }
  choice="$(printf '%s\n' "$list" | fuzzel --dmenu --prompt 'Wallpaper  ' || true)"
  [[ -n "${choice:-}" ]] || exit 0

  wall=""
  for dir in "${dirs[@]}"; do
    [[ -f "$dir/$choice" ]] && { wall="$dir/$choice"; break; }
  done

  [[ -n "${wall:-}" && -f "$wall" ]] || { notify-send 'Wallpaper' 'Could not resolve selected wallpaper' || true; exit 1; }
  "$HOME/.config/niri/scripts/apply-wallpaper.sh" "$wall"
}

run_clipboard() {
  local choice
  choice="$( (echo "󰃢  [Очистити всю історію буфера]"; cliphist list 2>/dev/null | head -n 100) | fuzzel --dmenu \
    --prompt "Clipboard  " \
    --width 55 2>/dev/null || true)"

  [[ -n "${choice:-}" ]] || exit 0

  if [[ "$choice" == *"Очистити всю історію"* ]]; then
    cliphist wipe
    rm -f "${XDG_CACHE_HOME:-$HOME/.cache}/cliphist/db"
    wl-copy --clear
    notify-send "Clipboard" "Історію буфера очищено" || true
    exit 0
  fi

  printf '%s' "$choice" | cliphist decode | wl-copy
  notify-send "Clipboard" "Copied to clipboard" || true
}

case "$mode" in
  launcher|apps|drun) run_launcher ;;
  power) run_power ;;
  wallpaper|wall) run_wallpaper ;;
  clipboard|clip) run_clipboard ;;
  *) notify-send 'Menu' "Unknown mode: $mode" || true; exit 1 ;;
esac
