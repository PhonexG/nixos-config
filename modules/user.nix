{ ... }:

{
  users.users.oni = {
    isNormalUser = true;
    description = "oni";
    extraGroups = [
      "networkmanager"
      "wheel"
      "video"
      "audio"
      "input"
    ];
  };
}
