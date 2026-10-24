{ config, pkgs, ... }:

{
  programs.niri.enable = true;

  # Display Manager configuration (SDDM Wayland with Catppuccin theme)
  services.displayManager.defaultSession = "niri";
  services.displayManager.sddm = {
    enable = true;
    wayland.enable = true;
    theme = "catppuccin-mocha-mauve";
    settings = {
      General.InputMethod = "";
      Users = {
        RememberLastUser = true;
        RememberLastSession = true;
        MinimumUid = 1000;
        MaximumUid = 60000;
      };
      Theme = {
        CursorTheme = "Bibata-Modern-Classic";
        CursorSize = 24;
      };
    };
  };

  # System packages required for Niri desktop environment
  environment.systemPackages = with pkgs; [
    xwayland-satellite
    waybar
    wofi
    swaynotificationcenter
    kitty
    wl-clipboard
    cliphist
    xdg-user-dirs
    xdg-utils
    wlogout
    swww
    grim
    slurp
    swappy
    brightnessctl
    playerctl
    libnotify
    pavucontrol
    networkmanagerapplet
    nwg-look
    matugen
    imagemagick
    hyprlock
    swayidle
    polkit_gnome
    bibata-cursors
    papirus-icon-theme
    adwaita-icon-theme
    gnome-themes-extra
    catppuccin-gtk
    (pkgs.catppuccin-sddm.override {
      flavor = "mocha";
      accent = "mauve";
    })
  ];

  # Security and PAM services
  security.pam.services.swaylock = {};
  security.pam.services.hyprlock = {};
  security.pam.services.sddm.enableGnomeKeyring = true;
}
