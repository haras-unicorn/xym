{ inputs, ... }:
let
  rootLabel = "NIXOS_SD";
in
{
  self.lib.hardware.rpi4 = {
    description = "Raspberry Pi 4.";
    system = "aarch64-linux";
    inherit rootLabel;

    # the Raspberry Pi 4 has no options of its own
    module = { };

    image = {
      modules = [
        "${inputs.nixpkgs}/nixos/modules/installer/sd-card/sd-image-aarch64.nix"
        # the profile pulls in installer tools and filesystems the relay never uses
        { disabledModules = [ "profiles/base.nix" ]; }
        # the installer copies and writes the image as it is, so compressing it
        # only costs build time and unpack time
        { sdImage.compressImage = false; }
      ];
      output = nixos: nixos.config.system.build.sdImage;
    };
  };

  self.nixosModules.rpi4 = {
    self = false;
    flake = true;

    value =
      {
        config,
        lib,
        pkgs,
        ...
      }:
      lib.mkIf (config.xym.hardware ? rpi4) {
        nixpkgs.overlays = [
          (_: prev: {
            # NOTE: https://github.com/NixOS/nixpkgs/issues/154163#issuecomment-1008362877
            makeModulesClosure = x: prev.makeModulesClosure (x // { allowMissing = true; });
          })
        ];

        xym.internal.unfreePackages = [
          "raspberrypifw"
          "raspberrypi-eeprom"
          "raspberrypi-wireless-firmware"
        ];

        # the default kernel is cached, the Raspberry Pi vendor kernel is not
        # and nixpkgs is dropping it, so there is no boot.kernelPackages here

        # the disk of the relay usually sits behind the USB 3 controller of the
        # Raspberry Pi 4, which is on PCIe and needs these to come up in initrd
        boot.initrd.availableKernelModules = [
          "pcie-brcmstb"
          "reset-raspberrypi"
          "xhci_pci"
          "usb_storage"
          "uas"
        ];

        hardware.firmware = [ pkgs.raspberrypiWirelessFirmware ];

        fileSystems."/boot".enable = false;
        fileSystems."/" = lib.mkForce {
          device = "/dev/disk/by-label/${rootLabel}";
          fsType = "ext4";
        };
        fileSystems."/firmware" = {
          device = "/dev/disk/by-label/FIRMWARE";
          fsType = "vfat";
        };

        swapDevices = lib.mkForce [ ];
        zramSwap.enable = true;

        boot.loader.grub.enable = lib.mkForce false;
        boot.loader.generic-extlinux-compatible.enable = true;

        environment.systemPackages = [
          pkgs.libraspberrypi
          pkgs.raspberrypi-eeprom
        ];
      };
  };
}
