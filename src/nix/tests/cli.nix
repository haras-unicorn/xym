{ selfLib, ... }:

{
  self.nixosTests.cli = {
    flake = true;

    value =
      { config, ... }:
      {
        containers.machine = {
          environment.systemPackages = [
            config.hostPkgs.${selfLib.overlays.namespace}.xym
          ];
        };

        testScript = ''
          fake = "XYM_FAKE=1 xym"
          dry = "XYM_FAKE=1 XYM_DRY_RUN=1 xym"

          start_all()
          machine.wait_for_unit("multi-user.target")

          with subtest("hardware and vpn are checked against the registry"):
              machine.succeed(f"{fake} hardware list | grep rpi4")
              machine.succeed(f"{fake} vpn list | grep easytier")
              machine.succeed(f"{fake} hardware check rpi4")
              machine.succeed(f"{fake} vpn check easytier")
              machine.fail(f"{fake} hardware check nope")
              machine.fail(f"{fake} vpn check nope")
              machine.fail(f"{fake} vpn check")
              machine.fail(f"{fake} vpn check easytier nope")

          with subtest("only whole, free, big enough disks pass"):
              machine.succeed(f"{fake} device list | grep /dev/sda")
              machine.succeed(f"{fake} device check /dev/sda")
              machine.succeed(f"{fake} device check /dev/sda --min-size 4GiB")
              machine.fail(f"{fake} device check /dev/sda --min-size 64GiB")
              machine.fail(f"{fake} device check /dev/sda1")
              machine.fail(f"{fake} device check /dev/nvme0n1")
              machine.fail(f"{fake} device check /dev/loop0")
              machine.fail(f"{fake} device check /dev/missing")

          with subtest("ddns-updater configs are validated before running"):
              machine.succeed("""echo '{"settings": [{"provider": "duckdns", "domain": "a.duckdns.org", "token": "t"}]}' > /root/good.json""")
              machine.succeed("echo nope > /root/bad.json")
              machine.succeed("""echo '{"settings": []}' > /root/empty.json""")
              machine.succeed("""echo '{"settings": [{"domain": "a.duckdns.org"}]}' > /root/unnamed.json""")
              machine.succeed(f"{fake} ddns check /root/good.json")
              machine.fail(f"{fake} ddns check /root/bad.json")
              machine.fail(f"{fake} ddns check /root/empty.json")
              machine.fail(f"{fake} ddns check /root/unnamed.json")
              machine.fail("xym ddns check /root/missing.json")

          with subtest("passwords are validated before the long build"):
              machine.succeed(f"{fake} password check correct-horse")
              machine.fail(f"{fake} password check short")

          with subtest("the wifi check informs and never fails"):
              machine.succeed(f"{fake} wifi check some-network some-password | grep connected")

          with subtest("a dry run changes nothing"):
              machine.succeed(f"{dry} image build rpi4 easytier | grep sd-image/xym.img")
              machine.fail(f"{dry} image build rpi4 nope")
              machine.succeed(f"{dry} image prepare /root/none.img rpi4 --ddns-config /root/good.json --password correct-horse | grep dry-run.img")
              machine.succeed(f"{dry} image write /root/none.img /dev/sda | grep 'dry run'")
              machine.fail(f"{dry} image write /root/none.img /dev/sda1")

          with subtest("updates check the device before building or copying"):
              machine.succeed(f"{fake} address check relay.example.org")
              machine.succeed(f"{fake} address check 192.168.1.5")
              machine.fail(f"{fake} address check 'a b'")
              machine.fail(f"{fake} address check xym@relay")
              machine.fail(f"{fake} address check 'relay;reboot'")
              machine.succeed(f"{fake} update 192.168.1.5 rpi4 easytier | grep 192.168.1.5")
              machine.fail(f"{fake} update 192.168.1.5 nope easytier")
              machine.fail(f"{fake} update 192.168.1.5 rpi4 nope")
              machine.fail(f"{fake} update 192.168.1.5 rpi4")
              machine.fail(f"{fake} update 'a b' rpi4 easytier")
              machine.fail(f"XYM_FAKE_DEVICE_ARCH=x86_64 {fake} update 192.168.1.5 rpi4 easytier")

          with subtest("cleaning refuses files xym did not make"):
              machine.fail(f"{fake} image clean /etc/passwd")
        '';
      };
  };
}
