#!/usr/bin/env bash
print_status() {
  status=$(wpctl get-volume @DEFAULT_AUDIO_SINK@ 2>/dev/null)
  if [[ -z "$status" ]]; then
    echo "󰝟 --%"
  elif [[ "$status" == *"[MUTED]"* ]]; then
    echo "󰝟 Muted"
  else
    vol=$(echo "$status" | awk '{print int($2 * 100)}')
    if (( vol >= 66 )); then
      icon="󰕾"
    elif (( vol >= 33 )); then
      icon="󰖀"
    else
      icon="󰕿"
    fi
    echo "$icon ${vol}%"
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
