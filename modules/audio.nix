{ pkgs, ... }:

let
  audioLedSync = pkgs.writeShellApplication {
    name = "audio-led-sync";
    runtimeInputs = [
      pkgs.wireplumber
      pkgs.pipewire
      pkgs.pulseaudio
      pkgs.jq
      pkgs.gawk
      pkgs.coreutils
    ];
    text = ''
      last_rnnoise_id=""
      last_raw_mic_id=""

      find_node_id() {
        local node_name="$1"
        pw-dump 2>/dev/null | jq -r --arg name "$node_name" '
          .[]
          | select(.type == "PipeWire:Interface:Node" and .info.props["node.name"] == $name)
          | .id
        ' | head -n1 || true
      }

      # Work around PipeWire 1.4 filter-chain virtual source ignoring mute/volume
      # until Props.params is explicitly poked once per node instance.
      unlock_rnnoise() {
        local id
        id="$(find_node_id "rnnoise_source")"

        if [ -n "$id" ] && [ "$id" != "$last_rnnoise_id" ]; then
          if pw-cli s "$id" Props '{ params: [ "monitor.channel-volumes", true ] }' >/dev/null 2>&1; then
            last_rnnoise_id="$id"
          fi
        fi
      }

      # Keep the raw ALC236 internal mic unmuted (otherwise rnnoise_source gets
      # silence) and below 0.45 so the noisy +10/+20/+30 dB hardware Mic Boost
      # stays at 0 dB.
      ensure_raw_mic_healthy() {
        local id out vol
        id="$(find_node_id "alsa_input.pci-0000_e5_00.6.analog-stereo")"
        [ -n "$id" ] || return 0
        [ "$id" != "$last_raw_mic_id" ] || return 0

        out="$(wpctl get-volume "$id" 2>/dev/null)" || return 0
        if [[ "$out" == *"[MUTED]"* ]]; then
          wpctl set-mute "$id" 0 >/dev/null 2>&1 || true
        fi

        vol="$(printf '%s\n' "$out" | awk '{print $2}')"
        if [ -n "$vol" ] && awk -v v="$vol" 'BEGIN { exit !(v > 0.45) }'; then
          wpctl set-volume "$id" 0.35 >/dev/null 2>&1 || true
        fi

        last_raw_mic_id="$id"
      }

      sync_led() {
        local target="$1"
        local led="$2"
        [ -w "$led" ] || return 0

        local out state cur
        out="$(wpctl get-volume "$target" 2>/dev/null)" || return 0
        if [[ "$out" == *"[MUTED]"* ]]; then
          state=1
        else
          state=0
        fi

        cur="$(cat "$led" 2>/dev/null || true)"
        if [ "$cur" != "$state" ]; then
          printf '%s\n' "$state" > "$led" 2>/dev/null || true
        fi
      }

      sync_all() {
        sync_led "@DEFAULT_AUDIO_SINK@" "/sys/class/leds/hda::mute/brightness"
        sync_led "@DEFAULT_AUDIO_SOURCE@" "/sys/class/leds/hda::micmute/brightness"
      }

      for _ in 1 2 3 4 5; do
        unlock_rnnoise
        ensure_raw_mic_healthy
        if [ -n "$last_rnnoise_id" ] && [ -n "$last_raw_mic_id" ]; then
          break
        fi
        sleep 1
      done

      sync_all

      while true; do
        if IFS= read -r -t 5 line; then
          case "$line" in
            *"'new' on source "*|*" on server "*)
              unlock_rnnoise
              ensure_raw_mic_healthy
              sync_all
              ;;
            *" on sink "*|*" on source "*)
              sync_all
              ;;
          esac
        else
          rc=$?
          if [ "$rc" -gt 128 ]; then
            # Idle timeout: re-sync LEDs (recovers automatically after suspend/resume)
            sync_all
          else
            # EOF from pactl subscribe (pipewire-pulse restarted) -> let systemd restart us
            break
          fi
        fi
      done < <(pactl subscribe)
    '';
  };
in
{
  # HP EliteBook 665 G11 with ALC236 codec SSID 103c:8c82:
  # reuse the supported 103c:8c81 quirk for the speaker/microphone mute LEDs.
  # The leading comma skips the first HDA controller (Radeon HDMI).
  boot.extraModprobeConfig = ''
    options snd_hda_intel model=,103c:8c81
  '';

  # Detach F6 (hda::mute) and F9 (hda::micmute) LEDs from the internal-card-only
  # ALSA trigger so user-space PipeWire sync can drive them for all outputs/inputs
  # (internal speakers/mic, USB-C headphones, Bluetooth, etc.).
  services.udev.extraRules = ''
    ACTION=="add|change", SUBSYSTEM=="leds", KERNEL=="hda::mute|hda::micmute", ATTR{trigger}="none", RUN+="${pkgs.coreutils}/bin/chgrp audio /sys%p/brightness", RUN+="${pkgs.coreutils}/bin/chmod 0664 /sys%p/brightness"
  '';

  systemd.user.services.audio-led-sync = {
    description = "Sync F6/F9 mute LEDs with active PipeWire default sink and source";
    wantedBy = [ "graphical-session.target" ];
    after = [
      "pipewire.service"
      "pipewire-pulse.service"
      "wireplumber.service"
    ];
    wants = [
      "pipewire-pulse.service"
      "wireplumber.service"
    ];
    serviceConfig = {
      ExecStart = "${audioLedSync}/bin/audio-led-sync";
      Restart = "always";
      RestartSec = 2;
    };
  };

  services.pulseaudio.enable = false;
  security.rtkit.enable = true;

  services.pipewire = {
    enable = true;
    alsa.enable = true;
    alsa.support32Bit = true;
    pulse.enable = true;
    wireplumber.enable = true;

    wireplumber.extraConfig."51-internal-mic-rename" = {
      "monitor.alsa.rules" = [
        {
          matches = [
            { "node.name" = "alsa_input.pci-0000_e5_00.6.analog-stereo"; }
          ];
          actions = {
            update-props = {
              "node.description" = "Built-in Mic (Raw)";
            };
          };
        }
      ];
    };

    # Real-time RNNoise suppression for the built-in ALC236 microphone.
    # Priority 2050 sits above the raw built-in mic (2009) so it is selected
    # automatically when no external headset is connected, while staying below
    # USB/Bluetooth headsets (2100+).
    extraConfig.pipewire."99-input-denoising" = {
      "context.modules" = [
        {
          name = "libpipewire-module-filter-chain";
          args = {
            "node.description" = "Built-in Mic (Noise Cancelling)";
            "media.name" = "Built-in Mic (Noise Cancelling)";
            "filter.graph" = {
              nodes = [
                {
                  type = "ladspa";
                  name = "rnnoise";
                  plugin = "${pkgs.rnnoise-plugin.ladspa}/lib/ladspa/librnnoise_ladspa.so";
                  label = "noise_suppressor_stereo";
                  control = {
                    "VAD Threshold (%)" = 50.0;
                    "VAD Grace Period (ms)" = 200;
                    "Retroactive VAD Grace (ms)" = 0;
                  };
                }
              ];
            };
            "capture.props" = {
              "node.name" = "capture.rnnoise_source";
              "node.passive" = true;
              "target.object" = "alsa_input.pci-0000_e5_00.6.analog-stereo";
              "audio.rate" = 48000;
              "audio.channels" = 2;
              "audio.position" = [
                "FL"
                "FR"
              ];
            };
            "playback.props" = {
              "node.name" = "rnnoise_source";
              "media.class" = "Audio/Source";
              "audio.rate" = 48000;
              "audio.channels" = 2;
              "audio.position" = [
                "FL"
                "FR"
              ];
              "monitor.channel-volumes" = true;
              "node.pause-on-idle" = false;
              "state.restore-props" = true;
              "priority.session" = 2050;
              "priority.driver" = 2050;
            };
          };
        }
      ];
    };
  };

  hardware.bluetooth = {
    enable = true;
    powerOnBoot = true;
  };

  services.blueman.enable = true;

  # Keep printer support out of the base system; enable services.printing
  # separately only if a printer is actually needed.
}
