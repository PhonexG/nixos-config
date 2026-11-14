{ config, ... }:

{
  xdg.enable = true;

  home.sessionVariables = {
    STARSHIP_CONFIG = "${config.home.homeDirectory}/.config/themes/current/starship.toml";
  };

  home.file.".local/bin/theme-switcher.sh" = {
    source = ../scripts/theme-switcher.sh;
    executable = true;
  };

  xdg.configFile = {
    "themes/current".source = config.lib.file.mkOutOfStoreSymlink "/etc/nixos/home/themes/rail-dark";

    "ironbar/config.toml".source =
      config.lib.file.mkOutOfStoreSymlink "${config.home.homeDirectory}/.config/themes/current/ironbar.toml";
    "ironbar/style.css".source =
      config.lib.file.mkOutOfStoreSymlink "${config.home.homeDirectory}/.config/themes/current/ironbar.css";

    "gtk-3.0/gtk.css".text = ''
      @import url("file://${config.home.homeDirectory}/.config/themes/current/gtk.css");
    '';
    "gtk-4.0/gtk.css".text = ''
      @import url("file://${config.home.homeDirectory}/.config/themes/current/gtk.css");
    '';

    "fish/config.fish".source = ./dotfiles/fish/config.fish;
    "starship.toml".source =
      config.lib.file.mkOutOfStoreSymlink "${config.home.homeDirectory}/.config/themes/current/starship.toml";
  };

  dconf.settings."org/gnome/desktop/interface" = {
    color-scheme = "prefer-dark";
    gtk-theme = "Adwaita-dark";
    icon-theme = "Papirus-Dark";
    cursor-theme = "Bibata-Modern-Ice";
  };
}
