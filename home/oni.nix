{ pkgs, ... }:

let
  ironbar = import ./ironbar-package.nix { inherit pkgs; };
  swayosd = import ./swayosd-package.nix { inherit pkgs; };
  osdWatcher = pkgs.writeShellApplication {
    name = "desktop-osd-watch";
    runtimeInputs = [
      pkgs.python3
      pkgs.pulseaudio
      pkgs.wireplumber
      swayosd
    ];
    text = ''
      exec python3 ${./dotfiles/swayosd/watch.py}
    '';
  };
in
{
  imports = [
    ./neovim.nix
    ./theming.nix
  ];

  home = {
    username = "oni";
    homeDirectory = "/home/oni";
    stateVersion = "25.11";
    packages = [ ironbar ];

    file = {
      ".config/niri/scripts" = {
        source = ./dotfiles/niri/scripts;
        recursive = true;
        executable = true;
      };
      ".icons/default/index.theme".source = ./dotfiles/icons/index.theme;
      ".local/bin/backup-system.sh" = {
        source = ../scripts/backup-system.sh;
        executable = true;
      };
      ".local/bin/blur-adjust.sh" = {
        source = ../scripts/blur-adjust.sh;
        executable = true;
      };
    };
  };

  news.display = "silent";
  manual = {
    manpages.enable = false;
    html.enable = false;
    json.enable = false;
  };

  systemd.user.services.ironbar = {
    Unit = {
      Description = "Ironbar desktop panel";
      After = [ "graphical-session-pre.target" ];
      PartOf = [ "graphical-session.target" ];
    };
    Service = {
      ExecStart = "${ironbar}/bin/ironbar";
      Environment = [
        "IRONBAR_LOG=error"
        "IRONBAR_FILE_LOG=error"
        # English panel/calendar text without changing the session or Fuzzel locale.
        "LC_NUMERIC=en_US.UTF-8"
        "LC_TIME=en_US.UTF-8"
        "LC_MESSAGES=en_US.UTF-8"
      ];
      Restart = "on-failure";
      RestartSec = 2;
      KillMode = "control-group";
      TimeoutStopSec = 5;
    };
    Install.WantedBy = [ "graphical-session.target" ];
  };

  services.swayosd = {
    enable = true;
    package = swayosd;
    topMargin = 0.85;
    # Store the stylesheet itself, so unrelated flake edits do not change the unit.
    stylePath = "${./dotfiles/swayosd/style.css}";
  };

  systemd.user.services.swayosd.Service.Environment = [ "LC_MESSAGES=en_US.UTF-8" ];

  systemd.user.services.desktop-osd = {
    Unit = {
      Description = "Volume and brightness OSD observer";
      After = [
        "graphical-session-pre.target"
        # Match SwayOSD's ordering to avoid a cycle through the session target.
        "graphical-session.target"
        "swayosd.service"
      ];
      Wants = [ "swayosd.service" ];
      PartOf = [ "graphical-session.target" ];
      ConditionEnvironment = "WAYLAND_DISPLAY";
    };
    Service = {
      ExecStart = "${osdWatcher}/bin/desktop-osd-watch";
      Restart = "on-failure";
      RestartSec = 2;
      KillMode = "control-group";
      TimeoutStopSec = 5;
    };
    Install.WantedBy = [ "graphical-session.target" ];
  };

  xdg.configFile = {
    # Niri
    "niri/config.kdl".source = ./dotfiles/niri/config.kdl;
    "niri/wallpapers/default.png".source = ./dotfiles/niri/default.png;

    # Ironbar; config.toml та style.css керуються через theming.nix.
    "ironbar/panel-status.py".source = ./dotfiles/ironbar/panel-status.py;
    "ironbar/speaker-status.sh" = {
      source = ./dotfiles/ironbar/speaker-status.sh;
      executable = true;
    };
    "ironbar/mic-status.sh" = {
      source = ./dotfiles/ironbar/mic-status.sh;
      executable = true;
    };
    "ironbar/brightness.sh" = {
      source = ./dotfiles/ironbar/brightness.sh;
      executable = true;
    };
    "ironbar/battery-status.sh" = {
      source = ./dotfiles/ironbar/battery-status.sh;
      executable = true;
    };
    "ironbar/controls.sh" = {
      source = ./dotfiles/ironbar/controls.sh;
      executable = true;
    };
    "ironbar/notifications.py".source = ./dotfiles/ironbar/notifications.py;

    # Passive, bottom-center feedback for all volume/backlight controls.
    "swayosd/config.toml".source = ./dotfiles/swayosd/config.toml;
    "swayosd/style.css".source = ./dotfiles/swayosd/style.css;

    # SwayNC, Fuzzel і Kitty
    "swaync/config.json".source = ./dotfiles/swaync/config.json;
    "swaync/style.css".source = ./dotfiles/swaync/style.css;
    "fuzzel/fuzzel.ini".source = ./dotfiles/fuzzel/fuzzel.ini;
    "kitty/kitty.conf".source = ./dotfiles/kitty/kitty.conf;
    "kitty/launch-actions.conf".source = ./dotfiles/kitty/launch-actions.conf;
    "kitty/open-actions.conf".source = ./dotfiles/kitty/open-actions.conf;

    # Wlogout, Hyprlock і Swappy
    "wlogout/layout".source = ./dotfiles/wlogout/layout;
    "wlogout/style.css".source = ./dotfiles/wlogout/style.css;
    "hypr/hyprlock.conf".source = ./dotfiles/hypr/hyprlock.conf;
    "swappy/config".source = ./dotfiles/swappy/config;

    # Редактор і командний рядок
    "micro/bindings.json".source = ./dotfiles/micro/bindings.json;

    # GTK, Thunar та XFCE
    "gtk-3.0/settings.ini".source = ./dotfiles/gtk-3.0/settings.ini;
    "gtk-3.0/bookmarks".source = ./dotfiles/gtk-3.0/bookmarks;
    "gtk-4.0/settings.ini".source = ./dotfiles/gtk-4.0/settings.ini;
    "Thunar/uca.xml".source = ./dotfiles/Thunar/uca.xml;
    "xfce4/xfconf/xfce-perchannel-xml/xsettings.xml".source = ./dotfiles/xfce4/xsettings.xml;

    # Rclone
    "rclone/bisync-filters.txt".source = ./dotfiles/rclone/bisync-filters.txt;
    "rclone/rclone-autofix.sh" = {
      source = ./dotfiles/rclone/rclone-autofix.sh;
      executable = true;
    };

    # Mask duplicate XDG autostart tray applets (handled by Ironbar popup controls)
    "autostart/nm-applet.desktop".text = "[Desktop Entry]\nHidden=true\n";
    "autostart/blueman.desktop".text = "[Desktop Entry]\nHidden=true\n";
  };

  xdg.dataFile."applications/micro.desktop".source = ./dotfiles/applications/micro.desktop;
}
