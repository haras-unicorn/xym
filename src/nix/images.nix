{
  config,
  inputs,
  lib,
  selfLib,
  ...
}:
let
  # container tests own the host name and make nixpkgs.config read-only, so
  # this lives here and not in the image modules
  imageModule =
    { config, ... }:
    {
      networking.hostName = "xym";

      nixpkgs.config.allowUnfreePredicate =
        package: builtins.elem (lib.getName package) config.xym.internal.unfreePackages;
    };

  hardwareName = hardware: builtins.head (builtins.attrNames hardware);

  # takes the values of the xym.hardware and xym.vpns options, and more modules
  # for whatever else of the device the caller wants to configure
  makeSystem =
    {
      hardware,
      vpns,
      modules ? [ ],
    }:
    let
      entry = selfLib.hardware.${hardwareName hardware};
    in
    inputs.nixpkgs.lib.nixosSystem {
      inherit (entry) system;
      modules = [
        config.flake.nixosModules.default
      ]
      ++ entry.image.modules
      ++ [
        imageModule
        { xym = { inherit hardware vpns; }; }
      ]
      ++ modules;
    };

  makeToplevel = arguments: (makeSystem arguments).config.system.build.toplevel;

  makeImage =
    arguments:
    selfLib.hardware.${hardwareName arguments.hardware}.image.output (
      makeSystem arguments
    );

  rpi4Easytier = {
    hardware.rpi4 = { };
    vpns = [ { easytier = { }; } ];
  };
in
{
  self.overlays.overlays.images = {
    flake = true;
    value = _final: _prev: { inherit makeSystem makeToplevel makeImage; };
  };

  # the system is the one that builds, and the hardware decides what is built
  self.lib = lib.genAttrs config.systems (
    system:
    let
      namespace = selfLib.overlays.namespace;
      pkgs = selfLib.pkgs.makePkgs { inherit system; };
    in
    {
      makeSystem = arguments: pkgs.${namespace}.makeSystem arguments;
      makeToplevel = arguments: pkgs.${namespace}.makeToplevel arguments;
      makeImage = arguments: pkgs.${namespace}.makeImage arguments;
    }
  );

  self.unitTests.images = {
    test-rpi4-easytier-evaluates = {
      expr = builtins.isString (makeImage rpi4Easytier).drvPath;
      expected = true;
    };

    test-rpi4-uses-the-mainline-kernel = {
      expr = builtins.match ".*rpi.*" (makeSystem rpi4Easytier)
      .config.boot.kernelPackages.kernel.name;
      expected = null;
    };

    test-the-system-can-rebuild-itself = {
      expr =
        let
          nixos = makeSystem rpi4Easytier;
        in
        nixos.config.nix.enable && !nixos.config.system.disableInstallerTools;
      expected = true;
    };

    test-the-library-makes-images = {
      expr =
        let
          system = builtins.head config.systems;
        in
        builtins.isString (config.flake.lib.${system}.makeImage rpi4Easytier).drvPath;
      expected = true;
    };

    test-the-library-makes-systems = {
      expr =
        let
          system = builtins.head config.systems;
        in
        builtins.isString
          (config.flake.lib.${system}.makeToplevel rpi4Easytier).drvPath;
      expected = true;
    };

    test-every-hardware-describes-its-image = {
      expr = builtins.all (
        hardware:
        hardware ? system
        && hardware ? rootLabel
        && hardware ? image.modules
        && hardware ? image.output
      ) (builtins.attrValues selfLib.hardware);
      expected = true;
    };
  };
}
