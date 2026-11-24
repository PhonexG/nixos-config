{ pkgs, ... }:

let
  toggleEco = pkgs.callPackage ../scripts/toggle-eco.nix { };
in
{
  # Load HP BIOS WMI driver to inspect parameters in sysfs
  boot.kernelModules = [ "hp-bioscfg" ];

  services.power-profiles-daemon.enable = false;

  services.tlp = {
    enable = true;

    settings = {
      CPU_SCALING_GOVERNOR_ON_AC = "powersave";
      CPU_SCALING_GOVERNOR_ON_BAT = "powersave";

      CPU_ENERGY_PERF_POLICY_ON_AC = "balance_performance";
      CPU_ENERGY_PERF_POLICY_ON_BAT = "balance_power";

      CPU_BOOST_ON_AC = 1;
      CPU_BOOST_ON_BAT = 1;

      WIFI_PWR_ON_AC = "off";
      WIFI_PWR_ON_BAT = "off";
      WOL_DISABLE = "Y";

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

      AMDGPU_ABM_LEVEL_ON_AC = 0;
      AMDGPU_ABM_LEVEL_ON_BAT = 1;

      DEVICES_TO_DISABLE_ON_BAT_NOT_IN_USE = "bluetooth";
    };
  };

  # Prevent spurious AC s2idle wake-sleep loops from Ethernet/WWAN while
  # preserving lid switch, power button, and keyboard wakeup.
  networking.networkmanager.settings.connection."ethernet.wake-on-lan" = 0;

  services.udev.extraRules = ''
    # Realtek RTL8111/8168 Ethernet (r8169)
    ACTION=="add|bind", SUBSYSTEM=="pci", ATTR{vendor}=="0x10ec", ATTR{device}=="0x8168", TEST=="power/wakeup", ATTR{power/wakeup}="disabled"
    # MediaTek T700 5G WWAN modem (mtk_t7xx)
    ACTION=="add|bind", SUBSYSTEM=="pci", ATTR{vendor}=="0x14c3", ATTR{device}=="0x4d75", TEST=="power/wakeup", ATTR{power/wakeup}="disabled"
  '';

  services.logind.settings.Login = {
    HandleLidSwitch = "suspend";
    HandleLidSwitchExternalPower = "suspend";
    HandleLidSwitchDocked = "suspend";
    HandlePowerKey = "suspend";
    HandleSuspendKey = "suspend";
    LidSwitchIgnoreInhibited = "no";
  };

  services.upower.enable = true;

  systemd.sleep.extraConfig = ''
    AllowSuspend=yes
    AllowHibernation=no
    AllowHybridSleep=no
    AllowSuspendThenHibernate=no
  '';

  environment.systemPackages = with pkgs; [
    toggleEco
    powertop
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
