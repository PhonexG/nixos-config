{ pkgs, ... }:

let
  clipClear = pkgs.writeShellScriptBin "clip-clear" ''
    set -euo pipefail
    ${pkgs.cliphist}/bin/cliphist wipe
    ${pkgs.wl-clipboard}/bin/wl-copy --clear
    ${pkgs.libnotify}/bin/notify-send \
      "Буфер обміну" \
      "Історію буфера успішно очищено" || true
  '';
in
{
  environment.systemPackages = [ clipClear ];

  systemd.user.services = {
    cliphist = {
      description = "Cliphist clipboard history watcher";
      wantedBy = [ "graphical-session.target" ];
      partOf = [ "graphical-session.target" ];
      after = [ "graphical-session.target" ];
      serviceConfig = {
        Type = "simple";
        ExecStart = "${pkgs.wl-clipboard}/bin/wl-paste --watch ${pkgs.cliphist}/bin/cliphist store";
        Restart = "always";
        RestartSec = 2;
      };
    };

    cliphist-images = {
      description = "Cliphist clipboard image history watcher";
      wantedBy = [ "graphical-session.target" ];
      partOf = [ "graphical-session.target" ];
      after = [ "graphical-session.target" ];
      serviceConfig = {
        Type = "simple";
        ExecStart = "${pkgs.wl-clipboard}/bin/wl-paste --type image --watch ${pkgs.cliphist}/bin/cliphist store";
        Restart = "always";
        RestartSec = 2;
      };
    };
  };
}
