#!/usr/bin/env bash
set -euo pipefail
niri msg action load-config-file >/dev/null 2>&1 || true
ironbar reload >/dev/null 2>&1 || true
swaync-client -R >/dev/null 2>&1 || true
swaync-client -rs >/dev/null 2>&1 || true
notify-send "Niri" "Session components reloaded" >/dev/null 2>&1 || true
