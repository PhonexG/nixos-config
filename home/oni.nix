{ ... }:

{
  home = {
    username = "oni";
    homeDirectory = "/home/oni";
    stateVersion = "25.11";

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
    };
  };

  news.display = "silent";
  manual = {
    manpages.enable = false;
    html.enable = false;
    json.enable = false;
  };

  xdg.configFile = {
    # Niri
    "niri/config.kdl".source = ./dotfiles/niri/config.kdl;
    "niri/wallpapers/default.png".source = ./dotfiles/niri/default.png;

    # Ironbar; colors.css генерується динамічно.
    "ironbar/config.json".source = ./dotfiles/ironbar/config.json;
    "ironbar/style.css".source = ./dotfiles/ironbar/style.css;
    "ironbar/wifi-status.sh" = {
      source = ./dotfiles/ironbar/wifi-status.sh;
      executable = true;
    };
    "ironbar/speaker-status.sh" = {
      source = ./dotfiles/ironbar/speaker-status.sh;
      executable = true;
    };
    "ironbar/mic-status.sh" = {
      source = ./dotfiles/ironbar/mic-status.sh;
      executable = true;
    };
    "ironbar/battery-status.sh" = {
      source = ./dotfiles/ironbar/battery-status.sh;
      executable = true;
    };

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
    "hypr/colors.conf".source = ./dotfiles/hypr/colors.conf;
    "swappy/config".source = ./dotfiles/swappy/config;

    # Редактор і командний рядок
    "micro/bindings.json".source = ./dotfiles/micro/bindings.json;
    "starship.toml".source = ./dotfiles/starship.toml;

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
  };

  xdg.dataFile."applications/micro.desktop".source = ./dotfiles/applications/micro.desktop;

  dconf.settings."org/gnome/desktop/interface" = {
    color-scheme = "prefer-dark";
    gtk-theme = "Adwaita-dark";
    icon-theme = "Papirus-Dark";
    cursor-theme = "Bibata-Modern-Ice";
  };
}
