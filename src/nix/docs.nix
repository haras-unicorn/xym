{ config, ... }:

{
  self.overlays.overlays.xym-docs = {
    flake = true;

    value = final: _prev: {
      docs = final.harasPackages.mkMdbook { src = ../..; };

      options-docs =
        (final.harasPackages.mkOptionsDocs {
          modules = [
            { _module.check = false; }
            config.flake.nixosModules.options
          ];
          specialArgs = {
            pkgs = final;
          };
          transformOptions =
            option:
            option
            // {
              visible = option.visible && builtins.head option.loc == "xym";
              declarations = [ ];
            };
        }).optionsCommonMark;
    };
  };
}
