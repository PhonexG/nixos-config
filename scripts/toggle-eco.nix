{ pkgs }:

pkgs.writeShellScriptBin "toggle-eco" ''
  STATE="/tmp/super_eco_active"
  TARGET_USER="''${SUDO_USER:-oni}"
  TARGET_UID="$(id -u "$TARGET_USER")"

  notify() {
    sudo -u "$TARGET_USER" \
      DBUS_SESSION_BUS_ADDRESS="unix:path=/run/user/$TARGET_UID/bus" \
      ${pkgs.libnotify}/bin/notify-send \
      -a "Power Mode" \
      -i "$3" \
      -t 3500 \
      "$1" "$2" 2>/dev/null || true
  }

  get_power() {
    for bat in /sys/class/power_supply/BAT*; do
      if [ -f "$bat/power_now" ]; then
        awk '{printf "%.1f W", $1 / 1000000}' "$bat/power_now"
        return
      fi
    done

    for bat in /sys/class/power_supply/BAT*; do
      if [ -f "$bat/current_now" ] && [ -f "$bat/voltage_now" ]; then
        awk \
          -v c="$(cat "$bat/current_now")" \
          -v v="$(cat "$bat/voltage_now")" \
          'BEGIN {printf "%.1f W", (c * v) / 1000000000000}'
        return
      fi
    done

    echo "N/A"
  }

  set_epp() {
    for f in /sys/devices/system/cpu/cpufreq/policy*/energy_performance_preference; do
      [ -f "$f" ] || continue
      echo "$1" > "$f" 2>/dev/null || true
    done
  }

  set_governor() {
    for f in /sys/devices/system/cpu/cpufreq/policy*/scaling_governor; do
      [ -f "$f" ] || continue
      echo "$1" > "$f" 2>/dev/null || true
    done
  }

  set_gpu() {
    for card in /sys/class/drm/card[0-9]*; do
      [ -f "$card/device/vendor" ] || continue
      vendor="$(cat "$card/device/vendor" 2>/dev/null || true)"
      [ "$vendor" = "0x1002" ] || continue

      node="$card/device/power_dpm_force_performance_level"
      if [ -f "$node" ]; then
        echo "$1" > "$node" 2>/dev/null || true
      fi
    done
  }

  find_niri_socket() {
    local runtime_dir="/run/user/$TARGET_UID"
    local sock=""

    if [ -n "''${NIRI_SOCKET:-}" ] && [ -S "''${NIRI_SOCKET}" ]; then
      printf '%s\n' "$NIRI_SOCKET"
      return 0
    fi

    for sock in "$runtime_dir"/niri.*.sock; do
      [ -S "$sock" ] || continue
      if sudo -u "$TARGET_USER" \
        XDG_RUNTIME_DIR="$runtime_dir" \
        NIRI_SOCKET="$sock" \
        ${pkgs.niri}/bin/niri msg version >/dev/null 2>&1; then
        printf '%s\n' "$sock"
        return 0
      fi
    done

    return 1
  }

  set_display_mode() {
    local mode="$1"
    local sock=""
    sock="$(find_niri_socket || true)"
    [ -n "$sock" ] || return 0

    sudo -u "$TARGET_USER" \
      XDG_RUNTIME_DIR="/run/user/$TARGET_UID" \
      NIRI_SOCKET="$sock" \
      ${pkgs.niri}/bin/niri msg output eDP-1 mode "$mode" \
      2>/dev/null || true
  }

  set_boost() {
    for f in /sys/devices/system/cpu/cpu*/cpufreq/boost; do
      [ -f "$f" ] || continue
      echo "$1" > "$f" 2>/dev/null || true
    done
  }

  if [ -f "$STATE" ]; then
    rm -f "$STATE"

    set_display_mode "1920x1200@60.001"

    ${pkgs.brightnessctl}/bin/brightnessctl set 35% 2>/dev/null || true
    ${pkgs.util-linux}/bin/rfkill unblock bluetooth 2>/dev/null || true

    set_epp "balance_power"
    set_governor "powersave"
    set_boost 1
    set_gpu "auto"

    sleep 1
    WATTS="$(get_power)"

    notify \
      "⚡ Power Mode" \
      "Eco вимкнено • 60 Hz\nСпоживання: $WATTS" \
      "battery-charging"

    exit 0
  fi

  touch "$STATE"

  set_display_mode "1920x1200@40.003"

  ${pkgs.brightnessctl}/bin/brightnessctl set 20% 2>/dev/null || true
  ${pkgs.util-linux}/bin/rfkill block bluetooth 2>/dev/null || true

  set_epp "power"
  set_governor "powersave"
  set_boost 1
  set_gpu "low"

  sleep 1
  WATTS="$(get_power)"

  notify \
    "🌱 Ultra-Eco" \
    "40 Hz • EPP power\nСпоживання: $WATTS" \
    "battery-level-20-symbolic"
''
