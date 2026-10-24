#!/usr/bin/env bash
set -euo pipefail
pkill -x waybar >/dev/null 2>&1 || true
sleep 0.25
waybar -c "$HOME/.config/waybar/config.jsonc" -s "$HOME/.config/waybar/style.css" >/tmp/waybar.log 2>&1 &
