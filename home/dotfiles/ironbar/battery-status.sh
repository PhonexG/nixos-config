#!/usr/bin/env bash
print_status() {
  bat_path=$(find /sys/class/power_supply -name "BAT*" | head -n1)
  if [[ -z "$bat_path" ]]; then
    echo "󰂎 --%"
    return
  fi

  cap=$(cat "$bat_path/capacity" 2>/dev/null || echo 0)
  status=$(cat "$bat_path/status" 2>/dev/null || echo "Discharging")

  if [[ "$status" == "Charging" ]]; then
    if (( cap >= 90 )); then icon="󰂅";
    elif (( cap >= 80 )); then icon="󰂊";
    elif (( cap >= 70 )); then icon="󰢞";
    elif (( cap >= 60 )); then icon="󰂉";
    elif (( cap >= 50 )); then icon="󰢝";
    elif (( cap >= 40 )); then icon="󰂈";
    elif (( cap >= 30 )); then icon="󰂇";
    elif (( cap >= 20 )); then icon="󰂆";
    else icon="󰢜"; fi
  else
    if (( cap >= 95 )); then icon="󰁹";
    elif (( cap >= 90 )); then icon="󰂂";
    elif (( cap >= 80 )); then icon="󰂁";
    elif (( cap >= 70 )); then icon="󰂀";
    elif (( cap >= 60 )); then icon="󰁿";
    elif (( cap >= 50 )); then icon="󰁾";
    elif (( cap >= 40 )); then icon="󰁽";
    elif (( cap >= 30 )); then icon="󰁼";
    elif (( cap >= 20 )); then icon="󰁻";
    elif (( cap >= 10 )); then icon="󰁺";
    else icon="󰂃"; fi
  fi

  echo "$icon  ${cap}%"
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
upower --monitor 2>/dev/null | while IFS= read -r _; do
  emit
done
