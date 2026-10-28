{ config, pkgs, ... }:

let
  toggleEco = pkgs.callPackage ../scripts/toggle-eco.nix {};
in {
  # Завантаження драйвера HP BIOS WMI для перевірки параметрів у sysfs
  boot.kernelModules = [ "hp-bioscfg" ];

  services.power-profiles-daemon.enable = false;

  services.tlp = {
    enable = true;

    settings = {
      PLATFORM_PROFILE_ON_AC = "performance";
      PLATFORM_PROFILE_ON_BAT = "balanced";

      CPU_SCALING_GOVERNOR_ON_AC = "schedutil";
      CPU_SCALING_GOVERNOR_ON_BAT = "powersave";

      CPU_ENERGY_PERF_POLICY_ON_AC = "balance_performance";
      CPU_ENERGY_PERF_POLICY_ON_BAT = "balance_power";

      CPU_BOOST_ON_AC = 1;
      CPU_BOOST_ON_BAT = 1;

      WIFI_PWR_ON_AC = "off";
      WIFI_PWR_ON_BAT = "off";

      SOUND_POWER_SAVE_ON_AC = 0;
      SOUND_POWER_SAVE_ON_BAT = 1;
      SOUND_POWER_SAVE_CONTROLLER = "Y";

      RUNTIME_PM_ON_AC = "on";
      RUNTIME_PM_ON_BAT = "auto";

      USB_AUTOSUSPEND = 1;

      NVME_APST_ON_BAT = 1;

      PCIE_ASPM_ON_AC = "performance";
      PCIE_ASPM_ON_BAT = "powersupersave";

      AHCI_RUNTIME_PM_ON_AC = "on";
      AHCI_RUNTIME_PM_ON_BAT = "auto";

      RADEON_DPM_PERF_LEVEL_ON_AC = "auto";
      RADEON_DPM_PERF_LEVEL_ON_BAT = "auto";

      AMDGPU_ABM_LEVEL_ON_AC = 0;
      AMDGPU_ABM_LEVEL_ON_BAT = 1;

      DEVICES_TO_DISABLE_ON_BAT_NOT_IN_USE = "bluetooth";
      SCHED_POWERSAVE_ON_BAT = 1;
    };
  };

  services.logind.settings.Login = {
    HandleLidSwitch = "suspend";
    HandleLidSwitchExternalPower = "suspend";
    HandleLidSwitchDocked = "suspend";
    HandlePowerKey = "suspend";
    HandleSuspendKey = "suspend";
    LidSwitchIgnoreInhibited = "yes";
  };

  services.upower.enable = true;

  systemd.sleep.extraConfig = ''
    AllowSuspend=yes
    AllowHibernation=no
    AllowHybridSleep=no
    AllowSuspendThenHibernate=no
  '';

  environment.systemPackages = [
    toggleEco
    pkgs.powertop
  ];

  security.sudo.extraRules = [
    {
      users = [ "oni" ];

      commands = [
        {
          command = "/run/current-system/sw/bin/toggle-eco";
          options = [ "NOPASSWD" ];
        }
        {
          command = "${toggleEco}/bin/toggle-eco";
          options = [ "NOPASSWD" ];
        }
      ];
    }
  ];
}
