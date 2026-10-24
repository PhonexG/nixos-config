{
  description = "Oni NixOS — minimal Niri workstation";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-25.11";
    home-manager = {
      url = "github:nix-community/home-manager/release-25.11";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    zen-browser = {
      url = "github:0xc000022070/zen-browser-flake";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = { self, nixpkgs, home-manager, ... }@inputs:
    let
      system = "x86_64-linux";
    in {
      nixosConfigurations.nixos = nixpkgs.lib.nixosSystem {
        inherit system;
        specialArgs = { inherit inputs; };
        modules = [
          ./configuration.nix
          home-manager.nixosModules.home-manager
          {
            home-manager = {
              useGlobalPkgs = true;
              useUserPackages = true;
              backupFileExtension = "hm-backup";
              extraSpecialArgs = { inherit inputs; };
              users.oni = import ./home/oni.nix;
            };
          }
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
