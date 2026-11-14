#!/usr/bin/env bash
set -euo pipefail

THEMES_DIR="/etc/nixos/home/themes"
CURRENT_LINK="$HOME/.config/themes/current"

usage() {
  cat <<'EOF'
Usage:
  theme-switcher.sh [--menu]
  theme-switcher.sh --apply <theme>
  theme-switcher.sh <theme>
  theme-switcher.sh --list
EOF
}

discover_themes() {
  [[ -d "$THEMES_DIR" ]] || return 0
  local dir name
  for dir in "$THEMES_DIR"/*/; do
    [[ -d "$dir" ]] || continue
    name="${dir%/}"
    name="${name##*/}"
    case "$name" in
      ""|default|legacy|.*) continue ;;
    esac
    printf '%s\n' "$name"
  done | sort -u
}

ensure_gtk_css() {
  local target="$1"
  local import_line="@import url(\"file://$HOME/.config/themes/current/gtk.css\");"
  mkdir -p "$(dirname "$target")"
  if [[ -f "$target" ]] && grep -Fqx "$import_line" "$target" 2>/dev/null; then
    return 0
  fi
  rm -f "$target"
  printf '%s\n' "$import_line" > "$target"
}

find_ironbar_pids() {
  {
    pgrep -x ironbar 2>/dev/null || true
    pgrep -x '.ironbar-wrappe' 2>/dev/null || true
  } | sort -u
}

kill_ironbar() {
  pkill -x ironbar >/dev/null 2>&1 || true
  pkill -x '.ironbar-wrappe' >/dev/null 2>&1 || true
}

restart_ironbar() {
  mkdir -p "$HOME/.config/autostart"
  printf '[Desktop Entry]\nHidden=true\n' > "$HOME/.config/autostart/nm-applet.desktop"
  printf '[Desktop Entry]\nHidden=true\n' > "$HOME/.config/autostart/blueman.desktop"
  pkill -f 'nm-applet|blueman-applet' >/dev/null 2>&1 || true

  local restarted=0
  if command -v systemctl >/dev/null 2>&1 && systemctl --user cat ironbar.service >/dev/null 2>&1; then
    systemctl --user set-environment LC_NUMERIC=en_US.UTF-8 LC_TIME=en_US.UTF-8 LC_MESSAGES=en_US.UTF-8 >/dev/null 2>&1 || true
    # Kill any stray non-unit ironbar process before restarting the user service.
    if systemctl --user restart ironbar.service >/dev/null 2>&1; then
      restarted=1
      sleep 0.3
    fi
  fi

  if (( restarted == 0 )); then
    kill_ironbar
    for _ in {1..20}; do
      [[ -z "$(find_ironbar_pids)" ]] && break
      sleep 0.05
    done
    if command -v ironbar >/dev/null 2>&1 && [[ -n "${WAYLAND_DISPLAY:-}" ]]; then
      IRONBAR_LOG="${IRONBAR_LOG:-error}" \
      IRONBAR_FILE_LOG="${IRONBAR_FILE_LOG:-error}" \
      LC_NUMERIC="en_US.UTF-8" \
      LC_TIME="en_US.UTF-8" \
      LC_MESSAGES="en_US.UTF-8" \
      nohup ironbar >/dev/null 2>&1 &
      disown || true
      sleep 0.3
    fi
  fi

  # Guarantee at most a single ironbar process is running.
  local -a pids=()
  mapfile -t pids < <(find_ironbar_pids)
  if (( ${#pids[@]} > 1 )); then
    kill_ironbar
    for _ in {1..20}; do
      [[ -z "$(find_ironbar_pids)" ]] && break
      sleep 0.05
    done
    if command -v systemctl >/dev/null 2>&1 && systemctl --user restart ironbar.service >/dev/null 2>&1; then
      :
    elif command -v ironbar >/dev/null 2>&1 && [[ -n "${WAYLAND_DISPLAY:-}" ]]; then
      IRONBAR_LOG="${IRONBAR_LOG:-error}" \
      IRONBAR_FILE_LOG="${IRONBAR_FILE_LOG:-error}" \
      LC_NUMERIC="en_US.UTF-8" \
      LC_TIME="en_US.UTF-8" \
      LC_MESSAGES="en_US.UTF-8" \
      nohup ironbar >/dev/null 2>&1 &
      disown || true
    fi
  fi

  if command -v ironbar >/dev/null 2>&1; then
    ironbar var set tray_open false >/dev/null 2>&1 || true
    ironbar var set tray_arrow '󰅀' >/dev/null 2>&1 || true
    /etc/nixos/home/dotfiles/ironbar/controls.sh wifi-sync >/dev/null 2>&1 || true
    /etc/nixos/home/dotfiles/ironbar/controls.sh bt-sync >/dev/null 2>&1 || true
  fi
}

reload_kitty() {
  local pids="" sock=""
  if pids="$(pidof kitty 2>/dev/null)" && [[ -n "$pids" ]]; then
    # shellcheck disable=SC2086
    kill -SIGUSR1 $pids 2>/dev/null || true
  else
    pkill -USR1 -x kitty >/dev/null 2>&1 || true
  fi
  if command -v kitty >/dev/null 2>&1; then
    for sock in /tmp/kitty /tmp/kitty-*; do
      [[ -S "$sock" ]] || continue
      kitty @ --to "unix:$sock" load-config >/dev/null 2>&1 || true
    done
  fi
}

apply_theme() {
  local theme="$1"
  local theme_dir="$THEMES_DIR/$theme"

  if [[ -z "$theme" || "$theme" == *"/"* || "$theme" == "default" || "$theme" == "legacy" ]]; then
    printf 'Invalid theme name: %s\n' "$theme" >&2
    exit 1
  fi

  if [[ ! -d "$theme_dir" ]]; then
    printf 'Theme not found: %s\n' "$theme_dir" >&2
    command -v notify-send >/dev/null 2>&1 && notify-send 'Theme' "Theme not found: $theme" >/dev/null 2>&1 || true
    exit 1
  fi

  mkdir -p "$HOME/.config/themes"
  ln -sfn "$theme_dir" "$CURRENT_LINK"

  mkdir -p "$HOME/.config/ironbar"
  ln -sfn "$CURRENT_LINK/ironbar.toml" "$HOME/.config/ironbar/config.toml"
  ln -sfn "$CURRENT_LINK/ironbar.css" "$HOME/.config/ironbar/style.css"
  ln -sfn "/etc/nixos/home/dotfiles/ironbar/controls.sh" "$HOME/.config/ironbar/controls.sh"
  rm -f "$HOME/.config/ironbar/config.json"

  ensure_gtk_css "$HOME/.config/gtk-3.0/gtk.css"
  ensure_gtk_css "$HOME/.config/gtk-4.0/gtk.css"

  # 1) Niri
  if command -v niri >/dev/null 2>&1; then
    niri msg action load-config-file >/dev/null 2>&1 || true
  fi

  # 2) Ironbar
  restart_ironbar

  # 3) Fuzzel reads include=~/.config/themes/current/fuzzel.ini on next launch.

  # 4) Kitty
  reload_kitty

  # 5) Starship reads STARSHIP_CONFIG=$HOME/.config/themes/current/starship.toml on next prompt.

  # 6) Fish universal reload signal
  if command -v fish >/dev/null 2>&1; then
    fish -c 'set -U __theme_reload_ts (date +%s)' >/dev/null 2>&1 || true
  fi

  # 7) Thunar / GTK settings (never clobber ~/.icons)
  if command -v gsettings >/dev/null 2>&1; then
    gsettings set org.gnome.desktop.interface color-scheme 'prefer-dark' >/dev/null 2>&1 || true
    gsettings set org.gnome.desktop.interface icon-theme 'Papirus-Dark' >/dev/null 2>&1 || true
  fi

  # 8) Hyprlock reads source = ~/.config/themes/current/hyprlock.conf on next lock.

  if command -v notify-send >/dev/null 2>&1; then
    notify-send 'Theme' "Applied $theme" >/dev/null 2>&1 || true
  fi
}

select_theme_menu() {
  local themes choice
  themes="$(discover_themes)"
  if [[ -z "$themes" ]]; then
    command -v notify-send >/dev/null 2>&1 && notify-send 'Theme' 'No themes found in /etc/nixos/home/themes' >/dev/null 2>&1 || true
    exit 0
  fi

  choice="$(printf '%s\n' "$themes" | fuzzel --dmenu --prompt 'Theme  ' || true)"
  [[ -n "${choice:-}" ]] || exit 0
  apply_theme "$choice"
}

case "${1:-}" in
  ""|--menu)
    select_theme_menu
    ;;
  --list)
    discover_themes
    ;;
  --apply)
    if [[ $# -lt 2 || -z "${2:-}" ]]; then
      usage >&2
      exit 1
    fi
    apply_theme "$2"
    ;;
  -h|--help)
    usage
    ;;
  *)
    apply_theme "$1"
    ;;
esac
