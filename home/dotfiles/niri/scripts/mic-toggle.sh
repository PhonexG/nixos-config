#!/usr/bin/env bash
set -euo pipefail
COOLDOWN_FILE="/tmp/niri-mic-toggle-last"
NOW_MS="$(date +%s%3N)"
LAST_MS="$(cat "$COOLDOWN_FILE" 2>/dev/null || echo 0)"
[[ "$LAST_MS" =~ ^[0-9]+$ ]] && (( NOW_MS - LAST_MS < 850 )) && exit 0
printf '%s' "$NOW_MS" > "$COOLDOWN_FILE"
if wpctl get-volume @DEFAULT_AUDIO_SOURCE@ 2>/dev/null | grep -qi MUTED; then
  wpctl set-mute @DEFAULT_AUDIO_SOURCE@ 0
  notify-send "Microphone" "Live" -t 900 || true
else
  wpctl set-mute @DEFAULT_AUDIO_SOURCE@ 1
  notify-send "Microphone" "Muted" -t 900 || true
fi
