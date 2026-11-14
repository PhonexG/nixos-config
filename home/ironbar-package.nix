{ pkgs }:

pkgs.symlinkJoin {
  name = "ironbar-wrapped-${pkgs.ironbar.version}";
  paths = [ pkgs.ironbar ];
  nativeBuildInputs = [ pkgs.makeWrapper ];
  postBuild = ''
    wrapProgram "$out/bin/ironbar" \
      --prefix PATH : "${
        pkgs.lib.makeBinPath [
          pkgs.networkmanager
          pkgs.bluez
          pkgs.util-linux
          pkgs.libnotify
        ]
      }"
  '';
  inherit (pkgs.ironbar) meta;
}
