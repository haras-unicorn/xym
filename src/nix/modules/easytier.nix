let
  # a relay carries the traffic of other networks, so the name of its own
  # network does not matter
  networkName = "xym";
in
{
  self.lib.vpns.easytier = {
    description = "EasyTier relay for the networks that connect to it.";

    module =
      { lib, ... }:
      {
        options.port = lib.mkOption {
          type = lib.types.port;
          default = 11010;
          description = "TCP and UDP port the relay listens on.";
        };
      };
  };

  self.nixosModules.easytier = {
    self = false;
    flake = true;

    value =
      {
        config,
        lib,
        pkgs,
        ...
      }:
      let
        relays = builtins.filter (vpn: vpn ? easytier) config.xym.vpns;
        cfg = (builtins.head relays).easytier;
        listener = protocol: "${protocol}://0.0.0.0:${builtins.toString cfg.port}";
      in
      lib.mkIf (relays != [ ]) {
        assertions = [
          {
            assertion = builtins.length relays == 1;
            message = "xym.vpns can list easytier only once";
          }
        ];

        services.easytier = {
          enable = true;
          instances.xym = {
            enable = true;
            settings = {
              hostname = config.networking.hostName;
              dhcp = false;
              listeners = [
                (listener "tcp")
                (listener "udp")
              ];
            };
            extraSettings = {
              network_identity.network_name = networkName;
              flags = {
                private_mode = false;
                relay_network_whitelist = "*";
                relay_all_peer_rpc = true;
                # a relay forwards inside EasyTier and never needs a TUN device
                no_tun = true;
              };
            };
          };
        };

        # easytier-cli shows the peers and routes of the relay
        environment.systemPackages = [ pkgs.easytier ];

        networking.firewall.allowedTCPPorts = [ cfg.port ];
        networking.firewall.allowedUDPPorts = [ cfg.port ];
      };
  };
}
