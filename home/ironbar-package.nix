{ pkgs }:

# Fix the GTK3 timer/hotspot and tray issues in the pinned Ironbar itself.
# Keep flake inputs and other desktop packages unchanged.
pkgs.ironbar.overrideAttrs (old: {
  patches = (old.patches or [ ]) ++ [ ./dotfiles/ironbar/ironbar-0.17.1-stability.patch ];
  postPatch = (old.postPatch or "") + ''
    cp ${./dotfiles/ironbar/networkmanager.rs} src/modules/networkmanager.rs
    ${pkgs.python3}/bin/python ${./dotfiles/ironbar/prepare-source.py}
  '';
  preFixup = (old.preFixup or "") + ''
    gappsWrapperArgs+=(--prefix PATH : "${
      pkgs.lib.makeBinPath [
        pkgs.networkmanager
        pkgs.bluez
        pkgs.util-linux
        pkgs.libnotify
      ]
    }")
  '';
})
