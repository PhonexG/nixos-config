#!/usr/bin/env bash
set -euo pipefail

INPUT_WALL="${1:-}"
BASE="$HOME/.config/niri"
WALL_DIR="$BASE/wallpapers"
CACHE_DIR="$HOME/.cache/niri"
CURRENT_WALL="$WALL_DIR/current"
SELECTED_PREFIX="$WALL_DIR/selected-wallpaper"
DEFAULT_WALL="$WALL_DIR/default.png"
WAYBAR_DIR="$HOME/.config/waybar"
KITTY_DIR="$HOME/.config/kitty"
SWAYNC_DIR="$HOME/.config/swaync"
WOFI_DIR="$HOME/.config/wofi"

mkdir -p "$CACHE_DIR" "$WALL_DIR" "$WAYBAR_DIR" "$KITTY_DIR" "$SWAYNC_DIR" "$WOFI_DIR"

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

MATUGEN_JSON="$CACHE_DIR/matugen.json"
if command -v matugen >/dev/null 2>&1; then
  matugen image "$WALL" --json hex >"$MATUGEN_JSON" 2>/tmp/matugen-niri.log || : >"$MATUGEN_JSON"
else
  : >"$MATUGEN_JSON"
fi

if command -v python3 >/dev/null 2>&1; then
  python3 - "$MATUGEN_JSON" "$WAYBAR_DIR" "$KITTY_DIR" "$SWAYNC_DIR" "$WOFI_DIR" <<'PY'
from pathlib import Path
import json, sys

json_path = Path(sys.argv[1])
waybar_dir, kitty_dir, swaync_dir, wofi_dir = map(Path, sys.argv[2:])
fallback = {
    "background":"#1e1e2e","surface":"#313244","surface_variant":"#45475a",
    "on_surface":"#cdd6f4","outline":"#6c7086","primary":"#89b4fa",
    "secondary":"#cba6f7","tertiary":"#94e2d5","error":"#f38ba8"
}
scheme = dict(fallback)
if json_path.exists() and json_path.stat().st_size:
    try:
        data=json.loads(json_path.read_text())
        colors=data.get("colors",{})
        picked=colors.get("dark") or colors.get("scheme-dark") or colors.get("scheme_dark") or next((v for v in colors.values() if isinstance(v,dict)), {})
        for k,v in picked.items():
            if isinstance(v,str) and v.startswith('#'): scheme[k]=v
    except Exception: pass

def get(k, alt=None): return scheme.get(k) or (scheme.get(alt) if alt else None) or fallback[k if k in fallback else alt]
def strip(h): return h.strip().lstrip('#')[:6]
def rgb(h,a):
    h=strip(h); return f"rgba({int(h[:2],16)}, {int(h[2:4],16)}, {int(h[4:6],16)}, {a})"
bg=get('background'); surface=get('surface','background'); surface2=get('surface_variant','surface'); text=get('on_surface'); muted=get('outline','surface_variant'); accent=get('primary'); accent2=get('secondary'); tertiary=get('tertiary','secondary'); danger=get('error')
def safe_write(p, data):
    try:
        p.unlink(missing_ok=True)
    except Exception:
        pass
    p.write_text(data)

safe_write(waybar_dir/'colors.css', f'''@define-color bg {bg};\n@define-color bg_alpha {rgb(bg,'0.72')};\n@define-color surface {surface};\n@define-color surface_alpha {rgb(surface,'0.72')};\n@define-color text {text};\n@define-color muted {muted};\n@define-color accent {accent};\n@define-color accent2 {accent2};\n@define-color danger {danger};\n@define-color success #a6e3a1;\n''')
safe_write(kitty_dir/'current-theme.conf', f'''foreground {text}\nbackground {bg}\nselection_foreground {bg}\nselection_background {accent}\ncursor {accent2}\ncursor_text_color {bg}\ncolor0 {surface2}\ncolor1 {danger}\ncolor2 {tertiary}\ncolor3 #f9e2af\ncolor4 {accent}\ncolor5 {accent2}\ncolor6 {tertiary}\ncolor7 {text}\ncolor8 {muted}\ncolor9 {danger}\ncolor10 {tertiary}\ncolor11 #f9e2af\ncolor12 {accent}\ncolor13 {accent2}\ncolor14 {tertiary}\ncolor15 {text}\n''')
for d in (swaync_dir,):
    safe_write(d/'colors.css', f'''@define-color bg {bg};\n@define-color bg_alpha {rgb(bg,'0.74')};\n@define-color surface {surface};\n@define-color surface_alpha {rgb(surface,'0.78')};\n@define-color text {text};\n@define-color muted {muted};\n@define-color accent {accent};\n@define-color accent2 {accent2};\n@define-color danger {danger};\n@define-color success #a6e3a1;\n''')
safe_write(wofi_dir/'colors.css', f'''@define-color bg {rgb(bg,'0.84')};\n@define-color surface {rgb(surface,'0.88')};\n@define-color text {text};\n@define-color muted {muted};\n@define-color accent {accent};\n@define-color accent2 {accent2};\n@define-color danger {danger};\n@define-color success #a6e3a1;\n''')
PY
fi

pkill -SIGUSR2 waybar >/dev/null 2>&1 || true
swaync-client -R >/dev/null 2>&1 || true
swaync-client -rs >/dev/null 2>&1 || true
