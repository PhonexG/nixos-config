{ ... }:

{
  # AMD CPU/GPU: keep the stock NixOS kernel and Mesa stack unless a project
  # specifically needs a custom kernel or ROCm.
  hardware.cpu.amd.updateMicrocode = true;
  hardware.enableRedistributableFirmware = true;

  hardware.graphics = {
    enable = true;
    enable32Bit = true;
  };

  # No Xorg server is enabled. Niri handles Wayland; X11 applications are
  # provided by niri's xwayland-satellite integration.
}
