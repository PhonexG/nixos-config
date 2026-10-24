#!/usr/bin/env bash
set -euo pipefail
"$HOME/.config/niri/scripts/lock-detached.sh" || true
sleep 0.25
systemctl suspend
