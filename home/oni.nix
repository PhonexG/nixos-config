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

  # Waybar (тільки статичні конфіги, colors.css генерується динамічно)
  xdg.configFile."waybar/config.jsonc".source = ./dotfiles/waybar/config.jsonc;
  xdg.configFile."waybar/style.css".source = ./dotfiles/waybar/style.css;

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

  # Wlogout
  xdg.configFile."wlogout/layout".source = ./dotfiles/wlogout/layout;
  xdg.configFile."wlogout/style.css".source = ./dotfiles/wlogout/style.css;

  # Micro editor bindings
  xdg.configFile."micro/bindings.json".source = ./dotfiles/micro/bindings.json;

  # Starship prompt configuration
  xdg.configFile."starship.toml".source = ./dotfiles/starship.toml;
}
