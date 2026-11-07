#!/usr/bin/env bash

# Use the display backlight, never keyboard LEDs.
backlights=(/sys/class/backlight/*)
backlight="${backlights[0]}"
mode="${1:---label}"

if [[ ! -r "$backlight/max_brightness" ]]; then
  if [[ "$mode" == --value ]]; then
    echo 1
  elif [[ "$mode" != --set ]]; then
    echo "󰃠  --%"
  fi
  exit 1
fi

if [[ "$mode" == --set ]]; then
  value="${2:-}"
  [[ "$value" =~ ^[0-9]+([.][0-9]+)?$ ]] || exit 1
  value="${value%%.*}"
  value=$((10#$value))
  (( value < 1 )) && value=1
  (( value > 100 )) && value=100
  exec brightnessctl --quiet --device="${backlight##*/}" set "${value}%"
fi

maximum=$(<"$backlight/max_brightness")
[[ "$maximum" =~ ^[0-9]+$ ]] && (( maximum > 0 )) || exit 1
last=""
while [[ -r "$backlight/brightness" ]]; do
  current=$(<"$backlight/brightness")
  if [[ "$current" =~ ^[0-9]+$ ]]; then
    percent=$(((current * 100 + maximum / 2) / maximum))
    if [[ "$percent" != "$last" ]]; then
      if [[ "$mode" == --value ]]; then
        echo "$percent"
      else
        echo "󰃠  ${percent}%"
      fi
      last="$percent"
    fi
  fi
  # Cheap sysfs reads; no brightnessctl subprocesses while idle.
  sleep 0.1
done
