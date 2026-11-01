{ ... }:

{
  # Завантажувач
  boot.loader = {
    systemd-boot = {
      enable = true;
      configurationLimit = 5;
    };
    efi.canTouchEfiVariables = true;
  };

  # Nix та обслуговування сховища
  nix = {
    settings = {
      experimental-features = [
        "nix-command"
        "flakes"
      ];
      auto-optimise-store = true;
    };

    gc = {
      automatic = true;
      dates = "weekly";
      options = "--delete-older-than 7d";
    };
  };

  nixpkgs.config.allowUnfree = true;

  # Обмеження розміру постійних системних журналів.
  services.journald.extraConfig = ''
    SystemMaxUse=200M
  '';

  # Мережа
  networking = {
    hostName = "nixos";
    networkmanager.enable = true;
  };

  # Пріоритет IPv4 над неробочим IPv6 для системних резолверів.
  environment.etc."gai.conf".text = ''
    precedence ::ffff:0:0/96  100
  '';

  # PKI та SSL-сумісність для сторонніх бінарників і агентів.
  security.pki.useCompatibleBundle = true;
  environment.sessionVariables = {
    SSL_CERT_FILE = "/etc/ssl/certs/ca-bundle.crt";
    SSL_CERT_DIR = "/etc/ssl/certs";
    NIX_SSL_CERT_FILE = "/etc/ssl/certs/ca-bundle.crt";
  };

  # Локалізація
  time.timeZone = "Europe/Kyiv";
  i18n = {
    defaultLocale = "en_US.UTF-8";
    extraLocaleSettings = {
      LC_ADDRESS = "uk_UA.UTF-8";
      LC_IDENTIFICATION = "uk_UA.UTF-8";
      LC_MEASUREMENT = "uk_UA.UTF-8";
      LC_MONETARY = "uk_UA.UTF-8";
      LC_NAME = "uk_UA.UTF-8";
      LC_NUMERIC = "uk_UA.UTF-8";
      LC_PAPER = "uk_UA.UTF-8";
      LC_TELEPHONE = "uk_UA.UTF-8";
      LC_TIME = "uk_UA.UTF-8";
    };
  };

  services.xserver.xkb = {
    layout = "us,ua";
    variant = "";
  };

  programs.git = {
    enable = true;
    config.safe.directory = "/etc/nixos";
  };
}
