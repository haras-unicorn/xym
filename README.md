# xym

<!-- ANCHOR: intro -->

xym writes generic NixOS images for machines that relay public VPN traffic.

You run one command, answer a few questions, and get a disk you can plug into
the device. The device then keeps its own DNS record up to date and relays VPN
traffic for anyone who connects to it.

```sh
nix run github:haras-unicorn/xym
```

An image holds only what a relay needs:

- chrony, because the VPN relies on cryptography and cryptography relies on an
  accurate clock.
- CoreDNS, because ddns-updater needs working name resolution.
- NetworkManager, to optionally join a Wi-Fi network.
- ddns-updater, configured with your own config.
- The VPN software. For now that is EasyTier.
- OpenSSH, so you can log in over the local network or the VPN and read the
  logs, and a few tools to find out what is wrong.
- Nix, so the device can be rebuilt or deployed to later.

The image is the same for everyone. Your ddns-updater config, your password and
your optional Wi-Fi profile are written into a copy of it, in user space, so you
never need root until the final write to the disk.

<!-- ANCHOR_END: intro -->

<!-- ANCHOR: usage -->

## Write an image

You need:

- Nix with flakes enabled.
- A ddns-updater `config.json`. See the
  [ddns-updater documentation](https://github.com/qdm12/ddns-updater) for the
  format.
- A disk to overwrite, such as an SD card in a reader.
- When your machine is not an ARM machine and you build an ARM image: binfmt
  emulation for it. On NixOS that is `boot.binfmt.emulatedSystems`.

Run the wizard. It asks for, and checks, one thing at a time:

1. The hardware and the VPN. Both must be supported by xym, and this machine
   must be able to build for that hardware.
2. Your ddns-updater config. xym runs ddns-updater with it for real and waits
   until every record is updated or found up to date. This needs the network,
   and it fails the run when it does not work.
3. An optional Wi-Fi network. xym tries to connect to it and tells you the
   result. A failure does not stop you, because you may be on another network
   than the device will be.
4. The password of the `xym` user on the device.
5. The disk. It must be a whole disk, not a partition, not read-only, not in
   use, and large enough for the image.
6. The image build. The first run takes long, later runs use the cache.
7. A double check before the write. You confirm, then type the name of the disk.

Only the final write needs root. When your user cannot write to the disk, xym
runs `dd` through `sudo`.

Every stage of the wizard is also a command, and the wizard only asks questions
and calls them. Add `--help` to any of them.

```sh
xym hardware list
xym hardware check rpi4
xym vpn list
xym password check "<password>"
xym device list
xym device check /dev/sdX
xym ddns check ./config.json
xym wifi check "<name>" "<password>"
xym image build rpi4 easytier
xym image prepare "<image>" rpi4 \
  --ddns-config ./config.json --password "<password>"
xym image write "<prepared image>" /dev/sdX
xym image clean "<prepared image>"
xym address check <address>
xym update <address> rpi4 easytier
```

To see the wizard without changing anything, preview it:

```sh
nix run github:haras-unicorn/xym#xym-fake
```

This runs the real wizard with fake disks, fake checks and a dry run, so nothing
is built, changed or written. The same behavior is available on the real program
through two environment variables:

- `XYM_FAKE` replaces everything xym asks the system, such as the disks, with
  fake data. It also skips every change, because fake disks are not real.
- `XYM_DRY_RUN` skips every change, and keeps the checks real.

Other variables:

- `XYM_IMAGE_DIR` is where the copy of the image is made and edited. It defaults
  to `xym` in your cache directory, because images are too big for a temporary
  directory.
- `XYM_FLAKE` is the flake the images come from. It defaults to the exact
  revision of xym you are running.

<!-- ANCHOR_END: usage -->

<!-- ANCHOR: guide -->

## Log in to the device

The device runs OpenSSH, and root cannot log in. There is one user, `xym`, with
the password you chose in the wizard. It can use `sudo`, and being in the
`wheel` group it can read the system journal without it.

```console
ssh xym@<address of the device>
journalctl --unit ddns-updater
journalctl --unit easytier-xym
easytier-cli peer
```

The device also has `dig`, `curl`, `tcpdump`, `mtr`, `htop`, `strace`, `lsof`
and `ethtool`, and core dumps are kept, so `coredumpctl` works.

SSH listens on every network interface. Do not forward its port from your router
unless you want the internet to try your password.

## Change the device later

The device keeps Nix, so you can update it to the xym you are running. Give xym
its address and the hardware and VPNs you wrote the image with. It checks them,
and that the device really is that hardware and was written by xym, before it
builds anything.

```sh
nix run github:haras-unicorn/xym -- update "<address>" "<hardware>" ..."<vpns>"
```

Your ddns-updater config, password and Wi-Fi profile stay on the device. The
update uses the default settings of the hardware and the VPNs, such as the
EasyTier port.

To change more, xym has three functions in its flake library, `makeSystem`,
`makeToplevel` and `makeImage`, under `lib.<system>`. They take the values of
the `xym.hardware` and `xym.vpns` options, and `modules` for the rest of the
device. Put the result of `makeSystem` under `nixosConfigurations` of your own
flake and deploy it as you like.

## Notes

The Wi-Fi test only runs when this machine has an idle Wi-Fi device. A test on a
device that is in use would drop your connection, so xym skips it and says so.

The Wi-Fi password is passed to `nmcli` as an argument, so other users on the
machine can see it for the few seconds the test takes.

<!-- ANCHOR_END: guide -->
