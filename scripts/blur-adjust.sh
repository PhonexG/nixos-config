#!/usr/bin/env bash
set -euo pipefail

# Frosted blur step presets (Step 0..4)
BLUR_STEPS=(0 16 32 48 64)
OPACITY_STEPS=("1.00" "0.94" "0.91" "0.88" "0.82")

CURRENT_THEME_KITTY="${HOME}/.config/themes/current/kitty.conf"
RAIL_DARK_KITTY="/etc/nixos/home/themes/rail-dark/kitty.conf"
DOTFILES_KITTY="/etc/nixos/home/dotfiles/kitty/kitty.conf"
PREV_FILE="${XDG_RUNTIME_DIR:-/tmp}/blur-adjust.prev"

action="${1:-status}"

read_current_blur() {
  local val=""
  local src
  for src in "$CURRENT_THEME_KITTY" "$RAIL_DARK_KITTY" "$DOTFILES_KITTY"; do
    if [[ -f "$src" ]]; then
      val="$(awk '/^[[:space:]]*background_blur[[:space:]]+/ { val=$2 } END { print val }' "$src")"
      if [[ "$val" =~ ^[0-9]+$ ]]; then
        printf '%s\n' "$val"
        return 0
      fi
    fi
  done
  printf '48\n'
}

blur_to_step() {
  local b="${1:-48}"
  if (( b <= 0 )); then
    printf '0\n'
  elif (( b <= 16 )); then
    printf '1\n'
  elif (( b <= 32 )); then
    printf '2\n'
  elif (( b <= 48 )); then
    printf '3\n'
  else
    printf '4\n'
  fi
}

update_key_in_file() {
  local file="$1"
  local key="$2"
  local value="$3"
  [[ -f "$file" ]] || return 0
  local target
  target="$(readlink -f "$file" 2>/dev/null || printf '%s' "$file")"
  [[ -w "$target" ]] || return 0

  if grep -qE "^[[:space:]]*${key}[[:space:]]+" "$target"; then
    sed -i -E "s|^([[:space:]]*${key}[[:space:]]+).*|\1${value}|" "$target"
  else
    printf '%s %s\n' "$key" "$value" >> "$target"
  fi
}

cur_blur="$(read_current_blur)"
cur_step="$(blur_to_step "$cur_blur")"

case "$action" in
  status|--status)
    cur_opacity="${OPACITY_STEPS[$cur_step]}"
    printf 'Step %d: blur=%spx opacity=%s\n' "$cur_step" "${BLUR_STEPS[$cur_step]}" "$cur_opacity"
    exit 0
    ;;
  up|+)
    next_step=$(( cur_step < 4 ? cur_step + 1 : 4 ))
    ;;
  down|-)
    next_step=$(( cur_step > 0 ? cur_step - 1 : 0 ))
    ;;
  toggle)
    if (( cur_blur > 0 )); then
      printf '%s\n' "$cur_step" > "$PREV_FILE"
      next_step=0
    else
      saved_step=3
      if [[ -f "$PREV_FILE" ]]; then
        raw_saved="$(tr -d '[:space:]' < "$PREV_FILE" 2>/dev/null || true)"
        if [[ "$raw_saved" =~ ^[1-4]$ ]]; then
          saved_step="$raw_saved"
        fi
      fi
      next_step="$saved_step"
    fi
    ;;
  *)
    printf 'Usage: %s {up|+|down|-|toggle|status|--status}\n' "$0" >&2
    exit 2
    ;;
esac

blur="${BLUR_STEPS[$next_step]}"
opacity="${OPACITY_STEPS[$next_step]}"

# Update resolved theme kitty.conf and rail-dark kitty.conf
if [[ -e "$CURRENT_THEME_KITTY" ]]; then
  update_key_in_file "$CURRENT_THEME_KITTY" "background_opacity" "$opacity"
  update_key_in_file "$CURRENT_THEME_KITTY" "background_blur" "$blur"
fi

update_key_in_file "$RAIL_DARK_KITTY" "background_opacity" "$opacity"
update_key_in_file "$RAIL_DARK_KITTY" "background_blur" "$blur"
update_key_in_file "$DOTFILES_KITTY" "background_blur" "$blur"

# Live reload running Kitty instances
if pids="$(pidof kitty 2>/dev/null)" && [[ -n "$pids" ]]; then
  # shellcheck disable=SC2086
  kill -SIGUSR1 $pids 2>/dev/null || pkill -USR1 -x kitty 2>/dev/null || true
else
  pkill -USR1 -x kitty 2>/dev/null || true
fi

shopt -s nullglob
for sock in /tmp/kitty /tmp/kitty-*; do
  [[ -S "$sock" ]] || continue
  kitty @ --to "unix:$sock" set-background-opacity "$opacity" >/dev/null 2>&1 || true
  kitty @ --to "unix:$sock" load-config >/dev/null 2>&1 || true
done
shopt -u nullglob

# Show OSD and desktop notification
swayosd-client --custom-message "Blur: ${blur}px (opacity ${opacity})" --custom-icon "preferences-desktop-effects" >/dev/null 2>&1 || true
notify-send -h string:x-canonical-private-synchronous:blur-adjust -u low -t 1400 "Frosted Blur" "Blur: ${blur}px · Opacity: ${opacity}" >/dev/null 2>&1 || true

printf 'Step %d: blur=%spx opacity=%s\n' "$next_step" "$blur" "$opacity"
