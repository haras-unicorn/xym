{
  self.nixosModules.chrony = {
    self = false;
    flake = true;

    value =
      { config, ... }:
      {
        services.timesyncd.enable = false;

        networking.timeServers = config.xym.time.servers;

        services.chrony.enable = true;
      };
  };
}
