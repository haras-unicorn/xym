{ selfLib, ... }:

{
  self.nixosTests.inject = {
    flake = true;

    value =
      { config, ... }:
      {
        containers.machine =
          { pkgs, ... }:
          {
            environment.systemPackages = [
              config.hostPkgs.${selfLib.overlays.namespace}.xym
              pkgs.e2fsprogs
            ];
          };

        testScript = ''
          start_all()
          machine.wait_for_unit("multi-user.target")

          machine.succeed("truncate --size 64M /root/image.img")
          machine.succeed("mkfs.ext4 -q -L NIXOS_SD /root/image.img")
          machine.succeed("""echo '{"settings": []}' > /root/ddns.json""")

          machine.succeed(
              "xym image inject /root/image.img rpi4"
              " --ddns-config /root/ddns.json"
              " --wifi-ssid xym-test --wifi-psk correct-horse"
              " --password hunter-two-hunter",
              timeout=900,
          )

          with subtest("the files land where the image modules read them"):
              machine.succeed("debugfs -R 'cat /etc/xym/ddns-updater.json' /root/image.img | grep settings")
              machine.succeed("debugfs -R 'cat /etc/NetworkManager/system-connections/xym-wifi.nmconnection' /root/image.img | grep ssid=xym-test")
              machine.succeed("debugfs -R 'cat /etc/xym/password' /root/image.img | grep -F '$6$'")
              machine.fail("debugfs -R 'cat /etc/xym/password' /root/image.img | grep hunter-two-hunter")

          with subtest("the secrets belong to root and only root reads them"):
              machine.succeed("debugfs -R 'stat /etc/xym/ddns-updater.json' /root/image.img | grep -E 'User: +0 +Group: +0'")
              machine.succeed("debugfs -R 'stat /etc/NetworkManager/system-connections/xym-wifi.nmconnection' /root/image.img | grep -E 'User: +0 +Group: +0'")
              machine.succeed("debugfs -R 'stat /etc/xym/password' /root/image.img | grep -E 'User: +0 +Group: +0'")
              machine.succeed("debugfs -R 'stat /etc/xym/ddns-updater.json' /root/image.img | grep -E 'Mode: +0600'")
              machine.succeed("debugfs -R 'stat /etc/NetworkManager/system-connections/xym-wifi.nmconnection' /root/image.img | grep -E 'Mode: +0600'")
              machine.succeed("debugfs -R 'stat /etc/xym/password' /root/image.img | grep -E 'Mode: +0600'")
        '';
      };
  };
}
