{ pkgs, ... }:

{
  environment.systemPackages = [ pkgs.rclone ];

  systemd.user = {
    services.rclone-bisync = {
      description = "Rclone self-healing bisync for Google Drive";
      wants = [ "network-online.target" ];
      after = [ "network-online.target" ];
      serviceConfig = {
        Type = "oneshot";
        ExecStart = "${pkgs.bash}/bin/bash %h/.config/rclone/rclone-autofix.sh";
        Nice = 19;
        IOSchedulingClass = "idle";
        CPUSchedulingPolicy = "idle";
      };
    };

    timers.rclone-bisync = {
      description = "Run Rclone Bisync every 10 minutes";
      wantedBy = [ "timers.target" ];
      timerConfig = {
        OnBootSec = "2m";
        OnUnitActiveSec = "10m";
        AccuracySec = "1m";
        Persistent = true;
        Unit = "rclone-bisync.service";
      };
    };
  };
}
