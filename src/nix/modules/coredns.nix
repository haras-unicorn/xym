{
  self.nixosModules.coredns = {
    self = false;
    flake = true;

    value =
      { config, ... }:
      let
        forwards = builtins.concatStringsSep " " config.xym.dns.forwards;
      in
      {
        services.resolved.enable = false;

        networking.networkmanager.dns = "none";
        networking.nameservers = [ "127.0.0.1" ];

        services.coredns = {
          enable = true;
          config = ''
            . {
              bind 127.0.0.1
              dnssec
              cache
              forward . ${forwards}
            }
          '';
        };
      };
  };
}
