{ pkgs, ... }:

let
  ironbar = import ./ironbar-package.nix { inherit pkgs; };

  screensaver = pkgs.writeShellApplication {
    name = "screensaver";
    runtimeInputs = [
      pkgs.coreutils
      pkgs.foot
      pkgs.gawk
      pkgs.gnugrep
      pkgs.gnused
      pkgs.procps
      pkgs.python3
      pkgs.terminaltexteffects
      pkgs.util-linux
    ];
    text = ''
      STATE_DIR="''${XDG_RUNTIME_DIR:-/run/user/$(id -u)}/power-state"
      LOCK_FILE="$STATE_DIR/screensaver.lock"
      PID_FILE="$STATE_DIR/screensaver.pid"
      THEME_DIR="$HOME/.config/themes/current"
      SELF="$0"

      mkdir -p "$STATE_DIR"

      # Rail Dark defaults (6-char hex without leading '#')
      BG_BASE="1e222a"
      BG_SURFACE="252a34"
      ACCENT_PRIMARY="88a4d4"
      ACCENT_SECONDARY="88c0d0"
      FG_PRIMARY="cfd6e2"
      FG_MUTED="8b95a7"
      STATUS_OK="a3be8c"
      STATUS_WARN="ebcb8b"
      STATUS_ERR="bf616a"

      ANSI_0="$BG_SURFACE"
      ANSI_1="$STATUS_ERR"
      ANSI_2="$STATUS_OK"
      ANSI_3="$STATUS_WARN"
      ANSI_4="$ACCENT_PRIMARY"
      ANSI_5="b48ead"
      ANSI_6="$ACCENT_SECONDARY"
      ANSI_7="$FG_PRIMARY"
      ANSI_8="$FG_MUTED"
      ANSI_15="eceff4"

      load_theme_colors() {
        local palette="$THEME_DIR/palette.toml"
        local kitty_conf="$THEME_DIR/kitty.conf"
        local line key val

        if [[ -r "$palette" ]]; then
          while IFS= read -r line; do
            if [[ "$line" =~ ^[[:space:]]*([a-z_]+)[[:space:]]*=[[:space:]]*\"#?([0-9a-fA-F]{6})\" ]]; then
              key="''${BASH_REMATCH[1]}"
              val="''${BASH_REMATCH[2],,}"
              case "$key" in
                bg_base) BG_BASE="$val" ;;
                bg_surface) BG_SURFACE="$val" ;;
                accent_primary) ACCENT_PRIMARY="$val" ;;
                accent_secondary) ACCENT_SECONDARY="$val" ;;
                fg_primary) FG_PRIMARY="$val" ;;
                fg_muted) FG_MUTED="$val" ;;
                status_ok) STATUS_OK="$val" ;;
                status_warn) STATUS_WARN="$val" ;;
                status_err) STATUS_ERR="$val" ;;
              esac
            fi
          done < "$palette"
        fi

        ANSI_0="$BG_SURFACE"
        ANSI_1="$STATUS_ERR"
        ANSI_2="$STATUS_OK"
        ANSI_3="$STATUS_WARN"
        ANSI_4="$ACCENT_PRIMARY"
        ANSI_6="$ACCENT_SECONDARY"
        ANSI_7="$FG_PRIMARY"
        ANSI_8="$FG_MUTED"

        if [[ -r "$kitty_conf" ]]; then
          while IFS= read -r line; do
            if [[ "$line" =~ ^[[:space:]]*(background|foreground|color0|color1|color2|color3|color4|color5|color6|color7|color8|color15)[[:space:]]+#?([0-9a-fA-F]{6}) ]]; then
              key="''${BASH_REMATCH[1]}"
              val="''${BASH_REMATCH[2],,}"
              case "$key" in
                background) BG_BASE="$val" ;;
                foreground) FG_PRIMARY="$val" ;;
                color0) ANSI_0="$val" ;;
                color1) ANSI_1="$val" ;;
                color2) ANSI_2="$val" ;;
                color3) ANSI_3="$val" ;;
                color4) ANSI_4="$val" ;;
                color5) ANSI_5="$val" ;;
                color6) ANSI_6="$val" ;;
                color7) ANSI_7="$val" ;;
                color8) ANSI_8="$val" ;;
                color15) ANSI_15="$val" ;;
              esac
            fi
          done < "$kitty_conf"
        fi
      }

      is_locked() {
        pgrep -x hyprlock >/dev/null 2>&1
      }

      has_active_display() {
        local status_file conn found_enabled=0
        shopt -s nullglob
        for status_file in /sys/class/drm/card*-*/status; do
          conn="''${status_file%/status}"
          [[ -r "$conn/enabled" ]] || continue
          [[ "$(<"$status_file")" == "connected" ]] || continue
          [[ "$(<"$conn/enabled")" == "enabled" ]] || continue
          found_enabled=1
          if [[ -r "$conn/dpms" ]] && [[ "$(<"$conn/dpms")" == "On" ]]; then
            shopt -u nullglob
            return 0
          fi
        done
        shopt -u nullglob
        (( found_enabled == 0 ))
      }

      is_pid_screensaver() {
        local pid="$1"
        [[ "$pid" =~ ^[0-9]+$ ]] || return 1
        kill -0 "$pid" 2>/dev/null || return 1
        [[ -r "/proc/$pid/cmdline" ]] || return 1
        tr '\0' ' ' < "/proc/$pid/cmdline" 2>/dev/null | grep -Fq "nixos-screensaver"
      }

      is_running() {
        local pid=""
        if [[ -r "$PID_FILE" ]]; then
          pid="$(<"$PID_FILE")"
          if is_pid_screensaver "$pid"; then
            return 0
          fi
        fi
        pgrep -f 'foot.*--app-id=nixos-screensaver' >/dev/null 2>&1
      }

      kill_pgrp_safe() {
        local pid="$1"
        [[ "$pid" =~ ^[0-9]+$ ]] || return 0
        kill -TERM -- "-$pid" 2>/dev/null || kill -TERM "$pid" 2>/dev/null || true
      }

      cmd_stop() {
        exec 9>"$LOCK_FILE"
        flock -w 2 9 || true

        local pid=""
        if [[ -r "$PID_FILE" ]]; then
          pid="$(<"$PID_FILE")"
          if is_pid_screensaver "$pid"; then
            kill_pgrp_safe "$pid"
          fi
        fi
        pkill -TERM -f 'foot.*--app-id=nixos-screensaver' 2>/dev/null || true

        for _ in 1 2 3 4 5 6; do
          if ! is_running; then
            break
          fi
          sleep 0.05
        done

        if [[ -n "$pid" ]] && is_pid_screensaver "$pid"; then
          kill -KILL -- "-$pid" 2>/dev/null || kill -KILL "$pid" 2>/dev/null || true
        fi
        pkill -KILL -f 'foot.*--app-id=nixos-screensaver' 2>/dev/null || true

        rm -f "$PID_FILE"
      }

      validate_mode() {
        local mode="''${1:-mix}"
        case "$mode" in
          mix|lightning|storm|sakura|nixos)
            printf '%s\n' "$mode"
            ;;
          tte)
            printf 'nixos\n'
            ;;
          tree)
            printf 'sakura\n'
            ;;
          *)
            printf 'Invalid screensaver mode: %s (expected mix|nixos|sakura|lightning|storm|tte)\n' "$mode" >&2
            exit 2
            ;;
        esac
      }

      cmd_start() {
        local mode effect
        mode="$(validate_mode "''${1:-mix}")"
        effect="''${2:-}"

        exec 9>"$LOCK_FILE"
        flock -n 9 || exit 0

        if is_locked || ! has_active_display || is_running; then
          exit 0
        fi

        load_theme_colors

        local -a foot_args=(
          --app-id=nixos-screensaver
          --title=Screensaver
          --fullscreen
          --config=/dev/null
          -o "main.font=JetBrainsMono Nerd Font:size=14"
          -o "main.pad=0x0"
          -o "main.box-drawings-uses-font-glyphs=no"
          -o "cursor.blink=no"
          -o "colors.alpha=1.0"
          -o "colors.background=$BG_BASE"
          -o "colors.foreground=$FG_PRIMARY"
          -o "colors.cursor=$BG_BASE $BG_BASE"
          -o "colors.regular0=$ANSI_0"
          -o "colors.regular1=$ANSI_1"
          -o "colors.regular2=$ANSI_2"
          -o "colors.regular3=$ANSI_3"
          -o "colors.regular4=$ANSI_4"
          -o "colors.regular5=$ANSI_5"
          -o "colors.regular6=$ANSI_6"
          -o "colors.regular7=$ANSI_7"
          -o "colors.bright0=$ANSI_8"
          -o "colors.bright1=$ANSI_1"
          -o "colors.bright2=$ANSI_2"
          -o "colors.bright3=$ANSI_3"
          -o "colors.bright4=$ANSI_4"
          -o "colors.bright5=$ANSI_5"
          -o "colors.bright6=$ANSI_6"
          -o "colors.bright7=$ANSI_15"
          -o "mouse.hide-when-typing=yes"
          -o "scrollback.lines=0"
          -o "bell.urgent=no"
          -o "bell.notify=no"
        )

        if [[ -n "$effect" ]]; then
          setsid foot "''${foot_args[@]}" -- "$SELF" run "$mode" "$effect" </dev/null >/dev/null 2>&1 9>&- &
        else
          setsid foot "''${foot_args[@]}" -- "$SELF" run "$mode" </dev/null >/dev/null 2>&1 9>&- &
        fi
        local pid=$!
        printf '%s\n' "$pid" > "$PID_FILE"
      }

      cmd_run() {
        local mode effect
        mode="$(validate_mode "''${1:-mix}")"
        effect="''${2:-}"

        load_theme_colors

        export SS_MODE="$mode"
        export SS_EFFECT="$effect"
        export SS_STATE_DIR="$STATE_DIR"
        export SS_BG_BASE="$BG_BASE"
        export SS_BG_SURFACE="$BG_SURFACE"
        export SS_ACCENT_PRIMARY="$ACCENT_PRIMARY"
        export SS_ACCENT_SECONDARY="$ACCENT_SECONDARY"
        export SS_FG_PRIMARY="$FG_PRIMARY"
        export SS_FG_MUTED="$FG_MUTED"
        export SS_STATUS_OK="$STATUS_OK"
        export SS_STATUS_WARN="$STATUS_WARN"
        export SS_STATUS_ERR="$STATUS_ERR"

        exec python3 - <<'PY'
      import fcntl
      import math
      import os
      import random
      import re
      import select
      import signal
      import struct
      import subprocess
      import tempfile
      import termios
      import time

      MODE = os.environ.get("SS_MODE", "mix")
      EFFECT_OVERRIDE = os.environ.get("SS_EFFECT", "").strip().lower()
      STATE_DIR = os.environ.get("SS_STATE_DIR", "/tmp")
      BG_BASE = os.environ.get("SS_BG_BASE", "1e222a")
      BG_SURFACE = os.environ.get("SS_BG_SURFACE", "252a34")
      ACCENT_PRIMARY = os.environ.get("SS_ACCENT_PRIMARY", "88a4d4")
      ACCENT_SECONDARY = os.environ.get("SS_ACCENT_SECONDARY", "88c0d0")
      FG_PRIMARY = os.environ.get("SS_FG_PRIMARY", "cfd6e2")
      FG_MUTED = os.environ.get("SS_FG_MUTED", "8b95a7")
      STATUS_OK = os.environ.get("SS_STATUS_OK", "a3be8c")
      STATUS_WARN = os.environ.get("SS_STATUS_WARN", "ebcb8b")
      STATUS_ERR = os.environ.get("SS_STATUS_ERR", "bf616a")

      STOP_REQUESTED = False

      # Filter out terminal query auto-responses (DSR, DA1/DA2, DECRPM, OSC 10/11)
      # while treating every single keypress or mouse event as instant exit.
      TERM_RESP_RE = re.compile(
          rb"\x1b\[[?>=]?[0-9;]*[Rc]"
          rb"|\x1b\[[?]?[0-9;]*\$y"
          rb"|\x1b\][0-9]+;[^\x07\x1b]*(?:\x07|\x1b\\)"
      )


      def hex_to_rgb(h):
          h = h.lstrip("#")
          if len(h) != 6:
              return (30, 34, 42)
          return (int(h[0:2], 16), int(h[2:4], 16), int(h[4:6], 16))


      def lerp_rgb(c1, c2, t):
          if t <= 0.0:
              return c1
          if t >= 1.0:
              return c2
          return (
              int(c1[0] + (c2[0] - c1[0]) * t),
              int(c1[1] + (c2[1] - c1[1]) * t),
              int(c1[2] + (c2[2] - c1[2]) * t),
          )


      BG_RGB = hex_to_rgb(BG_BASE)
      SURFACE_RGB = hex_to_rgb(BG_SURFACE)
      ACCENT1_RGB = hex_to_rgb(ACCENT_PRIMARY)
      ACCENT2_RGB = hex_to_rgb(ACCENT_SECONDARY)
      FG_RGB = hex_to_rgb(FG_PRIMARY)
      MUTED_RGB = hex_to_rgb(FG_MUTED)
      OK_RGB = hex_to_rgb(STATUS_OK)
      WARN_RGB = hex_to_rgb(STATUS_WARN)
      ERR_RGB = hex_to_rgb(STATUS_ERR)


      def set_input_raw_keep_opost(fd):
          """Enable instant unbuffered key/mouse reads while preserving OPOST|ONLCR
          so tte's newline-delimited frames never staircase on foot."""
          attrs = termios.tcgetattr(fd)
          attrs[0] &= ~(termios.IXON | termios.IXOFF | termios.ICRNL)
          attrs[1] |= termios.OPOST | termios.ONLCR
          attrs[3] &= ~(termios.ECHO | termios.ICANON | termios.IEXTEN | termios.ISIG)
          attrs[6][termios.VMIN] = 1
          attrs[6][termios.VTIME] = 0
          termios.tcsetattr(fd, termios.TCSANOW, attrs)


      def get_term_size(fd):
          try:
              data = fcntl.ioctl(fd, termios.TIOCGWINSZ, b"\x00" * 8)
              rows, cols, _, _ = struct.unpack("HHHH", data)
              if rows >= 12 and cols >= 30:
                  return rows, cols
          except OSError:
              pass
          return 40, 120


      def write_all(fd, data):
          view = memoryview(data)
          total = len(view)
          sent = 0
          while sent < total:
              try:
                  n = os.write(fd, view[sent:])
                  if n <= 0:
                      break
                  sent += n
              except InterruptedError:
                  continue
              except OSError:
                  break


      def is_user_input(chunk):
          if not chunk:
              return False
          cleaned = TERM_RESP_RE.sub(b"", chunk)
          return bool(cleaned)


      def poll_user_input(tty_fd, timeout):
          if STOP_REQUESTED:
              return True
          try:
              rlist, _, _ = select.select([tty_fd], [], [], max(0.0, timeout))
          except InterruptedError:
              return False
          except OSError:
              return True
          if tty_fd in rlist:
              try:
                  chunk = os.read(tty_fd, 4096)
                  if not chunk:
                      return True
                  if is_user_input(chunk):
                      return True
              except OSError:
                  return True
          return False


      def wait_or_input(tty_fd, duration):
          if STOP_REQUESTED:
              return True
          deadline = time.monotonic() + max(0.0, duration)
          while not STOP_REQUESTED:
              rem = deadline - time.monotonic()
              if rem <= 0:
                  return False
              if poll_user_input(tty_fd, min(0.03, rem)):
                  return True
          return True


      def clear_to_bg(tty_fd):
          br, bg_g, bb = BG_RGB
          write_all(
              tty_fd,
              f"\x1b[?25l\x1b[0m\x1b[48;2;{br};{bg_g};{bb}m\x1b[2J\x1b[1;1H".encode("utf-8"),
          )


      def detect_tte_capabilities():
          caps = {
              "flags": set(),
              "effects": [],
              "matrix_rain_time": False,
          }
          try:
              res = subprocess.run(
                  ["tte", "--help"],
                  capture_output=True,
                  text=True,
                  timeout=5,
              )
              help_text = (res.stdout or "") + "\n" + (res.stderr or "")
          except Exception:
              return caps

          for flag in (
              "--frame-rate",
              "--canvas-width",
              "--canvas-height",
              "--reuse-canvas",
              "--anchor-canvas",
              "--anchor-text",
              "--no-eol",
              "--no-restore-cursor",
              "--existing-color-handling",
              "--terminal-background-color",
              "--ignore-terminal-dimensions",
          ):
              if flag in help_text:
                  caps["flags"].add(flag)

          for m in re.finditer(r"\{([a-z0-9_,\s]+)\}", help_text):
              raw = [tok.strip() for tok in m.group(1).split(",") if tok.strip()]
              if "beams" in raw and len(raw) >= 10:
                  caps["effects"] = raw
                  break

          if "matrix" in caps["effects"]:
              try:
                  mres = subprocess.run(
                      ["tte", "matrix", "--help"],
                      capture_output=True,
                      text=True,
                      timeout=3,
                  )
                  mhelp = (mres.stdout or "") + "\n" + (mres.stderr or "")
                  if "--rain-time" in mhelp:
                      caps["matrix_rain_time"] = True
              except Exception:
                  pass
          return caps


      def render_fg_grid(grid, use_color=True):
          """Convert a 2D cell grid of (char, rgb) or None into foreground-only ANSI art.
          Using foreground-only TrueColor guarantees transparent cell backgrounds while
          tte animates every glyph across the fullscreen canvas."""
          lines = []
          for row in grid:
              out = []
              cur_rgb = None
              # Trim trailing spaces cleanly while preserving exact box width on non-empty rows
              last_nonempty = -1
              for idx, cell in enumerate(row):
                  if cell is not None and cell[0] != " ":
                      last_nonempty = idx
              if last_nonempty < 0:
                  lines.append("")
                  continue
              for idx in range(last_nonempty + 1):
                  cell = row[idx]
                  if cell is None or cell[0] == " ":
                      out.append(" ")
                      continue
                  ch, rgb = cell
                  if use_color:
                      if rgb != cur_rgb:
                          out.append(f"\x1b[38;2;{rgb[0]};{rgb[1]};{rgb[2]}m")
                          cur_rgb = rgb
                  out.append(ch)
              if use_color and cur_rgb is not None:
                  out.append("\x1b[0m")
              lines.append("".join(out))
          return "\n".join(lines) + "\n"


      # Iconic Omarchy-style ANSI-Shadow geometric "NIXOS" wordmark (46 cols x 6 rows)
      NIXOS_SHADOW_WORD = [
          "███╗   ██╗  ██╗  ██╗  ██╗   ██████╗   ███████╗",
          "████╗  ██║  ██║  ╚██╗██╔╝  ██╔═══██╗  ██╔════╝",
          "██╔██╗ ██║  ██║   ╚███╔╝   ██║   ██║  ███████╗",
          "██║╚██╗██║  ██║   ██╔██╗   ██║   ██║  ╚════██║",
          "██║ ╚████║  ██║  ██╔╝ ██╗  ╚██████╔╝  ███████║",
          "╚═╝  ╚═══╝  ╚═╝  ╚═╝  ╚═╝   ╚═════╝   ╚══════╝",
      ]


      def seg_dist(px, py, x1, y1, x2, y2):
          vx = x2 - x1
          vy = y2 - y1
          l2 = vx * vx + vy * vy
          if l2 <= 1e-9:
              return math.hypot(px - x1, py - y1)
          t = max(0.0, min(1.0, ((px - x1) * vx + (py - y1) * vy) / l2))
          return math.hypot(px - (x1 + t * vx), py - (y1 + t * vy))


      def build_art_nixos(use_color=True):
          """Exact 1:1 Euclidean NixOS 6-lambda snowflake above Omarchy ANSI-Shadow NIXOS (46 x 22)."""
          w = 46
          flake_h = 15
          gap = 1
          word_h = len(NIXOS_SHADOW_WORD)
          h = flake_h + gap + word_h
          grid = [[None] * w for _ in range(h)]

          cx = (w - 1) * 0.5
          cy = (flake_h - 1) * 0.5
          flake_r = 6.7

          # Precompute exact 60-degree NixOS 6-lambda segments in 1:1 Euclidean world coordinates
          inner_offset = flake_r * 0.32
          arm_back = inner_offset * 0.50
          arm_tip = flake_r * 0.93
          fork_start = flake_r * 0.40
          fork_len = flake_r * 0.46

          segs = []
          for k in range(6):
              ang = k * (math.pi / 3.0) + (math.pi / 6.0)
              ux, uy = math.cos(ang), math.sin(ang)
              nx, ny = -uy, ux
              ox = nx * inner_offset
              oy = ny * inner_offset
              segs.append((ox - ux * arm_back, oy - uy * arm_back, ox + ux * arm_tip, oy + uy * arm_tip, k % 2))
              fx = ox + ux * fork_start
              fy = oy + uy * fork_start
              fang = ang + (math.pi / 3.0)
              segs.append((fx, fy, fx + math.cos(fang) * fork_len, fy + math.sin(fang) * fork_len, k % 2))

          tone0_core = lerp_rgb(ACCENT1_RGB, (120, 175, 245), 0.32)
          tone0_edge = lerp_rgb(tone0_core, BG_RGB, 0.28)
          tone1_core = lerp_rgb(ACCENT2_RGB, (165, 225, 245), 0.30)
          tone1_edge = lerp_rgb(tone1_core, BG_RGB, 0.28)

          # Rasterize snowflake directly over integer cells (x*0.5 compensates 1:2 monospace cell aspect)
          for y in range(flake_h):
              wy = y - cy
              for x in range(w):
                  wx = (x - cx) * 0.5
                  best_d = 999.0
                  best_tone = 0
                  for x1, y1, x2, y2, tone in segs:
                      d = seg_dist(wx, wy, x1, y1, x2, y2)
                      if d < best_d:
                          best_d = d
                          best_tone = tone
                  if best_d <= 0.48:
                      grid[y][x] = ("█", tone0_core if best_tone == 0 else tone1_core)
                  elif best_d <= 0.72:
                      grid[y][x] = ("▓", tone0_edge if best_tone == 0 else tone1_edge)

          # Place Omarchy-style ANSI-Shadow "NIXOS" with crisp vertical gradient + subtle 3D shadows
          shadow_chars = set("╗╔╚╝║═")
          y0 = flake_h + gap
          for r_idx, line in enumerate(NIXOS_SHADOW_WORD):
              t = r_idx / max(1.0, float(word_h - 1))
              face_rgb = lerp_rgb(lerp_rgb(FG_RGB, (245, 250, 255), 0.45), ACCENT2_RGB, t * 0.85)
              face_os = lerp_rgb(ACCENT2_RGB, ACCENT1_RGB, t)
              shad_rgb = lerp_rgb(ACCENT1_RGB, MUTED_RGB, 0.45)
              for c_idx, ch in enumerate(line):
                  if ch == " " or c_idx >= w:
                      continue
                  if ch in shadow_chars:
                      grid[y0 + r_idx][c_idx] = (ch, shad_rgb)
                  else:
                      grid[y0 + r_idx][c_idx] = (ch, face_rgb if c_idx < 26 else face_os)

          return render_fg_grid(grid, use_color)


      def build_art_sakura(use_color=True):
          """Lush integer-grid Moyogi Zen Sakura Bonsai + balanced drifting petals (72 x 24)."""
          w, h = 72, 24
          grid = [[None] * w for _ in range(h)]
          cx = (w - 1) * 0.5
          base_y = 20.5

          bark_hi = (172, 134, 118)
          bark_light = (138, 102, 88)
          bark_mid = (98, 68, 58)
          bark_shadow = (64, 42, 36)

          rock_dark = (52, 58, 72)
          rock_mid = (74, 82, 98)
          moss_bright = lerp_rgb(OK_RGB, (235, 250, 220), 0.35)
          moss_mid = OK_RGB
          moss_deep = lerp_rgb(OK_RGB, BG_RGB, 0.38)

          sakura_hi = (255, 236, 242)
          sakura_bright = (255, 190, 206)
          sakura_mid = (255, 146, 174)
          sakura_deep = (232, 102, 138)
          sakura_shadow = (192, 72, 106)

          # 1. Central Zen moss island + balanced left & right stepping moss stones
          mounds = (
              (cx, 21.3, 13.5, 2.0),
              (13.0, 21.8, 5.5, 1.3),
              (58.0, 21.8, 5.5, 1.3),
          )
          for m_cx, m_cy, rx, ry in mounds:
              for y in range(h):
                  for x in range(w):
                      nx = (x - m_cx) / rx
                      ny = (y - m_cy) / ry
                      ripple = 0.08 * math.sin(x * 0.45)
                      if nx * nx + (ny - ripple) * (ny - ripple) <= 1.0:
                          if ny < -0.20:
                              grid[y][x] = ("█" if (x + y) % 2 == 0 else "▓", moss_bright if nx < 0.1 else moss_mid)
                          elif ny <= 0.28:
                              grid[y][x] = ("▓", moss_mid if (x + y) % 2 == 0 else moss_deep)
                          else:
                              grid[y][x] = ("█", rock_mid if nx < 0.25 else rock_dark)

          # 2. Cubic Bezier Moyogi trunk & symmetric boughs (evaluated over exact integer cells)
          def sample_bezier(p0, p1, p2, p3, r0, r1, steps=28):
              pts = []
              for s in range(steps + 1):
                  u = s / float(steps)
                  inv = 1.0 - u
                  bx = (inv ** 3) * p0[0] + 3 * (inv ** 2) * u * p1[0] + 3 * inv * (u ** 2) * p2[0] + (u ** 3) * p3[0]
                  by = (inv ** 3) * p0[1] + 3 * (inv ** 2) * u * p1[1] + 3 * inv * (u ** 2) * p2[1] + (u ** 3) * p3[1]
                  pts.append((bx, by, r0 + (r1 - r0) * u))
              return pts

          limbs = [
              # Main S-curved Moyogi trunk
              sample_bezier((cx, 20.5), (cx - 7.5, 15.5), (cx + 6.5, 10.2), (cx, 5.2), 1.65, 0.58, 36),
              # Symmetric root flare (nebari)
              sample_bezier((cx - 1.0, 20.2), (cx - 4.0, 20.7), (cx - 6.8, 21.1), (cx - 9.2, 21.4), 0.95, 0.42, 16),
              sample_bezier((cx + 1.0, 20.2), (cx + 4.0, 20.7), (cx + 6.8, 21.1), (cx + 9.2, 21.4), 0.95, 0.42, 16),
              # Left sweeping lower & mid boughs
              sample_bezier((cx - 3.5, 15.2), (cx - 10.5, 13.8), (cx - 16.5, 15.0), (cx - 21.5, 13.6), 0.95, 0.45, 24),
              sample_bezier((cx - 9.5, 14.2), (cx - 12.2, 12.2), (cx - 14.0, 11.4), (cx - 16.0, 10.6), 0.65, 0.40, 16),
              # Right sweeping lower & mid boughs
              sample_bezier((cx + 1.5, 13.6), (cx + 9.2, 12.0), (cx + 16.0, 13.8), (cx + 21.5, 12.5), 0.92, 0.45, 24),
              sample_bezier((cx + 8.5, 12.6), (cx + 11.5, 10.8), (cx + 13.8, 10.0), (cx + 16.0, 9.4), 0.62, 0.40, 16),
              # Upper left & right crown branches
              sample_bezier((cx + 0.5, 9.6), (cx - 4.5, 8.2), (cx - 9.2, 8.6), (cx - 13.5, 7.6), 0.72, 0.40, 18),
              sample_bezier((cx + 2.0, 8.8), (cx + 6.5, 7.4), (cx + 10.2, 8.0), (cx + 13.8, 7.0), 0.70, 0.40, 18),
          ]

          for limb in limbs:
              for y in range(h):
                  for x in range(w):
                      best_norm = 999.0
                      best_dx = 0.0
                      best_dy = 0.0
                      for bx, by, rad in limb:
                          dx = (x - bx) * 0.52
                          dy = y - by
                          d = math.hypot(dx, dy) / max(0.35, rad)
                          if d < best_norm:
                              best_norm = d
                              best_dx = dx
                              best_dy = dy
                      if best_norm <= 1.0:
                          light = best_dx * 0.55 - best_dy * 0.45
                          if light > 0.30:
                              col = bark_hi
                          elif light > -0.05:
                              col = bark_light
                          elif light > -0.40:
                              col = bark_mid
                          else:
                              col = bark_shadow
                          grid[y][x] = ("█" if best_norm < 0.78 else "▓", col)

          # 3. Solid lush sakura cloud-pads (direct integer-cell scan -> 0% stripe bugs!)
          pads = (
              (cx - 21.5, 12.6, 8.5, 2.3),
              (cx + 21.5, 11.6, 8.5, 2.3),
              (cx - 16.0, 9.6, 7.8, 2.1),
              (cx + 16.0, 8.6, 7.8, 2.1),
              (cx - 13.0, 6.8, 8.0, 2.1),
              (cx + 13.0, 6.2, 8.0, 2.1),
              (cx - 5.5, 5.2, 7.2, 2.0),
              (cx + 5.5, 5.2, 7.2, 2.0),
              (cx, 3.9, 10.5, 2.5),
          )
          for pcx, pcy, prx, pry in pads:
              for y in range(1, 20):
                  for x in range(1, w - 1):
                      nx = (x - pcx) / prx
                      ny = (y - pcy) / (pry * (0.76 if y > pcy else 1.06))
                      bump = 0.11 * math.sin(x * 0.65 + y * 0.9) + 0.08 * math.cos(x * 0.42 - y * 0.75)
                      d2 = nx * nx + ny * ny - bump
                      if d2 <= 1.0:
                          eh = ((x * 73 + y * 37) & 15) / 15.0
                          v_shade = -ny + 0.16 * nx + (eh - 0.5) * 0.25
                          if v_shade > 0.52:
                              col = sakura_hi
                          elif v_shade > 0.18:
                              col = sakura_bright
                          elif v_shade > -0.18:
                              col = sakura_mid
                          elif v_shade > -0.50:
                              col = sakura_deep
                          else:
                              col = sakura_shadow
                          ch = "█" if d2 < 0.72 else ("▓" if d2 < 0.90 else "▒")
                          grid[y][x] = (ch, col)

          # 4. Symmetrical drifting sakura petals across left, center, and right skies
          rng = random.Random()
          petal_cols = (sakura_hi, sakura_bright, sakura_mid, sakura_deep)
          petal_syms = ("✿", "❀", "•", "·")
          for zone_min, zone_max, count in ((1, 21, 14), (22, 49, 10), (50, w - 2, 14)):
              for _ in range(count):
                  px = rng.randint(zone_min, zone_max)
                  py = rng.randint(1, h - 2)
                  if grid[py][px] is None:
                      grid[py][px] = (rng.choice(petal_syms), rng.choice(petal_cols))

          return render_fg_grid(grid, use_color)


      def build_art_lightning(use_color=True):
          """Fully randomized Elden Ring forked lightning salvos (76 x 24).
          NO clouds at top, NO ground line at bottom — fresh random bolts & colors every run."""
          w, h = 76, 24
          grid = [[None] * w for _ in range(h)]
          rng = random.Random()

          palettes = {
              "gold": (
                  (255, 254, 240),
                  (255, 215, 0),
                  (245, 158, 11),
                  (180, 83, 9),
              ),
              "red": (
                  (255, 228, 232),
                  (255, 23, 68),
                  (220, 38, 38),
                  (145, 22, 58),
              ),
              "cyan": (
                  (245, 252, 255),
                  (56, 189, 248),
                  (14, 165, 233),
                  (59, 130, 246),
              ),
          }

          def make_bolt_pts(x0, y0, x1, y1, sway, depth=4):
              pts = [(float(x0), float(y0)), (float(x1), float(y1))]
              disp = float(sway)
              for _ in range(depth):
                  nxt = [pts[0]]
                  for i in range(len(pts) - 1):
                      ax, ay = pts[i]
                      bx, by = pts[i + 1]
                      nxt.append(((ax + bx) * 0.5 + rng.uniform(-disp, disp), (ay + by) * 0.5))
                      nxt.append((bx, by))
                  pts = nxt
                  disp *= rng.uniform(0.48, 0.58)
              return pts

          def raster_seg(x1, y1, x2, y2, core_c, inner_c, outer_c, is_trunk=True):
              steps = max(2, int(max(abs(x2 - x1), abs(y2 - y1)) * 2.0))
              for s in range(steps + 1):
                  u = s / float(steps)
                  px = int(round(x1 + (x2 - x1) * u))
                  py = int(round(y1 + (y2 - y1) * u))
                  if not (0 <= px < w and 0 <= py < h):
                      continue
                  if is_trunk:
                      for ox, ch, col in ((-2, "░", outer_c), (2, "░", outer_c), (-1, "▓", inner_c), (1, "▓", inner_c)):
                          nx = px + ox
                          if 0 <= nx < w and (grid[py][nx] is None or grid[py][nx][0] in ("░", "▒", "·", "•")):
                              grid[py][nx] = (ch, col)
                      grid[py][px] = ("█", core_c)
                  else:
                      for ox in (-1, 1):
                          nx = px + ox
                          if 0 <= nx < w and grid[py][nx] is None:
                              grid[py][nx] = ("░", outer_c)
                      if grid[py][px] is None or grid[py][px][0] != "█":
                          grid[py][px] = ("▓", inner_c)

          # Balanced 2 or 3 bolts spanning left, center, and right zones
          zones = [(4, 24), (27, 48), (51, w - 5)]
          rng.shuffle(zones)
          bolt_n = rng.choice((2, 3, 3))
          color_keys = ["gold", "red", "cyan"]
          rng.shuffle(color_keys)

          for b_i in range(bolt_n):
              z_lo, z_hi = zones[b_i]
              # Mix Elden Ring colors across multi-bolt salvos or match dramatically
              pal_key = color_keys[b_i % len(color_keys)] if rng.random() < 0.72 else color_keys[0]
              core_c, inner_c, outer_c, glow_c = palettes[pal_key]

              x0 = rng.randint(z_lo, z_hi)
              x1 = max(3, min(w - 4, x0 + rng.randint(-14, 14)))
              pts = make_bolt_pts(x0, 0, x1, h - 1, rng.uniform(5.0, 11.0), depth=4)

              # Draw primary forks (2..4 per bolt) + sub-forks
              fork_n = rng.randint(2, 4)
              idxs = list(range(2, max(3, len(pts) - 3)))
              rng.shuffle(idxs)
              for f_i, idx in enumerate(idxs[:fork_n]):
                  bx, by = pts[idx]
                  b_dir = -1 if (f_i % 2 == 0) else 1
                  b_ex = max(1, min(w - 2, bx + b_dir * rng.uniform(6.0, 15.0)))
                  b_ey = min(h - 1, by + rng.uniform(4.0, 10.0))
                  b_pts = make_bolt_pts(bx, by, b_ex, b_ey, rng.uniform(1.8, 4.2), depth=3)
                  for j in range(len(b_pts) - 1):
                      raster_seg(b_pts[j][0], b_pts[j][1], b_pts[j + 1][0], b_pts[j + 1][1], core_c, inner_c, outer_c, False)

              # Draw main trunk on top
              for j in range(len(pts) - 1):
                  raster_seg(pts[j][0], pts[j][1], pts[j + 1][0], pts[j + 1][1], core_c, inner_c, outer_c, True)

              # Bottom impact sparks splashing directly off bottom row (y = h - 1, NO ground line!)
              for _ in range(rng.randint(8, 14)):
                  sx = int(round(x1 + rng.uniform(-7.0, 7.0)))
                  sy = h - 1 - rng.randint(0, 3)
                  if 0 <= sx < w and 0 <= sy < h and grid[sy][sx] is None:
                      grid[sy][sx] = (
                          rng.choice(("✦", "✧", "•", "·")),
                          rng.choice((core_c, inner_c, glow_c)),
                      )

          return render_fg_grid(grid, use_color)


      class PixelCanvas:
          """60 FPS half-block pixel canvas used for crisp full-screen transitions."""

          def __init__(self, rows, cols, bg_rgb=BG_RGB):
              self.rows = rows
              self.cols = cols
              self.w = cols
              self.h = rows * 2
              self.bg_rgb = bg_rgb
              self.grid = [{} for _ in range(rows)]

          def set_px(self, px, py, rgb):
              if 0 <= px < self.w and 0 <= py < self.h:
                  r = py >> 1
                  row = self.grid[r]
                  pair = row.get(px)
                  if pair is None:
                      if py & 1:
                          row[px] = [self.bg_rgb, rgb]
                      else:
                          row[px] = [rgb, self.bg_rgb]
                  else:
                      pair[py & 1] = rgb

          def flush(self, tty_fd):
              br, bg_g, bb = self.bg_rgb
              bg_sgr = f"\x1b[48;2;{br};{bg_g};{bb}m"
              parts = [f"\x1b[?2026h\x1b[?7l\x1b[?25l\x1b[0m{bg_sgr}"]
              cur_fg = None
              cur_bg = self.bg_rgb

              for r in range(self.rows):
                  tr = r + 1
                  row = self.grid[r]
                  if cur_bg != self.bg_rgb:
                      parts.append(bg_sgr)
                      cur_bg = self.bg_rgb
                  parts.append(f"\x1b[{tr};1H\x1b[2K")
                  if not row:
                      continue

                  last_x = -2
                  for x in sorted(row.keys()):
                      top_c, bot_c = row[x]
                      if top_c == self.bg_rgb and bot_c == self.bg_rgb:
                          continue
                      if x != last_x + 1:
                          if cur_bg != self.bg_rgb:
                              parts.append(bg_sgr)
                              cur_bg = self.bg_rgb
                          parts.append(f"\x1b[{tr};{x + 1}H")
                      if top_c == bot_c:
                          if cur_bg != top_c:
                              parts.append(f"\x1b[48;2;{top_c[0]};{top_c[1]};{top_c[2]}m")
                              cur_bg = top_c
                          parts.append(" ")
                      elif top_c == self.bg_rgb:
                          if cur_fg != bot_c:
                              parts.append(f"\x1b[38;2;{bot_c[0]};{bot_c[1]};{bot_c[2]}m")
                              cur_fg = bot_c
                          if cur_bg != self.bg_rgb:
                              parts.append(bg_sgr)
                              cur_bg = self.bg_rgb
                          parts.append("▄")
                      else:
                          if cur_fg != top_c:
                              parts.append(f"\x1b[38;2;{top_c[0]};{top_c[1]};{top_c[2]}m")
                              cur_fg = top_c
                          if cur_bg != bot_c:
                              parts.append(f"\x1b[48;2;{bot_c[0]};{bot_c[1]};{bot_c[2]}m")
                              cur_bg = bot_c
                          parts.append("▀")
                      last_x = x

              parts.append("\x1b[0m\x1b[?7h\x1b[?25l\x1b[?2026l")
              write_all(tty_fd, "".join(parts).encode("utf-8"))


      def generate_pixel_bolt(x_start, y_start, x_end, y_end, sway, rng, depth=5):
          pts = [(float(x_start), float(y_start)), (float(x_end), float(y_end))]
          disp = float(sway)
          for _ in range(depth):
              new_pts = [pts[0]]
              for i in range(len(pts) - 1):
                  x1, y1 = pts[i]
                  x2, y2 = pts[i + 1]
                  mx = (x1 + x2) * 0.5 + rng.uniform(-disp, disp)
                  my = (y1 + y2) * 0.5
                  new_pts.append((mx, my))
                  new_pts.append((x2, y2))
              pts = new_pts
              disp *= rng.uniform(0.48, 0.58)

          pixels = []
          total_dy = max(1.0, float(y_end - y_start))
          for i in range(len(pts) - 1):
              x1, y1 = pts[i]
              x2, y2 = pts[i + 1]
              steps = max(1, int(max(abs(x2 - x1), abs(y2 - y1)) * 1.6))
              dx = x2 - x1
              dy = y2 - y1
              for s in range(steps + 1):
                  t = s / float(steps)
                  px = int(round(x1 + dx * t))
                  py = int(round(y1 + dy * t))
                  prog = max(0.0, min(1.0, (py - y_start) / total_dy))
                  pixels.append((px, py, prog))
          return pts, pixels


      def build_random_storm_strike(w, h, rng, zone_hint=None):
          palettes = {
              "gold": {
                  "core": (255, 254, 240),
                  "inner": (255, 215, 0),
                  "outer": (245, 158, 11),
                  "afterglow": (180, 83, 9),
                  "flash": (56, 48, 22),
              },
              "red": {
                  "core": (255, 228, 232),
                  "inner": (255, 23, 68),
                  "outer": (220, 38, 38),
                  "afterglow": (136, 19, 55),
                  "flash": (54, 20, 30),
              },
              "cyan": {
                  "core": (245, 252, 255),
                  "inner": (56, 189, 248),
                  "outer": (14, 165, 233),
                  "afterglow": (59, 130, 246),
                  "flash": (28, 42, 64),
              },
          }
          pal = palettes[rng.choice(("gold", "red", "cyan"))]

          if zone_hint == "left":
              x0 = rng.randint(max(3, int(w * 0.06)), max(5, int(w * 0.34)))
          elif zone_hint == "right":
              x0 = rng.randint(max(5, int(w * 0.66)), max(7, min(w - 4, int(w * 0.94))))
          elif zone_hint == "center":
              x0 = rng.randint(max(5, int(w * 0.32)), max(7, int(w * 0.68)))
          else:
              x0 = rng.randint(max(3, int(w * 0.06)), max(5, min(w - 4, int(w * 0.94))))

          angle_span = max(6, int(w * rng.uniform(0.08, 0.32)))
          x1 = max(3, min(w - 4, x0 + rng.randint(-angle_span, angle_span)))

          jagged = w * rng.uniform(0.06, 0.22)
          # Strike all the way from very top pixel (py = 0) to the absolute bottom edge (py = h - 1)
          trunk_pts, trunk_px = generate_pixel_bolt(x0, 0, x1, h - 1, jagged, rng, depth=5)

          fork_count = rng.randint(1, 6)
          candidate_idxs = list(range(2, max(3, len(trunk_pts) - 3)))
          rng.shuffle(candidate_idxs)
          branches = []
          for f_i, idx in enumerate(candidate_idxs[:fork_count]):
              bx, by = trunk_pts[idx]
              b_len_y = rng.randint(max(6, int(h * 0.12)), max(10, int(h * 0.45)))
              b_end_y = min(h - 1, int(by + b_len_y))
              b_dir = -1 if (f_i % 2 == 0) else 1
              if rng.random() < 0.25:
                  b_dir = -b_dir
              b_spread = rng.randint(max(5, int(w * 0.05)), max(10, int(w * 0.24)))
              b_end_x = max(2, min(w - 3, int(bx + b_dir * b_spread)))
              _, b_px = generate_pixel_bolt(bx, by, b_end_x, b_end_y, w * rng.uniform(0.025, 0.065), rng, depth=4)
              b_prog = by / max(1.0, float(h - 1))
              branches.append((b_prog, b_px))
              if len(b_px) > 8 and rng.random() < 0.50:
                  sbx, sby, _ = b_px[rng.randint(len(b_px) // 3, (len(b_px) * 2) // 3)]
                  sb_end_y = min(h - 1, sby + rng.randint(5, max(8, int(h * 0.20))))
                  sb_dir = -b_dir if rng.random() < 0.6 else b_dir
                  sb_end_x = max(2, min(w - 3, sbx + sb_dir * rng.randint(4, max(8, int(w * 0.11)))))
                  _, sb_px = generate_pixel_bolt(sbx, sby, sb_end_x, sb_end_y, w * 0.025, rng, depth=3)
                  branches.append((b_prog, sb_px))

          # Impact sparks splashing directly off the absolute bottom edge (py = h - 1), NO ground line
          spark_n = rng.randint(20, 36)
          sparks = []
          for i in range(spark_n):
              ang = -math.pi * (0.06 + 0.88 * (i / max(1.0, float(spark_n - 1)))) + rng.uniform(-0.08, 0.08)
              spd = rng.uniform(0.55, 2.25)
              sparks.append([float(x1), float(h - 1), math.cos(ang) * spd, math.sin(ang) * spd * 0.85])

          leader_frames = rng.randint(2, 9)
          flash_frames = rng.randint(3, 8)
          decay_frames = rng.randint(18, 46)
          thickness = rng.choice((1, 2, 2, 3))
          restrike_offsets = set()
          for _ in range(rng.choice((0, 1, 1, 2))):
              restrike_offsets.add(leader_frames + flash_frames + rng.randint(3, max(4, decay_frames // 2)))

          return {
              "pal": pal,
              "trunk": trunk_px,
              "branches": branches,
              "sparks": sparks,
              "age": 0,
              "leader_frames": leader_frames,
              "flash_frames": flash_frames,
              "decay_frames": decay_frames,
              "thickness": thickness,
              "restrikes": restrike_offsets,
          }


      def run_lightning_storm(tty_fd):
          """Fullscreen 60 FPS live Elden Ring lightning storm striking directly to the very bottom
          edge of the screen (py = H - 1). Zero clouds at top, zero ground line at bottom."""
          rows, cols = get_term_size(tty_fd)
          total_frames = 1440
          frame_dt = 0.0166

          rng = random.Random()
          active_strikes = []
          zone_bag = ["left", "center", "right"]
          rng.shuffle(zone_bag)

          def pop_zone():
              if not zone_bag:
                  zone_bag.extend(("left", "center", "right"))
                  rng.shuffle(zone_bag)
              return zone_bag.pop()

          next_strike_frame = rng.randint(12, 32)
          clear_to_bg(tty_fd)

          for frame in range(total_frames):
              t0 = time.monotonic()
              rows, cols = get_term_size(tty_fd)
              w = cols
              h = rows * 2

              if frame >= next_strike_frame and frame < total_frames - 60:
                  salvo_roll = rng.random()
                  salvo_n = 1 if salvo_roll < 0.58 else (2 if salvo_roll < 0.88 else 3)
                  for _ in range(salvo_n):
                      z = pop_zone() if rng.random() < 0.82 else None
                      active_strikes.append(build_random_storm_strike(w, h, rng, zone_hint=z))
                  next_strike_frame = frame + rng.randint(28, 105)

              flash = 0.0
              flash_color = BG_RGB
              for st in active_strikes:
                  age = st["age"]
                  lf = st["leader_frames"]
                  ff = st["flash_frames"]
                  if lf <= age < lf + ff or age in st["restrikes"]:
                      st_f = 1.0 if age == lf else 0.72
                  elif lf + ff <= age <= lf + ff + 16:
                      st_f = max(0.0, 0.50 * (1.0 - (age - lf - ff) / 16.0))
                  else:
                      st_f = 0.0
                  if st_f > flash:
                      flash = st_f
                      flash_color = st["pal"]["flash"]

              frame_bg = lerp_rgb(BG_RGB, flash_color, flash * 0.55)
              canvas = PixelCanvas(rows, cols, frame_bg)

              still_active = []
              for st in active_strikes:
                  age = st["age"]
                  lf = st["leader_frames"]
                  ff = st["flash_frames"]
                  df = st["decay_frames"]
                  thick = st["thickness"]
                  pal = st["pal"]
                  core_c = pal["core"]
                  inner_c = pal["inner"]
                  outer_c = pal["outer"]
                  after_c = pal["afterglow"]
                  is_restrike = age in st["restrikes"]

                  if age < lf:
                      reach = (age + 1) / float(lf)
                      for px, py, prog in st["trunk"]:
                          if prog <= reach:
                              canvas.set_px(px, py, inner_c)
                      for b_prog, b_px in st["branches"]:
                          if b_prog <= reach:
                              for px, py, _ in b_px:
                                  canvas.set_px(px, py, outer_c)
                  elif age < lf + ff or is_restrike:
                      is_peak = (age == lf) or is_restrike
                      for _, b_px in st["branches"]:
                          for px, py, _ in b_px:
                              if is_peak and thick >= 2:
                                  canvas.set_px(px - 1, py, outer_c)
                                  canvas.set_px(px + 1, py, outer_c)
                              canvas.set_px(px, py, core_c if is_peak else inner_c)

                      for px, py, _ in st["trunk"]:
                          if thick >= 3 and is_peak:
                              canvas.set_px(px - 2, py, outer_c)
                              canvas.set_px(px + 2, py, outer_c)
                          if thick >= 2 or is_peak:
                              canvas.set_px(px - 1, py, inner_c if is_peak else outer_c)
                              canvas.set_px(px + 1, py, inner_c if is_peak else outer_c)
                          canvas.set_px(px, py, core_c)
                  else:
                      decay = (age - lf - ff) / max(1.0, float(df))
                      if decay < 0.45:
                          c_main = lerp_rgb(inner_c, outer_c, decay / 0.45)
                      else:
                          c_main = lerp_rgb(outer_c, after_c, (decay - 0.45) / 0.55)
                          c_main = lerp_rgb(c_main, frame_bg, decay * 0.68)

                      if decay < 0.65:
                          c_br = lerp_rgb(outer_c, frame_bg, decay / 0.65)
                          for _, b_px in st["branches"]:
                              for idx, (px, py, _) in enumerate(b_px):
                                  if idx % 2 == 0:
                                      canvas.set_px(px, py, c_br)

                      for idx, (px, py, _) in enumerate(st["trunk"]):
                          if decay > 0.55 and (idx + age) % 3 == 0:
                              continue
                          canvas.set_px(px, py, c_main)
                          if decay < 0.35 and thick >= 2:
                              canvas.set_px(px - 1, py, lerp_rgb(after_c, frame_bg, 0.45))
                              canvas.set_px(px + 1, py, lerp_rgb(after_c, frame_bg, 0.45))

                  # Bottom-edge impact sparks splashing directly off py = h - 1
                  if lf <= age <= lf + 34:
                      dt_s = (age - lf + 1) * 0.65
                      s_prog = (age - lf) / 34.0
                      s_col = lerp_rgb(core_c if s_prog < 0.3 else inner_c, after_c, s_prog)
                      for sp in st["sparks"]:
                          sx = int(round(sp[0] + sp[2] * dt_s))
                          sy = int(round(sp[1] + sp[3] * dt_s + 0.08 * (dt_s * dt_s)))
                          if 0 <= sx < w and 0 <= sy < h:
                              canvas.set_px(sx, sy, s_col)
                              if s_prog < 0.45 and sy + 1 < h:
                                  canvas.set_px(sx, sy + 1, outer_c)

                  st["age"] += 1
                  if st["age"] <= lf + ff + df:
                      still_active.append(st)
              active_strikes = still_active

              canvas.flush(tty_fd)
              elapsed = time.monotonic() - t0
              if wait_or_input(tty_fd, max(0.002, frame_dt - elapsed)):
                  return True
          return False


      EXCLUDED_EFFECTS = {"dev_worm", "print", "highlight"}

      FALLBACK_EFFECTS = [
          "beams",
          "binarypath",
          "blackhole",
          "bouncyballs",
          "bubbles",
          "burn",
          "colorshift",
          "crumble",
          "decrypt",
          "errorcorrect",
          "expand",
          "fireworks",
          "laseretch",
          "matrix",
          "middleout",
          "orbittingvolley",
          "overflow",
          "pour",
          "rain",
          "randomsequence",
          "rings",
          "scattered",
          "slice",
          "slide",
          "spotlights",
          "spray",
          "swarm",
          "sweep",
          "synthgrid",
          "unstable",
          "vhstape",
          "waves",
          "wipe",
      ]

      SCENE_EFFECT_PREFS = {
          "nixos": [
              "beams",
              "matrix",
              "synthgrid",
              "blackhole",
              "rings",
              "decrypt",
              "laseretch",
              "waves",
              "fireworks",
              "binarypath",
              "spotlights",
              "orbittingvolley",
              "sweep",
              "vhstape",
              "swarm",
              "middleout",
              "expand",
              "rain",
              "crumble",
              "slice",
              "slide",
              "spray",
              "scattered",
              "unstable",
              "wipe",
              "pour",
              "burn",
              "colorshift",
              "errorcorrect",
              "randomsequence",
              "bubbles",
              "bouncyballs",
          ],
          "sakura": [
              "rain",
              "waves",
              "swarm",
              "bubbles",
              "blackhole",
              "rings",
              "fireworks",
              "spotlights",
              "beams",
              "middleout",
              "expand",
              "pour",
              "scattered",
              "slide",
              "sweep",
              "wipe",
              "orbittingvolley",
              "colorshift",
              "bouncyballs",
              "randomsequence",
          ],
          "lightning": [
              "beams",
              "laseretch",
              "fireworks",
              "vhstape",
              "unstable",
              "crumble",
              "slice",
              "synthgrid",
              "spotlights",
              "blackhole",
              "waves",
              "rings",
              "spray",
              "matrix",
              "rain",
              "sweep",
              "binarypath",
              "orbittingvolley",
              "expand",
          ],
      }


      def build_effect_pool(token, caps):
          avail = [
              e
              for e in (caps["effects"] if caps["effects"] else FALLBACK_EFFECTS)
              if e not in EXCLUDED_EFFECTS and not e.startswith("dev_")
          ]
          avail_set = set(avail)
          prefs = [e for e in SCENE_EFFECT_PREFS.get(token, avail) if e in avail_set]
          # Also include any brand-new upstream effects in avail
          extras = [e for e in avail if e not in set(prefs)]
          pool = prefs + extras
          return pool if pool else ["beams"]


      def kill_proc_group(proc):
          if proc is None or proc.poll() is not None:
              return
          try:
              os.killpg(proc.pid, signal.SIGTERM)
          except OSError:
              try:
                  proc.terminate()
              except OSError:
                  pass
          deadline = time.monotonic() + 0.25
          while time.monotonic() < deadline:
              if proc.poll() is not None:
                  return
              time.sleep(0.02)
          if proc.poll() is None:
              try:
                  os.killpg(proc.pid, signal.SIGKILL)
              except OSError:
                  try:
                      proc.kill()
                  except OSError:
                      pass
              try:
                  proc.wait(timeout=0.2)
              except Exception:
                  pass


      def build_art_for_token(token, use_color):
          if token == "nixos":
              return build_art_nixos(use_color)
          if token == "sakura":
              return build_art_sakura(use_color)
          if token == "lightning":
              return build_art_lightning(use_color)
          return build_art_nixos(use_color)


      def run_tte_scene(tty_fd, token, effect, caps):
          """Run native Omarchy-style tte animation directly on tty_fd at 60 FPS
          with zero PTY proxy, zero truncation, exact centering, and instant input exit."""
          flags = caps["flags"]
          use_color = "--existing-color-handling" in flags
          art_text = build_art_for_token(token, use_color)

          rows, cols = get_term_size(tty_fd)
          art_path = None
          try:
              fd_tmp, art_path = tempfile.mkstemp(prefix="ss-art-", suffix=".txt", dir=STATE_DIR)
              with os.fdopen(fd_tmp, "w", encoding="utf-8") as fh:
                  fh.write(art_text)

              cmd = ["tte", "-i", art_path]
              if "--frame-rate" in flags:
                  cmd.extend(["--frame-rate", "60"])
              if "--canvas-width" in flags and "--canvas-height" in flags:
                  if "--reuse-canvas" in flags:
                      cmd.extend(["--canvas-width", "0", "--canvas-height", "0", "--reuse-canvas"])
                  else:
                      cmd.extend(["--canvas-width", str(cols), "--canvas-height", str(max(10, rows - 1))])
              if "--anchor-canvas" in flags:
                  cmd.extend(["--anchor-canvas", "c"])
              if "--anchor-text" in flags:
                  cmd.extend(["--anchor-text", "c"])
              if "--no-eol" in flags:
                  cmd.append("--no-eol")
              if "--no-restore-cursor" in flags:
                  cmd.append("--no-restore-cursor")
              if use_color:
                  cmd.extend(["--existing-color-handling", "dynamic"])
              if "--terminal-background-color" in flags:
                  cmd.extend(["--terminal-background-color", BG_BASE])

              cmd.append(effect)
              if effect == "matrix" and caps["matrix_rain_time"]:
                  cmd.extend(["--rain-time", "6"])

              clear_to_bg(tty_fd)
              t_start = time.monotonic()
              proc = subprocess.Popen(
                  cmd,
                  stdin=subprocess.DEVNULL,
                  stdout=tty_fd,
                  stderr=subprocess.DEVNULL,
                  start_new_session=True,
              )

              try:
                  while proc.poll() is None:
                      if STOP_REQUESTED or poll_user_input(tty_fd, 0.02):
                          kill_proc_group(proc)
                          return True
              finally:
                  kill_proc_group(proc)

              # Fallback once with minimal safe flags if an unfamiliar effect/flag rejected cleanly
              if proc.returncode != 0 and (time.monotonic() - t_start) < 0.25 and not STOP_REQUESTED:
                  plain_art = build_art_for_token(token, False)
                  with open(art_path, "w", encoding="utf-8") as fh:
                      fh.write(plain_art)
                  clear_to_bg(tty_fd)
                  fb_cmd = ["tte", "-i", art_path, "--frame-rate", "60"]
                  if "--canvas-width" in flags and "--canvas-height" in flags and "--reuse-canvas" in flags:
                      fb_cmd.extend(["--canvas-width", "0", "--canvas-height", "0", "--reuse-canvas"])
                  if "--anchor-canvas" in flags:
                      fb_cmd.extend(["--anchor-canvas", "c"])
                  if "--anchor-text" in flags:
                      fb_cmd.extend(["--anchor-text", "c"])
                  if "--no-eol" in flags:
                      fb_cmd.append("--no-eol")
                  if "--no-restore-cursor" in flags:
                      fb_cmd.append("--no-restore-cursor")
                  fb_cmd.append("beams")
                  fb_proc = subprocess.Popen(
                      fb_cmd,
                      stdin=subprocess.DEVNULL,
                      stdout=tty_fd,
                      stderr=subprocess.DEVNULL,
                      start_new_session=True,
                  )
                  try:
                      while fb_proc.poll() is None:
                          if STOP_REQUESTED or poll_user_input(tty_fd, 0.02):
                              kill_proc_group(fb_proc)
                              return True
                  finally:
                      kill_proc_group(fb_proc)

              # Ensure cursor stays strictly hidden and hold completed artwork briefly to admire
              write_all(tty_fd, b"\x1b[?25l")
              if wait_or_input(tty_fd, 2.2):
                  return True
              return False
          finally:
              if art_path:
                  try:
                      os.unlink(art_path)
                  except OSError:
                      pass


      def next_playlist(mode, last_token):
          if mode in ("lightning", "storm", "sakura", "nixos"):
              return [mode]
          items = ["nixos", "sakura", "lightning", "storm"]
          random.shuffle(items)
          if last_token and items[0] == last_token:
              items.append(items.pop(0))
          return items


      def main():
          global STOP_REQUESTED
          try:
              tty_fd = os.open("/dev/tty", os.O_RDWR | os.O_NOCTTY)
          except OSError:
              tty_fd = 0

          saved_termios = None
          try:
              saved_termios = termios.tcgetattr(tty_fd)
          except termios.error:
              pass

          def handle_sig(_signum, _frame):
              global STOP_REQUESTED
              STOP_REQUESTED = True

          signal.signal(signal.SIGTERM, handle_sig)
          signal.signal(signal.SIGINT, handle_sig)
          signal.signal(signal.SIGHUP, handle_sig)

          try:
              if saved_termios is not None:
                  set_input_raw_keep_opost(tty_fd)

              br, bg_g, bb = BG_RGB
              write_all(
                  tty_fd,
                  f"\x1b[?1049h\x1b[?25l\x1b[0m\x1b[48;2;{br};{bg_g};{bb}m\x1b[2J\x1b[1;1H\x1b[?1003h\x1b[?1006h".encode(
                      "utf-8"
                  ),
              )

              caps = detect_tte_capabilities()
              effect_bags = {}
              last_effect = None

              def pick_effect(token):
                  nonlocal last_effect
                  if EFFECT_OVERRIDE:
                      if not caps["effects"] or EFFECT_OVERRIDE in caps["effects"]:
                          return EFFECT_OVERRIDE
                  bag = effect_bags.get(token)
                  if not bag:
                      bag = build_effect_pool(token, caps)
                      random.shuffle(bag)
                      if last_effect and len(bag) > 1 and bag[-1] == last_effect:
                          bag.insert(0, bag.pop())
                      effect_bags[token] = bag
                  eff = bag.pop()
                  last_effect = eff
                  return eff

              # Wait briefly for Niri fullscreen configure + startup input grace window
              time.sleep(0.3)
              while True:
                  try:
                      r, _, _ = select.select([tty_fd], [], [], 0.01)
                  except InterruptedError:
                      continue
                  if not r:
                      break
                  try:
                      if not os.read(tty_fd, 4096):
                          break
                  except OSError:
                      break

              last_token = None
              while not STOP_REQUESTED:
                  playlist = next_playlist(MODE, last_token)
                  for token in playlist:
                      if STOP_REQUESTED:
                          break
                      last_token = token

                      if token == "storm":
                          exited = run_lightning_storm(tty_fd)
                      else:
                          effect = pick_effect(token)
                          exited = run_tte_scene(tty_fd, token, effect, caps)
                      if exited or STOP_REQUESTED:
                          STOP_REQUESTED = True
                          break
          finally:
              write_all(
                  tty_fd,
                  b"\x1b[?2026l\x1b[?1003l\x1b[?1006l\x1b[0m\x1b[?25h\x1b[?1049l",
              )
              if saved_termios is not None:
                  try:
                      termios.tcsetattr(tty_fd, termios.TCSADRAIN, saved_termios)
                  except termios.error:
                      pass
              if tty_fd > 2:
                  try:
                      os.close(tty_fd)
                  except OSError:
                      pass


      if __name__ == "__main__":
          main()
      PY
      }

      case "''${1:-toggle}" in
        start)
          if (( $# > 0 )); then
            shift
          fi
          cmd_start "''${1:-mix}" "''${2:-}"
          ;;
        stop)
          cmd_stop
          ;;
        toggle)
          if (( $# > 0 )); then
            shift
          fi
          if is_running; then
            cmd_stop
          else
            cmd_start "''${1:-mix}" "''${2:-}"
          fi
          ;;
        run)
          if (( $# > 0 )); then
            shift
          fi
          cmd_run "''${1:-mix}" "''${2:-}"
          ;;
        is-running)
          is_running
          ;;
        status|--status)
          if is_running; then
            printf 'running\n'
          else
            printf 'stopped\n'
          fi
          ;;
        *)
          printf 'Usage: screensaver {start [mode] [effect]|stop|toggle [mode] [effect]|run [mode] [effect]|status|is-running}\n' >&2
          printf 'Modes: mix (default), nixos (or tte), sakura, lightning, storm\n' >&2
          exit 2
          ;;
      esac
    '';
  };

  lockToggle = pkgs.writeShellApplication {
    name = "lock-toggle";
    runtimeInputs = [
      pkgs.coreutils
      pkgs.libnotify
      ironbar
    ];
    text = ''
      STATE_DIR="''${XDG_RUNTIME_DIR:-/run/user/$(id -u)}/power-state"
      FLAG_FILE="$STATE_DIR/no-autolock"

      mkdir -p "$STATE_DIR"

      is_autolock_on() {
        [[ ! -e "$FLAG_FILE" ]]
      }

      sync_bar() {
        if is_autolock_on; then
          ironbar var set autolock_off false >/dev/null 2>&1 || true
        else
          ironbar var set autolock_off true >/dev/null 2>&1 || true
        fi
      }

      notify_state() {
        local body="$1"
        notify-send \
          -h string:x-canonical-private-synchronous:lock-toggle \
          -u low \
          -t 2500 \
          "Auto-Lock" \
          "$body" >/dev/null 2>&1 || true
      }

      set_on() {
        rm -f "$FLAG_FILE"
        sync_bar
        notify_state "ON — screen locks automatically on idle & sleep"
      }

      set_off() {
        touch "$FLAG_FILE"
        sync_bar
        notify_state "OFF — idle & sleep skip auto-lock (manual lock still works)"
      }

      case "''${1:-toggle}" in
        on)
          set_on
          ;;
        off)
          set_off
          ;;
        toggle)
          if is_autolock_on; then
            set_off
          else
            set_on
          fi
          ;;
        --sync)
          sync_bar
          ;;
        --status|status)
          if [[ "''${2:-}" == "--json" ]]; then
            if is_autolock_on; then
              printf '{"autolock":"on","enabled":true}\n'
            else
              printf '{"autolock":"off","enabled":false}\n'
            fi
          else
            if is_autolock_on; then
              printf 'on\n'
            else
              printf 'off\n'
            fi
          fi
          ;;
        *)
          printf 'Usage: lock-toggle [on|off|toggle|--status [--json]|--sync]\n' >&2
          exit 2
          ;;
      esac
    '';
  };

  screenAwake = pkgs.writeShellApplication {
    name = "screen-awake";
    runtimeInputs = [
      pkgs.coreutils
      pkgs.libnotify
      ironbar
    ];
    text = ''
      STATE_DIR="''${XDG_RUNTIME_DIR:-/run/user/$(id -u)}/power-state"
      FLAG_FILE="$STATE_DIR/keep-screen-on"

      mkdir -p "$STATE_DIR"

      is_awake_on() {
        [[ -e "$FLAG_FILE" ]]
      }

      sync_bar() {
        if is_awake_on; then
          ironbar var set screen_awake true >/dev/null 2>&1 || true
        else
          ironbar var set screen_awake false >/dev/null 2>&1 || true
        fi
      }

      notify_state() {
        local body="$1"
        notify-send \
          -h string:x-canonical-private-synchronous:screen-awake \
          -u low \
          -t 2500 \
          "Keep Screen On" \
          "$body" >/dev/null 2>&1 || true
      }

      set_on() {
        touch "$FLAG_FILE"
        sync_bar
        notify_state "ON — screen stays on (idle screensaver, blanking & suspend paused)"
      }

      set_off() {
        rm -f "$FLAG_FILE"
        sync_bar
        notify_state "OFF — normal idle screensaver & display blanking restored"
      }

      case "''${1:-toggle}" in
        on)
          set_on
          ;;
        off)
          set_off
          ;;
        toggle)
          if is_awake_on; then
            set_off
          else
            set_on
          fi
          ;;
        --sync)
          sync_bar
          ;;
        --status|status)
          if [[ "''${2:-}" == "--json" ]]; then
            if is_awake_on; then
              printf '{"screen_awake":"on","active":true}\n'
            else
              printf '{"screen_awake":"off","active":false}\n'
            fi
          else
            if is_awake_on; then
              printf 'on\n'
            else
              printf 'off\n'
            fi
          fi
          ;;
        *)
          printf 'Usage: screen-awake [on|off|toggle|--status [--json]|--sync]\n' >&2
          exit 2
          ;;
      esac
    '';
  };

  caffeine = pkgs.writeShellApplication {
    name = "caffeine";
    runtimeInputs = [
      pkgs.coreutils
      pkgs.libnotify
      pkgs.systemd
      ironbar
    ];
    text = ''
      STATE_DIR="''${XDG_RUNTIME_DIR:-/run/user/$(id -u)}/power-state"
      FLAG_FILE="$STATE_DIR/caffeine-mode"
      LEGACY_FLAG_FILE="$STATE_DIR/llm-mode"
      UNIT_NAME="caffeine-keep-awake.service"
      LEGACY_UNIT_NAME="llm-keep-awake.service"
      RUN_FLAG=""

      mkdir -p "$STATE_DIR"

      is_unit_active() {
        systemctl --user is-active --quiet "$UNIT_NAME" 2>/dev/null \
          || systemctl --user is-active --quiet "$LEGACY_UNIT_NAME" 2>/dev/null
      }

      reconcile_state() {
        if [[ -e "$FLAG_FILE" || -e "$LEGACY_FLAG_FILE" ]]; then
          if ! is_unit_active; then
            rm -f "$FLAG_FILE" "$LEGACY_FLAG_FILE"
          fi
        fi

        local f pid
        shopt -s nullglob
        for f in "$STATE_DIR"/caffeine-run.* "$STATE_DIR"/llm-run.*; do
          pid="''${f##*.}"
          if ! [[ "$pid" =~ ^[0-9]+$ ]] || ! kill -0 "$pid" 2>/dev/null; then
            rm -f "$f"
          fi
        done
        shopt -u nullglob
      }

      has_active_runs() {
        local -a runs=()
        shopt -s nullglob
        runs=("$STATE_DIR"/caffeine-run.* "$STATE_DIR"/llm-run.*)
        shopt -u nullglob
        (( ''${#runs[@]} > 0 ))
      }

      is_persistent_on() {
        reconcile_state
        [[ -e "$FLAG_FILE" || -e "$LEGACY_FLAG_FILE" ]] && is_unit_active
      }

      is_any_active() {
        if is_persistent_on; then
          return 0
        fi
        has_active_runs
      }

      sync_bar() {
        if is_any_active; then
          ironbar var set caffeine_mode true >/dev/null 2>&1 || true
        else
          ironbar var set caffeine_mode false >/dev/null 2>&1 || true
        fi
      }

      notify_state() {
        local body="$1"
        notify-send \
          -h string:x-canonical-private-synchronous:caffeine \
          -u low \
          -t 2500 \
          "Caffeine Mode" \
          "$body" >/dev/null 2>&1 || true
      }

      cmd_on() {
        if ! systemctl --user is-active --quiet "$UNIT_NAME" 2>/dev/null; then
          systemd-run \
            --user \
            --unit=caffeine-keep-awake \
            --collect \
            --description="Caffeine Keep-Awake Inhibitor" \
            systemd-inhibit \
              --what=sleep:handle-lid-switch \
              --who="caffeine" \
              --why="Caffeine keep-awake mode" \
              --mode=block \
              sleep infinity >/dev/null
        fi
        rm -f "$LEGACY_FLAG_FILE"
        touch "$FLAG_FILE"
        sync_bar
        notify_state "ON — sleep & lid-suspend disabled (display off after 45m)"
      }

      cmd_off() {
        systemctl --user stop "$UNIT_NAME" "$LEGACY_UNIT_NAME" >/dev/null 2>&1 || true
        rm -f "$FLAG_FILE" "$LEGACY_FLAG_FILE"
        sync_bar
        notify_state "OFF — normal sleep restored"
      }

      cmd_run() {
        if (( $# == 0 )); then
          printf 'Usage: caffeine run <command> [args...]\n' >&2
          exit 2
        fi

        RUN_FLAG="$STATE_DIR/caffeine-run.$$"
        touch "$RUN_FLAG"
        sync_bar
        notify_state "Running inhibited: $1"

        cleanup_run() {
          if [[ -n "''${RUN_FLAG:-}" ]]; then
            rm -f "$RUN_FLAG"
            RUN_FLAG=""
          fi
          sync_bar
        }
        trap cleanup_run EXIT INT TERM

        local rc=0
        systemd-inhibit \
          --what=sleep:handle-lid-switch \
          --who="caffeine-run" \
          --why="Caffeine job: $1" \
          --mode=block \
          -- "$@" || rc=$?
        return "$rc"
      }

      case "''${1:-toggle}" in
        on)
          cmd_on
          ;;
        off)
          cmd_off
          ;;
        toggle)
          if is_persistent_on; then
            cmd_off
          else
            cmd_on
          fi
          ;;
        run)
          shift
          cmd_run "$@"
          ;;
        --sync)
          sync_bar
          ;;
        --status|status)
          if [[ "''${2:-}" == "--json" ]]; then
            if is_any_active; then
              printf '{"caffeine":"on","active":true}\n'
            else
              printf '{"caffeine":"off","active":false}\n'
            fi
          else
            if is_any_active; then
              printf 'on\n'
            else
              printf 'off\n'
            fi
          fi
          ;;
        *)
          printf 'Usage: caffeine [on|off|toggle|--status [--json]|--sync|run <cmd...>]\n' >&2
          exit 2
          ;;
      esac
    '';
  };

  llmMode = pkgs.writeShellApplication {
    name = "llm-mode";
    runtimeInputs = [ caffeine ];
    text = ''
      exec caffeine "$@"
    '';
  };

  sessionPower = pkgs.writeShellApplication {
    name = "session-power";
    runtimeInputs = [
      pkgs.coreutils
      pkgs.hyprlock
      pkgs.niri
      pkgs.procps
      pkgs.systemd
      pkgs.util-linux
      screensaver
      lockToggle
      screenAwake
      caffeine
    ];
    text = ''
      ensure_niri_socket() {
        if [[ -n "''${NIRI_SOCKET:-}" && -S "$NIRI_SOCKET" ]]; then
          return 0
        fi
        local runtime_dir sock
        runtime_dir="''${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"
        shopt -s nullglob
        for sock in "$runtime_dir"/niri.*.sock; do
          if [[ -S "$sock" ]]; then
            export NIRI_SOCKET="$sock"
            break
          fi
        done
        shopt -u nullglob
      }

      niri_action() {
        ensure_niri_socket
        niri msg action "$@" >/dev/null 2>&1 || true
      }

      is_caffeine_active() {
        [[ "$(caffeine --status)" == "on" ]]
      }

      is_autolock_on() {
        [[ "$(lock-toggle --status)" == "on" ]]
      }

      is_screen_awake() {
        [[ "$(screen-awake --status)" == "on" ]]
      }

      cmd_lock() {
        local sleep_mode=0
        if [[ "''${1:-}" == "--sleep" ]]; then
          sleep_mode=1
        fi

        if screensaver is-running; then
          screensaver stop || true
          sleep 0.15
        fi

        if pgrep -x hyprlock >/dev/null 2>&1; then
          exit 0
        fi

        if (( sleep_mode == 1 )); then
          setsid -f hyprlock --immediate-render --no-fade-in </dev/null >/dev/null 2>&1
          for _ in 1 2 3 4 5 6 7 8; do
            if pgrep -x hyprlock >/dev/null 2>&1; then
              break
            fi
            sleep 0.05
          done
          sleep 0.35
        else
          exec hyprlock
        fi
      }

      case "''${1:-}" in
        idle-screensaver)
          if is_screen_awake || is_caffeine_active; then
            exit 0
          fi
          screensaver start || true
          ;;
        resume-screensaver)
          screensaver stop || true
          ;;
        idle-display-off)
          if is_screen_awake || is_caffeine_active; then
            exit 0
          fi
          if screensaver is-running; then
            screensaver stop || true
            sleep 0.15
          fi
          if is_autolock_on; then
            cmd_lock --sleep
            niri_action power-off-monitors
          else
            niri_action power-off-monitors
          fi
          ;;
        idle-caffeine-display-off|idle-llm-display-off)
          if is_caffeine_active && ! is_screen_awake; then
            screensaver stop || true
            niri_action power-off-monitors
          fi
          ;;
        resume-display)
          niri_action power-on-monitors
          ;;
        idle-suspend)
          if is_screen_awake || is_caffeine_active; then
            exit 0
          fi
          systemctl suspend
          ;;
        before-sleep)
          screensaver stop || true
          if is_autolock_on; then
            cmd_lock --sleep
          fi
          ;;
        after-resume)
          niri_action power-on-monitors
          ;;
        lock)
          shift
          cmd_lock "$@"
          ;;
        lid-close)
          if is_caffeine_active; then
            screensaver stop || true
            niri_action power-off-monitors
          fi
          ;;
        lid-open)
          niri_action power-on-monitors
          ;;
        sync-bar)
          caffeine --sync
          lock-toggle --sync
          screen-awake --sync
          ;;
        *)
          printf 'Usage: session-power {idle-screensaver|resume-screensaver|idle-display-off|idle-caffeine-display-off|resume-display|idle-suspend|before-sleep|after-resume|lock [--sleep]|lid-close|lid-open|sync-bar}\n' >&2
          exit 2
          ;;
      esac
    '';
  };

  ironbarSyncPower = pkgs.writeShellApplication {
    name = "ironbar-sync-power";
    runtimeInputs = [
      pkgs.coreutils
      ironbar
      sessionPower
    ];
    text = ''
      # Wait briefly for Ironbar's IPC socket after start/restart, then push power-state vars.
      for _ in 1 2 3 4 5 6 7 8 9 10; do
        if ironbar var get caffeine_mode >/dev/null 2>&1; then
          session-power sync-bar || true
          exit 0
        fi
        sleep 0.2
      done
    '';
  };
in
{
  home.packages = [
    screensaver
    lockToggle
    screenAwake
    caffeine
    llmMode
    sessionPower
  ];

  systemd.user.services.ironbar.Service.ExecStartPost = "-${ironbarSyncPower}/bin/ironbar-sync-power";

  systemd.user.services.swayidle = {
    Unit = {
      Description = "Wayland idle manager (screensaver, DPMS, lock, suspend)";
      After = [
        "graphical-session-pre.target"
        "graphical-session.target"
      ];
      PartOf = [ "graphical-session.target" ];
      ConditionEnvironment = "WAYLAND_DISPLAY";
    };
    Service = {
      ExecStart = pkgs.lib.concatStringsSep " " [
        "${pkgs.swayidle}/bin/swayidle"
        "-w"
        "timeout 180 '${sessionPower}/bin/session-power idle-screensaver'"
        "resume '${sessionPower}/bin/session-power resume-screensaver'"
        "timeout 900 '${sessionPower}/bin/session-power idle-display-off'"
        "resume '${sessionPower}/bin/session-power resume-display'"
        "timeout 1500 '${sessionPower}/bin/session-power idle-suspend'"
        "timeout 2700 '${sessionPower}/bin/session-power idle-caffeine-display-off'"
        "resume '${sessionPower}/bin/session-power resume-display'"
        "before-sleep '${sessionPower}/bin/session-power before-sleep'"
        "after-resume '${sessionPower}/bin/session-power after-resume'"
        "lock '${sessionPower}/bin/session-power lock'"
      ];
      Restart = "on-failure";
      RestartSec = 2;
    };
    Install.WantedBy = [ "graphical-session.target" ];
  };
}
