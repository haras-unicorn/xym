{ selfLib, ... }:
{
  self.nixosModules.options = {
    self = false;
    flake = true;

    value =
      { lib, ... }:
      let
        tag =
          entry:
          lib.mkOption {
            type = lib.types.submodule entry.module;
            inherit (entry) description;
          };
      in
      {
        options.xym = {
          hardware = lib.mkOption {
            type = lib.types.nullOr (
              lib.types.attrTag (builtins.mapAttrs (_: tag) selfLib.hardware)
            );
            default = null;
            description = ''
              Hardware the image is built for, as a tag with the options of that
              hardware. `null` keeps the generic modules only, which is what the
              container tests use.
            '';
          };

          vpns = lib.mkOption {
            type = lib.types.listOf (
              lib.types.attrTag (builtins.mapAttrs (_: tag) selfLib.vpns)
            );
            default = [ ];
            description = ''
              VPN technologies the machine relays traffic for, each a tag with
              the options of that technology.
            '';
            example = [ { easytier.port = 11010; } ];
          };

          time.servers = lib.mkOption {
            type = lib.types.listOf lib.types.str;
            default = [
              # Google
              "216.239.35.0"
              "216.239.35.4"
              "216.239.35.8"
              "216.239.35.12"

              # Cloudflare
              "162.159.200.1"
              "162.159.200.123"
            ];
            description = ''
              NTP servers for chrony. Addresses and not names, because name
              resolution needs DNSSEC and DNSSEC needs the right time.
            '';
          };

          dns.forwards = lib.mkOption {
            type = lib.types.listOf lib.types.str;
            default = [
              # Cloudflare
              "tls://1.1.1.2%one.one.one.one"
              "tls://1.0.0.2%one.one.one.one"

              # Quad9
              "tls://9.9.9.9%dns.quad9.net"

              # ControlD
              "tls://76.76.2.11%p1.freedns.controld.com"
            ];
            description = "Upstream resolvers CoreDNS forwards to, over TLS.";
          };

          ddns.period = lib.mkOption {
            type = lib.types.str;
            default = "5m";
            description = "How often ddns-updater checks the public IP address.";
          };

          ddns.listeningAddress = lib.mkOption {
            type = lib.types.str;
            default = "127.0.0.1:8000";
            description = "Address of the ddns-updater web interface.";
          };

          ddns.healthAddress = lib.mkOption {
            type = lib.types.str;
            default = "127.0.0.1:9999";
            description = "Address of the ddns-updater health server.";
          };
        };
      };
  };
}
