{ pkgs, ... }:

{
  # Контейнери
  virtualisation = {
    containers.enable = true;
    docker = {
      enable = true;
      enableOnBoot = false;
      package = pkgs.docker_29;
      autoPrune = {
        enable = true;
        dates = "weekly";
      };
    };
  };

  users.users.oni.extraGroups = [ "docker" ];

  # Запуск сторонніх динамічних бінарників.
  services.envfs.enable = false;
  programs.nix-ld = {
    enable = true;
    libraries = with pkgs; [
      # GIO / GLib
      glib

      # Звук
      alsa-lib

      # Графіка, Wayland та Vulkan
      vulkan-loader
      libxkbcommon
      wayland
      mesa
      libGL
      libglvnd

      # X11 fallback
      xorg.libX11
      xorg.libXcursor
      xorg.libXi
      xorg.libXrandr
      xorg.libxcb

      # Базові системні бібліотеки
      fontconfig
      freetype
      stdenv.cc.cc
      zlib
      openssl
    ];
  };

  # Глобальний набір інструментів розробника.
  environment.systemPackages = with pkgs; [
    # Мови та компілятори
    python3
    gcc

    # Системи збирання та налагодження
    gnumake
    cmake
    ninja
    pkg-config
    gdb
    clang-tools

    # Python tooling та LSP
    pyright
    ruff

    # Керування контейнерами
    docker-compose
    lazydocker
  ];
}
