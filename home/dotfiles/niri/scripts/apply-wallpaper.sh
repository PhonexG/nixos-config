#!/usr/bin/env bash
set -euo pipefail

INPUT_WALL="${1:-}"
BASE="$HOME/.config/niri"
WALL_DIR="$BASE/wallpapers"
CACHE_DIR="$HOME/.cache/niri"
CURRENT_WALL="$WALL_DIR/current"
SELECTED_PREFIX="$WALL_DIR/selected-wallpaper"
DEFAULT_WALL="$WALL_DIR/default.png"

mkdir -p "$CACHE_DIR" "$WALL_DIR"

if [[ -n "$INPUT_WALL" ]]; then
  # Expand tilde and get absolute path
  INPUT_WALL="${INPUT_WALL/#\~/$HOME}"
  if [[ -f "$INPUT_WALL" ]]; then
    INPUT_WALL="$(readlink -f "$INPUT_WALL" 2>/dev/null || realpath "$INPUT_WALL" 2>/dev/null || echo "$INPUT_WALL")"
  else
    notify-send "Wallpaper" "File not found: $INPUT_WALL" || true
    exit 1
  fi
  ext=".${INPUT_WALL##*.}"
  ext="$(printf '%s' "$ext" | tr '[:upper:]' '[:lower:]')"
  SAVED_WALL="${SELECTED_PREFIX}${ext}"
  cp -f -- "$INPUT_WALL" "$SAVED_WALL"
  ln -sfn "$SAVED_WALL" "$CURRENT_WALL"
  WALL="$SAVED_WALL"
elif [[ -e "$CURRENT_WALL" ]]; then
  WALL="$(readlink -f "$CURRENT_WALL" 2>/dev/null || echo "$CURRENT_WALL")"
else
  WALL="$DEFAULT_WALL"
fi

if [[ ! -f "$WALL" ]]; then
  if command -v magick >/dev/null 2>&1; then
    magick -size 2560x1440 gradient:'#0f172a-#312e81' \
      -fill 'rgba(255,255,255,0.08)' -draw 'circle 2100,260 2500,260' \
      -fill 'rgba(255,255,255,0.06)' -draw 'circle 360,1180 760,1180' "$DEFAULT_WALL"
    WALL="$DEFAULT_WALL"
  else
    notify-send "Wallpaper" "No wallpaper found" || true
    exit 1
  fi
fi

ln -sfn "$WALL" "$CACHE_DIR/current_wallpaper"

if command -v swww >/dev/null 2>&1; then
  if ! swww query >/dev/null 2>&1; then
    swww-daemon --format xrgb >/dev/null 2>&1 &
    sleep 0.25
  fi
  swww img "$WALL" --transition-type grow --transition-pos center --transition-duration 0.8 --transition-fps 60 || true
fi
