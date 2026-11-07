{ pkgs, ... }:

let
  vp = pkgs.vimPlugins;

  lazyPlugins = with vp; [
    tokyonight-nvim
    telescope-nvim
    plenary-nvim
    nvim-autopairs
  ];
in
{
  programs.neovim = {
    enable = true;

    withPython3 = false;
    withRuby = false;

    extraPackages = with pkgs; [
      ripgrep
      fd
    ];

    plugins = [ vp.lazy-nvim ] ++ map (plugin: {
      inherit plugin;
      optional = true;
    }) lazyPlugins;

    extraLuaConfig = ''
      vim.g.mapleader = " "

      -- Шляхи до плагінів, установлених через Nix.
      vim.g.nix_plugins = {
        tokyonight = "${vp.tokyonight-nvim}",
        telescope = "${vp.telescope-nvim}",
        plenary = "${vp.plenary-nvim}",
        autopairs = "${vp.nvim-autopairs}",
      }

      vim.opt.rtp:prepend("${vp.lazy-nvim}")

      require("config.options")
      require("config.lazy")
    '';
  };

  xdg.configFile."nvim/lua/config" = {
    source = ./dotfiles/nvim/lua/config;
    recursive = true;
  };
}
