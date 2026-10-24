{ config, pkgs, ... }:

{
  # Docker virtualization
  virtualisation.containers.enable = true;
  virtualisation.docker = {
    enable = true;
    enableOnBoot = false;
    package = pkgs.docker_29;
    autoPrune = {
      enable = true;
      dates = "weekly";
    };
  };

# FHS and dynamic binary execution
          services.envfs.enable = false;
       	programs.nix-ld.enable = true;
            programs.nix-ld.libraries = with pkgs; [
              # GIO / GLib (виправляє помилку libgio-2.0.so.0)
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
          
              # X11 (потрібні для xwayland fallback)
              xorg.libX11
              xorg.libXcursor
              xorg.libXi
              xorg.libXrandr
              xorg.libxcb
          
              # Шрифти та базові системні ліби
              fontconfig
              freetype
              stdenv.cc.cc
              zlib
              openssl
            ];
  
  # Developer baseline toolchain (available globally)
  environment.systemPackages = with pkgs; [
    # Compilers, build systems, debuggers
    gcc
    gnumake
    cmake
    ninja
    pkg-config
    gdb
    clang-tools # provides system clangd LSP

    # Language tooling & LSPs
    pyright
    ruff

    # Container orchestration tools
    docker-compose
    lazydocker
  ];

  users.users.oni.extraGroups = [
    "docker"
  ];
}
