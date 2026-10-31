#!/usr/bin/env bash

parse_vol() {
  local raw="$1"
  local num="${raw#Volume: }"
  num="${num%% *}"
  local int="${num%%.*}"
  local frac="${num#*.}"
  if [[ "$int" == "$num" ]]; then
    echo "$((int * 100))"
  else
    frac="${frac:0:2}"
    while (( ${#frac} < 2 )); do frac="${frac}0"; done
    frac=$((10#$frac))
    echo "$((int * 100 + frac))"
  fi
}

print_status() {
  local status
  status=$(wpctl get-volume @DEFAULT_AUDIO_SOURCE@ 2>/dev/null)
  if [[ -z "$status" ]]; then
    echo "󰍭 Off"
  elif [[ "$status" == *"[MUTED]"* ]]; then
    echo "󰍭 Off"
  else
    local vol
    vol=$(parse_vol "$status")
    echo "󰍬 ${vol}%"
  fi
}

last=""
emit() {
  local cur
  cur=$(print_status)
  if [[ "$cur" != "$last" ]]; then
    echo "$cur"
    last="$cur"
  fi
}

while true; do
  emit
  sleep 1
done
