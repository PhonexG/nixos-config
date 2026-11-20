{ pkgs }:

let
  unwrapped = pkgs.kdePackages.sddm.unwrapped.overrideAttrs (old: {
    patches = (old.patches or [ ]) ++ [
      # Merged upstream: actually check tty1 rather than "ttySDDM_INITIAL_VT".
      # https://github.com/sddm/sddm/pull/2110
      ./patches/sddm-initial-vt.patch
      # Keep the greeter/compositor alive until the new session has started.
      # Merged upstream: https://github.com/sddm/sddm/pull/2212
      ./patches/sddm-greeter-lifetime.patch
    ];
  });
in
pkgs.kdePackages.sddm.override { inherit unwrapped; }
