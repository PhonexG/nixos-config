{ pkgs }:

# Keep the pinned OSD renderer passive; only reduce its widget sizing and timeout.
pkgs.swayosd.overrideAttrs (old: {
  patches = (old.patches or [ ]) ++ [ ./dotfiles/swayosd/swayosd-0.2.1-compact.patch ];
})
