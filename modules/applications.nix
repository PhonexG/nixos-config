{ config, pkgs, inputs, ... }:

{
  environment.systemPackages = with pkgs; [
    # GUI & Productivity Applications
    inputs.zen-browser.packages.${pkgs.stdenv.hostPlatform.system}.default
    telegram-desktop
    rclone
    obsidian
    steam

    # Media, Credentials & Dictionaries
    mpv
    ffmpeg
    seahorse
    libsecret
    hunspell
    hunspellDicts.uk_UA
    hunspellDicts.en_US
  ];
}
