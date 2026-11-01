{ inputs, pkgs, ... }:

let
  system = pkgs.stdenv.hostPlatform.system;
  zenBrowser = inputs.zen-browser.packages.${system}.default;
in
{
  # Загальні пакети, які не належать до конкретного сервісу або модуля.
  environment.systemPackages = with pkgs; [
    # Базові мережеві інструменти
    curl
    wget

    # Графічні програми
    zenBrowser
    telegram-desktop
    obsidian
    steam

    # Мультимедіа
    mpv
    ffmpeg

    # Облікові дані та словники
    seahorse
    libsecret
    hunspell
    hunspellDicts.uk_UA
    hunspellDicts.en_US
  ];
}
