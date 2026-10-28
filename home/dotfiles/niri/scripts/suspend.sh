#!/usr/bin/env bash
set -euo pipefail

pgrep -x hyprlock >/dev/null 2>&1 || hyprlock &
systemctl suspend
