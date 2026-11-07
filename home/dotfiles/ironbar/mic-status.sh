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

# React to PipeWire changes instead of polling wpctl once per second.
# Ignore client events: running wpctl creates its own PipeWire client.
emit
while true; do
  changed=false
  while IFS= read -r line; do
    case "$line" in
      *"Spa:Pod:Object:Param:Props:mute"*|*"Spa:Pod:Object:Param:Props:channelVolumes"*|*"default.audio.source"*)
        changed=true
        ;;
      "")
        if [[ "$changed" == true ]]; then
          emit
          changed=false
        fi
        ;;
    esac
  done < <(stdbuf -oL pw-mon --no-colors --hide-props --print-separator 2>/dev/null)
  # Reconnect if PipeWire is restarted.
  sleep 1
  emit
done
