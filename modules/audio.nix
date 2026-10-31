{ config, pkgs, ... }:

{
  # HP EliteBook 665 G11 with ALC236 codec SSID 103c:8c82:
  # reuse the supported 103c:8c81 quirk for the speaker/microphone mute LEDs.
  # The leading comma skips the first HDA controller (Radeon HDMI).
  boot.extraModprobeConfig = ''
    options snd_hda_intel model=,103c:8c81
  '';

  services.pulseaudio.enable = false;
  security.rtkit.enable = true;

  services.pipewire = {
    enable = true;
    alsa.enable = true;
    alsa.support32Bit = true;
    pulse.enable = true;
    wireplumber.enable = true;
  };

  hardware.bluetooth = {
    enable = true;
    powerOnBoot = true;
  };

  services.blueman.enable = true;

  # Keep printer support out of the base system; enable services.printing
  # separately only if a printer is actually needed.
}
