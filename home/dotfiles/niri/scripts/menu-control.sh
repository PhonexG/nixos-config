#!/usr/bin/env bash
set -euo pipefail

mode="${1:-launcher}"
user="${USER:-$(id -un)}"
style="$HOME/.config/wofi/style.css"
conf="$HOME/.config/wofi/config"
state_file="${XDG_RUNTIME_DIR:-/tmp}/wofi-${user}.mode"

is_wofi_running() {
  pkill -0 -u "$user" -x .wofi-wrapped 2>/dev/null || pkill -0 -u "$user" -x wofi 2>/dev/null
}

kill_wofi() {
  pkill -u "$user" -x .wofi-wrapped 2>/dev/null || true
  pkill -u "$user" -x wofi 2>/dev/null || true
}

# If an instance of wofi is already running
if is_wofi_running; then
  current_mode=""
  [[ -f "$state_file" ]] && current_mode="$(< "$state_file" 2>/dev/null || true)"

  # Kill previous instance immediately
  kill_wofi

  # Wait up to 250ms for process to exit cleanly
  for _ in {1..25}; do
    is_wofi_running || break
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
  wofi --show drun --conf "$conf" --style "$style" --allow-images --width 720 --height 500
}

run_power() {
  local choice answer
  choice="$(printf '%s\n' \
    '  Lock' \
    '󰍃  Logout' \
    '󰤄  Suspend' \
    '󰜉  Reboot' \
    '  Shutdown' \
    | wofi --dmenu --prompt 'Power Control' --width 520 --height 390 --conf "$conf" --style "$style" || true)"

  confirm() {
    local action="$1"
    answer="$(printf 'No\nYes\n' | wofi --dmenu --prompt "Confirm $action" --width 420 --height 190 --conf "$conf" --style "$style" || true)"
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
    printf 'img:%s:text:%s\n' "$wall" "$base"
  done | sort -u)"

  [[ -n "$list" ]] || { notify-send 'Wallpaper' 'No wallpaper images found' || true; exit 0; }
  choice="$(printf '%s\n' "$list" | wofi --dmenu --allow-images --prompt 'Wallpaper' --width 920 --height 620 --conf "$conf" --style "$style" || true)"
  [[ -n "${choice:-}" ]] || exit 0

  if [[ "$choice" =~ ^img:(.+):text: ]]; then
    wall="${BASH_REMATCH[1]}"
  else
    wall="${choice#img:}"
    wall="${wall%:text:*}"
  fi

  [[ -n "${wall:-}" && -f "$wall" ]] || { notify-send 'Wallpaper' 'Could not resolve selected wallpaper' || true; exit 1; }
  "$HOME/.config/niri/scripts/apply-wallpaper.sh" "$wall"
}

run_clipboard() {
  local choice
  choice="$( (echo "󰃢  [Очистити всю історію буфера]"; cliphist list 2>/dev/null | head -n 100) | wofi --dmenu \
    --prompt "Clipboard" \
    --width 720 \
    --height 450 \
    --conf "$conf" \
    --style "$style" 2>/dev/null || true)"

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
