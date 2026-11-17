{
  self.nixosModules.base = {
    self = false;
    flake = true;

    value =
      { lib, ... }:
      {
        # idiomatic for NixOS because the state version is pinned once per
        # install, and an image is a fresh install
        system.stateVersion = "26.05";

        time.timeZone = "UTC";

        # the xym user is the only login, and its password comes from the
        # installer, so nobody changes users by hand
        users.mutableUsers = false;

        # the device can rebuild itself or be deployed to, so nix stays
        nix.settings.experimental-features = [
          "nix-command"
          "flakes"
        ];
        nix.channel.enable = false;

        # copying a system to the device needs a trusted user, and wheel can
        # become root with the same password anyway
        nix.settings.trusted-users = [ "@wheel" ];

        # the registry entry would put the whole nixpkgs source into the image
        nixpkgs.flake.setNixPath = false;
        nixpkgs.flake.setFlakeRegistry = false;

        # the diagnostics module lists what the xym user gets instead
        environment.defaultPackages = lib.mkForce [ ];
        programs.command-not-found.enable = false;

        services.udisks2.enable = false;
        boot.enableContainers = false;
      };
  };
}
