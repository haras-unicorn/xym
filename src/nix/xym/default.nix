{ self, selfLib, ... }:
let
  registry = {
    hardware = builtins.mapAttrs (_: hardware: {
      inherit (hardware) system rootLabel;
    }) selfLib.hardware;
    vpns = builtins.attrNames selfLib.vpns;
    inherit (selfLib) access inject;
  };

  tunables = {
    ddns = {
      timeoutSeconds = 180;
      logLines = 30;
      pollSeconds = 2;
      period = "1h";
      listeningAddress = "127.0.0.1:18000";
      healthAddress = "127.0.0.1:19999";
    };
    wifi.timeoutSeconds = 30;
    password.minLength = 8;
    update = {
      systemProfile = "/nix/var/nix/profiles/system";
      switchUnit = "xym-switch";
    };
    image.writeBlockSize = "4M";
  };
in
{
  self.overlays.overlays.xym = {
    flake = true;

    value =
      final: _prev:
      let
        # NOTE: haraspkgs only makes an app out of a package with a description,
        # and writeNushellApplication sets none
        described =
          description: package:
          package.overrideAttrs (old: {
            meta = old.meta // {
              inherit description;
            };
          });

        script = final.harasPackages.renderMustacheText {
          name = "xym.nu";
          text = builtins.readFile ./xym.nu;
          vars = {
            registry = builtins.toJSON registry;
            tunables = builtins.toJSON tunables;
            # the images are built from exactly the revision this script is from
            flake = "${self}";
          };
        };

        xym = described "Write a NixOS image that relays VPN traffic to a disk" (
          final.harasPackages.writeNushellApplication {
            name = "xym";
            runtimeInputs = [
              final.gum
              final.coreutils
              final.util-linux
              final.ddns-updater
              final.networkmanager
              final.openssl
              final.openssh
              final.libguestfs-with-appliance
            ];
            environment = {
              # libvirt is not needed to edit a disk image
              LIBGUESTFS_BACKEND = "direct";
            };
            text = script;
          }
        );
      in
      {
        inherit xym;

        default = xym;

        xym-fake = described "Preview the xym wizard with fake data and a dry run" (
          final.harasPackages.writeNushellApplication {
            name = "xym-fake";
            environment = {
              XYM_FAKE = "1";
              XYM_DRY_RUN = "1";
            };
            text = ''
              def --wrapped main [...arguments: string] {
                run-external "${final.lib.getExe xym}" ...$arguments
              }
            '';
          }
        );
      };
  };
}
