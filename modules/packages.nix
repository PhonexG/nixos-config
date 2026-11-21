{ inputs, pkgs, ... }:

let
  system = pkgs.stdenv.hostPlatform.system;
  zenBrowser = inputs.zen-browser.packages.${system}.default;
in
{
  # General packages not tied to a specific service or module.
  environment.systemPackages = with pkgs; [
    # Basic networking tools
    curl
    wget

    # GUI applications
    zenBrowser
    telegram-desktop
    obsidian
    steam
    jetbrains.idea 
    # Multimedia
    mpv
    ffmpeg

    # Keyring and dictionaries
    seahorse
    libsecret
    hunspell
    hunspellDicts.uk_UA
    hunspellDicts.en_US
  ];
}
