{
  self.nixosModules.internal = {
    self = false;
    flake = true;

    value =
      { lib, ... }:
      {
        options.xym.internal.unfreePackages = lib.mkOption {
          type = lib.types.listOf lib.types.str;
          default = [ ];
          internal = true;
          description = ''
            Names of unfree packages the image is allowed to contain. Hardware
            modules add the firmware they need, and the image build turns the
            list into the allow predicate of nixpkgs.
          '';
        };
      };
  };
}
