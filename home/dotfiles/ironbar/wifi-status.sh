#!/usr/bin/env bash
mode="${1:---label}"

print_status() {
  local radio ssid signal icon
  if nmcli -t -f TYPE,STATE device status 2>/dev/null | grep -q '^ethernet:connected$'; then
    if [[ "$mode" == --icon ]]; then echo "󰀂"; else echo "Ethernet — connected"; fi
    return
  fi
  radio=$(nmcli radio wifi 2>/dev/null)
  if [[ "$radio" == "disabled" ]]; then
    if [[ "$mode" == --icon ]]; then echo "󰤮"; else echo "Wi-Fi disabled"; fi
  else
    ssid=$(nmcli -t -f active,ssid dev wifi list --rescan no 2>/dev/null | grep '^yes:' | head -n1 | cut -d: -f2-)
    if [[ -n "$ssid" ]]; then
      signal=$(nmcli -t -f IN-USE,SIGNAL dev wifi list --rescan no 2>/dev/null | awk -F: '$1 == "*" {print $2; exit}')
      signal="${signal:-0}"
      [[ "$signal" =~ ^[0-9]+$ ]] || signal=0
      if (( signal >= 75 )); then icon="󰤨";
      elif (( signal >= 50 )); then icon="󰤥";
      elif (( signal >= 25 )); then icon="󰤢";
      else icon="󰤟"; fi
      if [[ "$mode" == --icon ]]; then echo "$icon"; else echo "$ssid · signal ${signal}%"; fi
    else
      if [[ "$mode" == --icon ]]; then echo "󰤮"; else echo "Wi-Fi — disconnected"; fi
    fi
  fi
}

if [[ "$mode" == --summary ]]; then
  print_status
  exit 0
fi

last=""
emit() {
  cur=$(print_status)
  if [[ "$cur" != "$last" ]]; then
    echo "$cur"
    last="$cur"
  fi
}

emit
nmcli monitor 2>/dev/null | while IFS= read -r _; do
  emit
done
