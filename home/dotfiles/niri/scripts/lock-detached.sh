#!/usr/bin/env bash
set -euo pipefail
pgrep -x hyprlock >/dev/null 2>&1 && exit 0
nohup hyprlock >/tmp/hyprlock.log 2>&1 &
