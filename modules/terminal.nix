{ pkgs, ... }:

let
  rebuildScript = pkgs.writeShellScriptBin "rebuild" ''
    set -euo pipefail

    REPO="/etc/nixos"
    if [ -d "$REPO/.git" ]; then
      ${pkgs.git}/bin/git -C "$REPO" add -A
    fi

    sudo nixos-rebuild switch --flake "$REPO#nixos" "$@"
  '';
in
{
  environment.sessionVariables = {
    EDITOR = "micro";
    VISUAL = "micro";
    TERMINAL = "kitty";
  };

  programs.fish = {
    enable = true;

    shellInit = ''
      set -g fish_greeting

      set -gx EDITOR micro
      set -gx VISUAL micro
      set -gx TERMINAL kitty

      set -gx SSL_CERT_FILE /etc/ssl/certs/ca-bundle.crt
      set -gx SSL_CERT_DIR /etc/ssl/certs
      set -gx NIX_SSL_CERT_FILE /etc/ssl/certs/ca-bundle.crt

      fish_add_path $HOME/.local/bin

      set -g fish_color_autosuggestion brblack
      set -g fish_color_command blue
      set -g fish_color_error red
      set -g fish_pager_color_prefix brcyan --bold
      set -g fish_pager_color_description yellow
      set -g fish_pager_color_selected_background --background=brblack
    '';

    shellAliases = {
      ls = "eza --icons --group-directories-first";
      ll = "eza -lah --icons --group-directories-first --git";
      la = "eza -a --icons --group-directories-first";
      lt = "eza --tree --level=2 --icons --group-directories-first";
      cat = "bat --paging=never";
      c = "z";

      # Git
      gs = "git status --short --branch";
      ga = "git add";
      gc = "git commit";
      gp = "git push";
      gl = "git pull";
      gco = "git checkout";
      gb = "git branch";
      gd = "git diff";

      # NixOS
      drybuild = "sudo nixos-rebuild dry-build --flake /etc/nixos#nixos";
      bootbuild = "sudo nixos-rebuild boot --flake /etc/nixos#nixos";
      nixclean = "sudo nix-collect-garbage -d";
      ngen = "sudo nixos-rebuild list-generations";
      nixpins = "echo 'Список закріплених поколінь:'; ls -la /nix/var/nix/gcroots/pinned_system_*";

      ports = "ss -tulpn";
      myip = "ip -brief addr";
      zen = "zen-beta";
    };

    interactiveShellInit = ''
      # Shell integrations
      if type -q nix-your-shell
        nix-your-shell fish | source
      end
      if type -q atuin
        atuin init fish | source
      end
      if type -q carapace
        carapace _carapace fish | source
      end

      function nixpin
        set -l current_gen (readlink /nix/var/nix/profiles/system)
        if test -z "$current_gen"
          echo "Помилка: не вдалося знайти поточне системне покоління."
          return 1
        end
        set -l timestamp (date +%Y%m%d_%H%M%S)
        set -l root_path "/nix/var/nix/gcroots/pinned_system_$timestamp"
        echo "Закріплюємо поточне покоління..."
        sudo ln -sfn $current_gen $root_path
        echo "Покоління успішно збережено: $root_path"
      end

      function nixunpin
        if test (count $argv) -eq 0
          echo "Використання: nixunpin <мітка_часу>"
          echo "Доступні закріплення:"
          ls -1 /nix/var/nix/gcroots/pinned_system_*
          return 1
        end
        sudo rm -f /nix/var/nix/gcroots/pinned_system_$argv[1]
        echo "Закріплення для '$argv[1]' знято (тепер його можна видалити через nixclean)."
      end

      function nixswitch
        if test (count $argv) -eq 0
          echo "Використання: nixswitch <номер_покоління>"
          echo "Ось доступні покоління:"
          sudo nixos-rebuild list-generations
          return 1
        end
        set -l gen $argv[1]
        set -l profile_path "/nix/var/nix/profiles/system-$gen-link"
        if test -e $profile_path
          echo "Перемикаємося на покоління №$gen..."
          sudo $profile_path/bin/switch-to-configuration switch
        else
          echo "Покоління №$gen не знайдено або вже видалене."
          return 1
        end
      end

      function nmtui
        nmcli device wifi rescan
        command nmtui $argv
      end
    '';
  };

  users.users.oni.shell = pkgs.fish;

  programs.starship.enable = true;
  programs.zoxide.enable = true;
  programs.direnv.enable = true;
  programs.fzf = {
    fuzzyCompletion = true;
    keybindings = true;
  };

  # Командний рядок та інтерактивні утиліти.
  environment.systemPackages = with pkgs; [
    rebuildScript
    starship
    micro
    nix-index
    nix-output-monitor
    btop
    fastfetch
    eza
    bat
    fd
    ripgrep
    jq
    fzf
    atuin
    carapace
    nix-your-shell
  ];
}
