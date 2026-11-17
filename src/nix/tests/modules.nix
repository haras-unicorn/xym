{ config, ... }:
{
  self.nixosTests.modules = {
    flake = true;

    value = _: {
      containers.machine = {
        imports = [ config.flake.nixosModules.default ];
        xym.vpns = [ { easytier = { }; } ];
      };

      testScript = ''
        start_all()

        machine.wait_for_unit("coredns.service")
        machine.wait_for_open_port(53, "127.0.0.1")

        machine.wait_for_unit("easytier-xym.service")
        machine.wait_for_open_port(11010)

        machine.wait_for_unit("sshd.socket")
        machine.wait_for_open_port(22)
        machine.succeed("grep -i 'PermitRootLogin no' /etc/ssh/sshd_config")
        machine.succeed("id xym | grep wheel")

        # the device can rebuild itself, and its user can find out what is wrong
        machine.succeed("type nixos-rebuild nix man dig tcpdump htop easytier-cli")
        machine.succeed("systemctl cat systemd-coredump.socket")

        machine.succeed("systemctl cat chronyd.service")
        machine.succeed("systemctl cat NetworkManager.service")
        machine.succeed("systemctl cat ddns-updater.service | grep LoadCredential")
        machine.succeed("grep 127.0.0.1 /etc/resolv.conf")
      '';
    };
  };
}
