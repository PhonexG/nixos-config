#!/usr/bin/env bash
print_status() {
  radio=$(nmcli radio wifi 2>/dev/null)
  if [[ "$radio" == "disabled" ]]; then
    echo "󰤭  Off"
  else
    ssid=$(nmcli -t -f active,ssid dev wifi 2>/dev/null | grep '^yes:' | cut -d: -f2-)
    if [[ -n "$ssid" ]]; then
      echo "󰤨  $ssid"
    else
      echo "󰤯  On"
    fi
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
nmcli monitor 2>/dev/null | while IFS= read -r _; do
  emit
done
