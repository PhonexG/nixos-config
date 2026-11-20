{ pkgs, ... }:

{
  services.udisks2 = {
    enable = true;
    mountOnMedia = true;
  };

  services.gvfs.enable = true;
  services.tumbler.enable = true;

  security.polkit.extraConfig = ''
    polkit.addRule(function(action, subject) {
      if (subject.isInGroup("wheel") && (
        action.id == "org.freedesktop.udisks2.filesystem-mount" ||
        action.id == "org.freedesktop.udisks2.filesystem-mount-system" ||
        action.id == "org.freedesktop.udisks2.filesystem-unmount-others"
      )) {
        return polkit.Result.YES;
      }
    });
  '';

  boot.supportedFilesystems = [
    "ntfs"
    "exfat"
    "vfat"
    "btrfs"
    "ext4"
  ];

  boot.kernel.sysctl = {
    "vm.dirty_background_bytes" = 16 * 1024 * 1024; # 16 MB
    "vm.dirty_bytes" = 48 * 1024 * 1024; # 48 MB
  };

  # Standard Thunar without source patches.
  programs.thunar = {
    enable = true;
    plugins = with pkgs.xfce; [
      thunar-archive-plugin
      thunar-volman
    ];
  };

  programs.xfconf.enable = true;

  environment.systemPackages = with pkgs; [
    # GUI archive manager
    file-roller

    # Archive formats
    _7zz
    p7zip
    unrar
    unar
    unzip
    zip
    gnutar
    gzip
    bzip2
    xz
    zstd
    lzip
    lrzip
    lzop
    cpio

    # Storage devices and filesystems
    xfce.exo
    udisks2
    gvfs
    ntfs3g
    exfatprogs
    dosfstools
    gparted
    usbutils
    pciutils
    util-linux
  ];
}
