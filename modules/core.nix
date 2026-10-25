{ config, pkgs, ... }:

let
  rebuildScript = pkgs.writeShellScriptBin "rebuild" ''
    set -euo pipefail
    REPO="/etc/nixos"
    if [ -d "$REPO/.git" ]; then
      ${pkgs.git}/bin/git -C "$REPO" add -A
    fi
    sudo nixos-rebuild switch --flake "$REPO#nixos" "$@"
  '';

  clipClearScript = pkgs.writeShellScriptBin "clip-clear" ''
    set -euo pipefail
    ${pkgs.cliphist}/bin/cliphist wipe
    ${pkgs.wl-clipboard}/bin/wl-copy --clear
    ${pkgs.libnotify}/bin/notify-send "Буфер обміну" "Історію буфера успішно очищено" || true
  '';
in
{
  # Завантажувач
  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;
  boot.loader.systemd-boot.configurationLimit = 5;
  
  # Додатковий пункт для Chimera Linux
  boot.loader.systemd-boot.extraEntries = {
      "chimera.conf" = ''
        title Chimera Linux
        efi /EFI/chimera/grubx64.efi
      '';
    };

  # Оптимізація та налаштування Nix
  nix.settings.experimental-features = [ "nix-command" "flakes" ];
  nix.settings.auto-optimise-store = true;
  nix.gc = {
    automatic = true;
    dates = "weekly";
    options = "--delete-older-than 7d";
  };
  nixpkgs.config.allowUnfree = true;

  # Мережа та ім'я хоста
  networking.hostName = "nixos";
  networking.networkmanager.enable = true;

  # Пріоритет IPv4 над неробочим IPv6 для системних резолверів
  environment.etc."gai.conf".text = ''
    precedence ::ffff:0:0/96  100
  '';

  # PKI / SSL сумісність для сторонніх агентів та Node.js
  security.pki.useCompatibleBundle = true;

  # Локалізація
  time.timeZone = "Europe/Kyiv";
  i18n.defaultLocale = "en_US.UTF-8";
  i18n.extraLocaleSettings = {
    LC_ADDRESS = "uk_UA.UTF-8";
    LC_IDENTIFICATION = "uk_UA.UTF-8";
    LC_MEASUREMENT = "uk_UA.UTF-8";
    LC_MONETARY = "uk_UA.UTF-8";
    LC_NAME = "uk_UA.UTF-8";
    LC_NUMERIC = "uk_UA.UTF-8";
    LC_PAPER = "uk_UA.UTF-8";
    LC_TELEPHONE = "uk_UA.UTF-8";
    LC_TIME = "uk_UA.UTF-8";
  };

  # Розкладка клавіатури
  services.xserver.xkb = {
    layout = "us,ua";
    variant = "";
  };

  # Сервіси сесії та зв'язки ключів
  programs.dconf.enable = true;
  services.gnome.gnome-keyring.enable = true;

  # XDG Portals
  xdg.portal = {
    enable = true;
    extraPortals = [
      pkgs.xdg-desktop-portal-gnome
      pkgs.xdg-desktop-portal-gtk
    ];
    config = {
      common.default = [ "gtk" ];
      niri = {
        default = [ "gnome" "gtk" ];
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

  # Загальносистемні змінні сесії
  environment.sessionVariables = {
    EDITOR = "micro";
    VISUAL = "micro";
    TERMINAL = "kitty";

    NIXOS_OZONE_WL = "1";
    ELECTRON_OZONE_PLATFORM_HINT = "auto";

    XCURSOR_SIZE = "24";
    _JAVA_AWT_WM_NONREPARENTING = "1";

    # SSL сертифікати для generic/manylinux бінарників під nix-ld (Zed ACP агенти, сторонній Python, Node.js)
    SSL_CERT_FILE = "/etc/ssl/certs/ca-bundle.crt";
    SSL_CERT_DIR = "/etc/ssl/certs";
    NIX_SSL_CERT_FILE = "/etc/ssl/certs/ca-bundle.crt";
  };

  # Шрифти
  fonts.fontDir.enable = true;
  fonts.packages = with pkgs; [
    nerd-fonts.jetbrains-mono
    nerd-fonts.iosevka
    nerd-fonts.symbols-only
    noto-fonts
    noto-fonts-color-emoji
    corefonts      
    vista-fonts
  ];

  fonts.fontconfig.defaultFonts = {
    monospace = [ "JetBrainsMono Nerd Font" "Symbols Nerd Font Mono" "Noto Color Emoji" ];
    sansSerif = [ "Noto Sans" "Symbols Nerd Font" "Noto Color Emoji" ];
    serif = [ "Noto Serif" "Noto Color Emoji" ];
    emoji = [ "Noto Color Emoji" ];
  };

  # Git
  programs.git = {
    enable = true;
    config.safe.directory = "/etc/nixos";
  };

  # Користувацькі фонові служби
  systemd.user.services.cliphist = {
    description = "Cliphist clipboard history watcher";
    wantedBy = [ "graphical-session.target" ];
    partOf = [ "graphical-session.target" ];
    after = [ "graphical-session.target" ];
    serviceConfig = {
      Type = "simple";
      ExecStart = "${pkgs.wl-clipboard}/bin/wl-paste --watch ${pkgs.cliphist}/bin/cliphist store";
      Restart = "always";
      RestartSec = 2;
    };
  };

  systemd.user.services.cliphist-images = {
    description = "Cliphist clipboard image history watcher";
    wantedBy = [ "graphical-session.target" ];
    partOf = [ "graphical-session.target" ];
    after = [ "graphical-session.target" ];
    serviceConfig = {
      Type = "simple";
      ExecStart = "${pkgs.wl-clipboard}/bin/wl-paste --type image --watch ${pkgs.cliphist}/bin/cliphist store";
      Restart = "always";
      RestartSec = 2;
    };
  };

  systemd.user.services.rclone-bisync = {
    description = "Rclone self-healing bisync for Google Drive";
    wants = [ "network-online.target" ];
    after = [ "network-online.target" ];
    serviceConfig = {
      Type = "oneshot";
      ExecStart = "${pkgs.bash}/bin/bash %h/.config/rclone/rclone-autofix.sh";
      Nice = 19;
      IOSchedulingClass = "idle";
      CPUSchedulingPolicy = "idle";
    };
  };

  systemd.user.timers.rclone-bisync = {
    description = "Run Rclone Bisync every 10 minutes";
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnBootSec = "2m";
      OnUnitActiveSec = "10m";
      AccuracySec = "1m";
      Persistent = true;
      Unit = "rclone-bisync.service";
    };
  };

  # Базові пакети
  environment.systemPackages = with pkgs; [
    curl
    wget
    python3
    rebuildScript
    clipClearScript
  ];
}
