{
  # the installer writes the optional Wi-Fi profile of the user here, and
  # NetworkManager reads every profile in this directory
  self.lib.inject.wifi = "/etc/NetworkManager/system-connections/xym-wifi.nmconnection";

  self.nixosModules.networkmanager = {
    self = false;
    flake = true;

    value = {
      systemd.network.enable = false;
      systemd.network.wait-online.enable = false;

      networking.networkmanager.enable = true;
      networking.networkmanager.wifi.powersave = false;
    };
  };
}
