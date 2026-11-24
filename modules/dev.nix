{ pkgs, ... }:

{
  # Containers
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

  # Run third-party dynamic binaries.
  services.envfs.enable = false;
  programs.nix-ld = {
    enable = true;
    libraries = with pkgs; [
      # GIO / GLib
      glib

      # Audio
      alsa-lib

      # Graphics, Wayland, and Vulkan
      vulkan-loader
      libxkbcommon
      wayland
      mesa
      libGL
      libglvnd

      # X11 fallback
      xorg.libX11
      xorg.libXcomposite
      xorg.libXcursor
      xorg.libXdamage
      xorg.libXext
      xorg.libXfixes
      xorg.libXi
      xorg.libXrandr
      xorg.libxcb

      # Electron / Chromium GUI libraries
      nspr
      nss
      atk
      at-spi2-atk
      at-spi2-core
      cups
      dbus
      cairo
      gtk3
      pango
      libgbm
      libdrm
      expat

      # Base system libraries
      fontconfig
      freetype
      stdenv.cc.cc
      zlib
      openssl
    ];
  };

  # Global developer toolset.
  environment.systemPackages = with pkgs; [
    # Languages and compilers
    python3
    gcc

    # Build systems and debugging
    gnumake
    cmake
    ninja
    pkg-config
    gdb
    clang-tools

    # Python tooling and LSP
    pyright
    ruff

    # Container management
    docker-compose
    lazydocker
  ];
}
