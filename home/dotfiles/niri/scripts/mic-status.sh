#!/usr/bin/env bash
set -euo pipefail
json() {
  local text="$1" class="$2" tooltip="$3"
  text=${text//\\/\\\\}; text=${text//\"/\\\"}
  class=${class//\\/\\\\}; class=${class//\"/\\\"}
  tooltip=${tooltip//\\/\\\\}; tooltip=${tooltip//\"/\\\"}; tooltip=${tooltip//$'\n'/\\n}
  printf '{"text":"%s","class":"%s","tooltip":"%s"}\n' "$text" "$class" "$tooltip"
}
state="$(wpctl get-volume @DEFAULT_AUDIO_SOURCE@ 2>/dev/null || true)"
if [[ -n "$state" ]]; then
  if printf '%s' "$state" | grep -qi MUTED; then json "" "muted" "Default microphone muted"; else json "" "live" "Default microphone live"; fi
else
  json "" "muted" "No default microphone found"
fi
