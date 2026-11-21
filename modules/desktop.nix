{ pkgs, ... }:

let
  sddm = import ./sddm-package.nix { inherit pkgs; };
  catppuccinSddm = pkgs.catppuccin-sddm.override {
    flavor = "mocha";
    accent = "mauve";
  };
in
{
  programs.niri.enable = true;

  # Display manager for the Niri Wayland session.
  services.displayManager = {
    defaultSession = "niri";
    sddm = {
      enable = true;
      package = sddm;
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
  };

  programs.dconf.enable = true;
  services.gnome.gnome-keyring.enable = true;

  # XDG portals for Niri and GTK applications.
  xdg.portal = {
    enable = true;
    extraPortals = [
      pkgs.xdg-desktop-portal-gnome
      pkgs.xdg-desktop-portal-gtk
    ];
    config = {
      common.default = [ "gtk" ];
      niri = {
        default = [
          "gnome"
          "gtk"
        ];
        "org.freedesktop.impl.portal.Secret" = [ "gnome-keyring" ];
        "org.freedesktop.impl.portal.FileChooser" = [ "gtk" ];
        "org.freedesktop.impl.portal.OpenURI" = [ "gtk" ];
        "org.freedesktop.impl.portal.AppChooser" = [ "gtk" ];
        "org.freedesktop.impl.portal.ScreenCast" = [ "gnome" ];
        "org.freedesktop.impl.portal.Screenshot" = [ "gnome" ];
        "org.freedesktop.impl.portal.Inhibit" = [ "gnome" ];
      };
    };
    xdgOpenUsePortal = true;
  };

  environment.sessionVariables = {
    NIXOS_OZONE_WL = "1";
    ELECTRON_OZONE_PLATFORM_HINT = "auto";
    XCURSOR_SIZE = "24";
    _JAVA_AWT_WM_NONREPARENTING = "1";
  };

  fonts = {
    fontDir.enable = true;
    packages = with pkgs; [
      nerd-fonts.jetbrains-mono
      nerd-fonts.iosevka
      nerd-fonts.symbols-only
      noto-fonts
      noto-fonts-color-emoji
      corefonts
      vista-fonts
    ];
    fontconfig.defaultFonts = {
      monospace = [
        "JetBrainsMono Nerd Font"
        "Symbols Nerd Font Mono"
        "Noto Color Emoji"
      ];
      sansSerif = [
        "Noto Sans"
        "Symbols Nerd Font"
        "Noto Color Emoji"
      ];
      serif = [
        "Noto Serif"
        "Noto Color Emoji"
      ];
      emoji = [ "Noto Color Emoji" ];
    };
  };

  # Graphical session components and utilities.
  environment.systemPackages =
    (with pkgs; [
      xwayland-satellite
      fuzzel
      swaynotificationcenter
      kitty
      foot
      terminaltexteffects
      wl-clipboard
      cliphist
      xdg-user-dirs
      xdg-utils
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
    ])
    ++ [ catppuccinSddm ];

  security.pam.services = {
    hyprlock = { };
    sddm.enableGnomeKeyring = true;
  };
}
