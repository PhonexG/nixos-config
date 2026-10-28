#!/usr/bin/env bash
print_status() {
  status=$(wpctl get-volume @DEFAULT_AUDIO_SOURCE@ 2>/dev/null)
  if [[ -z "$status" ]]; then
    echo "󰍭 Off"
  elif [[ "$status" == *"[MUTED]"* ]]; then
    echo "󰍭 Off"
  else
    vol=$(echo "$status" | awk '{print int($2 * 100)}')
    echo "󰍬 ${vol}%"
  fi
}

last=""
emit() {
  cur=$(print_status)
  if [[ "$cur" != "$last" ]]; then
    echo "$cur"
    last="$cur"
  fi
}

emit
pw-mon --no-colors 2>/dev/null | while IFS= read -r line; do
  if [[ "$line" == *"changed:"* ]]; then
    emit
  fi
done
