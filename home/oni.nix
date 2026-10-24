{ config, pkgs, ... }:

{
  home.username = "oni";
  home.homeDirectory = "/home/oni";
  home.stateVersion = "25.11";

  # Оптимізація: вимикаємо генерацію новин та зайвої документації
  news.display = "silent";
  manual.manpages.enable = false;
  manual.html.enable = false;
  manual.json.enable = false;

  # Niri конфігурація та скрипти
  xdg.configFile."niri/config.kdl".source = ./dotfiles/niri/config.kdl;
  home.file.".config/niri/scripts" = {
    source = ./dotfiles/niri/scripts;
    recursive = true;
    executable = true;
  };
  # Дефолтні шпалери як fallback (без блокування всієї папки wallpapers)
  xdg.configFile."niri/wallpapers/default.png".source = ./dotfiles/niri/default.png;

  # Ironbar (тільки статичні конфіги, colors.css генерується динамічно)
  xdg.configFile."ironbar/config.json".source = ./dotfiles/ironbar/config.json;
  xdg.configFile."ironbar/style.css".source = ./dotfiles/ironbar/style.css;

  # SwayNC
  xdg.configFile."swaync/config.json".source = ./dotfiles/swaync/config.json;
  xdg.configFile."swaync/style.css".source = ./dotfiles/swaync/style.css;

  # Wofi
  xdg.configFile."wofi/config".source = ./dotfiles/wofi/config;
  xdg.configFile."wofi/style.css".source = ./dotfiles/wofi/style.css;

  # Kitty (kitty.conf та дії; current-theme.conf генерується динамічно)
  xdg.configFile."kitty/kitty.conf".source = ./dotfiles/kitty/kitty.conf;
  xdg.configFile."kitty/launch-actions.conf".source = ./dotfiles/kitty/launch-actions.conf;
  xdg.configFile."kitty/open-actions.conf".source = ./dotfiles/kitty/open-actions.conf;

  # Wlogout & Hyprlock & Swappy
  xdg.configFile."wlogout/layout".source = ./dotfiles/wlogout/layout;
  xdg.configFile."wlogout/style.css".source = ./dotfiles/wlogout/style.css;
  xdg.configFile."hypr/hyprlock.conf".source = ./dotfiles/hypr/hyprlock.conf;
  xdg.configFile."hypr/colors.conf".source = ./dotfiles/hypr/colors.conf;
  xdg.configFile."swappy/config".source = ./dotfiles/swappy/config;

  # Micro editor bindings & Desktop launcher
  xdg.configFile."micro/bindings.json".source = ./dotfiles/micro/bindings.json;
  xdg.dataFile."applications/micro.desktop".source = ./dotfiles/applications/micro.desktop;

  # Starship prompt configuration
  xdg.configFile."starship.toml".source = ./dotfiles/starship.toml;

  # Теми GTK 3/4, закладки, курсор за замовчуванням та дії Thunar
  xdg.configFile."gtk-3.0/settings.ini".source = ./dotfiles/gtk-3.0/settings.ini;
  xdg.configFile."gtk-3.0/bookmarks".source = ./dotfiles/gtk-3.0/bookmarks;
  xdg.configFile."gtk-4.0/settings.ini".source = ./dotfiles/gtk-4.0/settings.ini;
  xdg.configFile."Thunar/uca.xml".source = ./dotfiles/Thunar/uca.xml;
  xdg.configFile."xfce4/xfconf/xfce-perchannel-xml/xsettings.xml".source = ./dotfiles/xfce4/xsettings.xml;
  home.file.".icons/default/index.theme".source = ./dotfiles/icons/index.theme;

  # Допоміжний скрипт Thunar "Open Terminal Here"
  home.file.".local/bin/thunar-open-terminal.sh" = {
    source = ./dotfiles/bin/thunar-open-terminal.sh;
    executable = true;
  };

  # Схема dconf для темного режиму, іконок Papirus-Dark та курсора Bibata
  dconf.settings = {
    "org/gnome/desktop/interface" = {
      color-scheme = "prefer-dark";
      gtk-theme = "Adwaita-dark";
      icon-theme = "Papirus-Dark";
      cursor-theme = "Bibata-Modern-Ice";
    };
  };
}
