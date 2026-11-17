let
  # the installer writes the ddns-updater config of the user here
  configPath = "/etc/xym/ddns-updater.json";
in
{
  self.lib.inject.ddns = configPath;

  self.nixosModules.ddns-updater = {
    self = false;
    flake = true;

    value =
      { config, lib, ... }:
      let
        cfg = config.xym.ddns;
      in
      {
        services.ddns-updater = {
          enable = true;
          environment = {
            # %d is the credentials directory, see LoadCredential below
            CONFIG_FILEPATH = "%d/config.json";
            PERIOD = cfg.period;
            LISTENING_ADDRESS = cfg.listeningAddress;
            HEALTH_SERVER_ADDRESS = cfg.healthAddress;
            RESOLVER_ADDRESS = "${builtins.head config.networking.nameservers}:53";
          };
        };

        systemd.services.ddns-updater = {
          wants = [
            "coredns.service"
            "chronyd.service"
          ];
          after = [
            "coredns.service"
            "chronyd.service"
          ];

          unitConfig.ConditionPathExists = configPath;

          serviceConfig = {
            LoadCredential = "config.json:${configPath}";
            Restart = lib.mkForce "always";
          };
        };
      };
  };
}
