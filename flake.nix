{
  description = "Oni NixOS — minimal Niri workstation";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-25.11";
    zen-browser = {
      url = "github:0xc000022070/zen-browser-flake";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = { self, nixpkgs, ... }@inputs:
    let
      system = "x86_64-linux";
    in {
      nixosConfigurations.nixos = nixpkgs.lib.nixosSystem {
        inherit system;
        specialArgs = { inherit inputs; };
        modules = [
          ./configuration.nix
        ];
      };

      # Project scaffolds:  nix flake init -t /etc/nixos#cpp   (or #python)
      templates = {
        cpp = {
          path = ./templates/cpp;
          description = "C/C++ dev shell: gcc, cmake, ninja, gdb, clangd";
        };
        python = {
          path = ./templates/python;
          description = "Python dev shell with uv and ruff";
        };
      };
    };
}
