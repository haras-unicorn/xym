{
  self.nixosModules.diagnostics = {
    self = false;
    flake = true;

    value =
      { pkgs, ... }:
      {
        # enough to find out why a relay misbehaves, and not more
        environment.systemPackages = [
          pkgs.bind.dnsutils
          pkgs.curl
          pkgs.ethtool
          pkgs.htop
          pkgs.lsof
          pkgs.mtr
          pkgs.strace
          pkgs.tcpdump
        ];
      };
  };
}
