{
  imports = [
    ./hardware-configuration.nix
    ./modules/core.nix
    ./modules/hardware.nix
    ./modules/niri.nix
    ./modules/audio.nix
    ./modules/storage.nix
    ./modules/power.nix
    ./modules/terminal.nix
    ./modules/applications.nix
    ./modules/dev.nix
    ./modules/user.nix
  ];

  system.stateVersion = "25.11";
}
