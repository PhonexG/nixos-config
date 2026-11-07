#!/usr/bin/env python3
"""Small live information cards. Each update is one Pango-safe stdout line."""
import html
from pathlib import Path
import signal
import sys
import threading


def cpu_counters(path=Path('/proc/stat')):
    counters = {}
    for line in path.read_text().splitlines():
        fields = line.split()
        if fields and fields[0].startswith('cpu'):
            values = [int(value) for value in fields[1:9]]
            counters[fields[0]] = (sum(values), values[3] + values[4])
    return counters


def utilization(before, after):
    total = after[0] - before[0]
    idle = after[1] - before[1]
    return max(0, min(100, 100 * (total - idle) / total)) if total > 0 else 0


def cpu_text(before, after):
    load = {name: utilization(before.get(name, value), value) for name, value in after.items()}
    lines = [f"Overall       {load.get('cpu', 0):5.1f}%", '']
    cores = [(name, value) for name, value in load.items() if name != 'cpu']
    for offset in range(0, len(cores), 2):
        lines.append('    '.join(f"{name.upper():5} {value:5.1f}%" for name, value in cores[offset:offset + 2]))
    frequencies = []
    for policy in Path('/sys/devices/system/cpu/cpufreq').glob('policy*/scaling_cur_freq'):
        try:
            frequencies.append(int(policy.read_text()) / 1_000_000)
        except (OSError, ValueError):
            pass
    if frequencies:
        lines += ['', f'Frequency     {sum(frequencies) / len(frequencies):.2f} GHz']
    return '\n'.join(lines)


def battery_text(root=Path('/sys/class/power_supply')):
    batteries = sorted(root.glob('BAT*'))
    if not batteries:
        return 'No battery found'
    battery = batteries[0]

    def read(name, default=''):
        try:
            return (battery / name).read_text().strip()
        except OSError:
            return default

    def number(name):
        try:
            return float(read(name, '0'))
        except ValueError:
            return 0

    state = read('status')
    states = {'Charging': 'Charging', 'Discharging': 'On battery',
              'Full': 'Fully charged', 'Not charging': 'Plugged in'}
    lines = [f"{states.get(state, state)} · {read('capacity', '—')}%"]
    voltage = number('voltage_now')
    power = number('power_now') / 1_000_000
    if not power:
        power = number('current_now') * voltage / 1_000_000_000_000
    energy = number('energy_now') / 1_000_000
    full = number('energy_full') / 1_000_000
    design = number('energy_full_design') / 1_000_000
    if not full and voltage:
        energy = number('charge_now') * voltage / 1_000_000_000_000
        full = number('charge_full') * voltage / 1_000_000_000_000
        design = number('charge_full_design') * voltage / 1_000_000_000_000
    if power > 0 and state in ('Charging', 'Discharging'):
        lines += ['', f"{'Charging power' if state == 'Charging' else 'Power draw'}: {power:.1f} W"]
        remaining = max(0, full - energy) if state == 'Charging' else energy
        if remaining > 0:
            minutes = round(remaining / power * 60)
            label = 'Until full' if state == 'Charging' else 'Estimated remaining'
            lines.append(f'{label}: {minutes // 60} h {minutes % 60} min')
    if full:
        lines += ['', f'Capacity: {full:.1f} Wh']
    if full and design:
        lines.append(f'Health: {min(100, full / design * 100):.0f}% of design capacity')
    if Path('/tmp/super_eco_active').exists():
        lines += ['', 'Ultra-Eco mode enabled']
    return '\n'.join(lines)


def main():
    mode = sys.argv[1]
    stopped = threading.Event()
    signal.signal(signal.SIGTERM, lambda *_: stopped.set())
    signal.signal(signal.SIGINT, lambda *_: stopped.set())
    before = cpu_counters() if mode == 'cpu' else {}
    if mode == 'cpu':
        stopped.wait(0.2)
    while not stopped.is_set():
        if mode == 'cpu':
            after = cpu_counters()
            text = cpu_text(before, after)
            before = after
        else:
            text = battery_text()
        # Ironbar treats span-wrapped text as markup; plain entities are escaped.
        print('<span>' + html.escape(text).replace('\n', '&#10;') + '</span>', flush=True)
        stopped.wait(2 if mode == 'cpu' else 5)


if __name__ == '__main__':
    try:
        main()
    except BrokenPipeError:
        pass
