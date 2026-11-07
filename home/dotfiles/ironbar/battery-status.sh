#!/usr/bin/env bash

mode="${1:-}"

print_summary() {
  python3 - <<'PY'
from pathlib import Path

batteries = sorted(Path('/sys/class/power_supply').glob('BAT*'))
if not batteries:
    print('No battery found.')
    raise SystemExit(0)
battery = batteries[0]

def read(name):
    try:
        return (battery / name).read_text().strip()
    except OSError:
        return ''

def number(name):
    try:
        return float(read(name))
    except ValueError:
        return 0.0

status = read('status')
states = {'Charging': 'charging', 'Discharging': 'discharging',
          'Full': 'fully charged', 'Not charging': 'not charging'}
print(f"Charge: {read('capacity') or '—'}% · {states.get(status, status or 'unknown')}")
power = number('power_now')
if not power:
    power = number('current_now') * number('voltage_now') / 1_000_000
if power > 0:
    print(f"{'Charging power' if status == 'Charging' else 'Power draw'}: {power / 1_000_000:.1f} W")
    energy = number('energy_now')
    if status == 'Charging':
        energy = max(0, number('energy_full') - energy)
    if energy > 0 and status in ('Charging', 'Discharging'):
        minutes = round(energy / power * 60)
        label = 'Until full' if status == 'Charging' else 'Estimated remaining'
        print(f'{label}: {minutes // 60} h {minutes % 60} min')
full, design = number('energy_full'), number('energy_full_design')
if full > 0 and design > 0:
    print(f'Battery health: {full / design * 100:.0f}% of design capacity')
PY
}

if [[ "$mode" == --summary ]]; then
  print_summary
  exit 0
fi

print_status() {
  bat_path=$(find /sys/class/power_supply -name "BAT*" | head -n1)
  if [[ -z "$bat_path" ]]; then
    echo "󰂎 --%"
    return
  fi

  cap=$(cat "$bat_path/capacity" 2>/dev/null || echo 0)
  status=$(cat "$bat_path/status" 2>/dev/null || echo "Discharging")

  # Same ten-step glyph arrays as Omarchy's Waybar battery configuration.
  local level=$((cap / 10))
  (( level > 9 )) && level=9
  (( level < 0 )) && level=0
  local discharge_icons=("󰁺" "󰁻" "󰁼" "󰁽" "󰁾" "󰁿" "󰂀" "󰂁" "󰂂" "󰁹")
  local charge_icons=("󰢜" "󰂆" "󰂇" "󰂈" "󰢝" "󰂉" "󰢞" "󰂊" "󰂋" "󰂅")
  if [[ "$status" == "Full" ]]; then
    icon="󰂅"
  elif [[ "$status" == "Not charging" ]]; then
    icon=""
  elif [[ "$status" == "Charging" ]]; then
    icon="${charge_icons[$level]}"
  else
    icon="${discharge_icons[$level]}"
  fi

  local label="$icon ${cap}%"
  [[ "$mode" != --icon ]] || label="$icon"
  if [[ "$status" == "Discharging" ]] && (( cap <= 10 )); then
    echo "<span foreground=\"#f7768e\">$label</span>"
  elif [[ "$status" == "Discharging" ]] && (( cap <= 20 )); then
    echo "<span foreground=\"#e0af68\">$label</span>"
  else
    echo "$label"
  fi
}

if [[ "$mode" == --once ]]; then
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
upower --monitor 2>/dev/null | while IFS= read -r _; do
  emit
done
