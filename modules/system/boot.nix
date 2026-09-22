{ lib, ... }:
let
  inherit (lib)
    mkEnableOption
    ;
in
{
  flake.modules.nixos.system = {
    options = {
      internal.system = {
        dualBoot.enable = mkEnableOption "dual-booting" // {
          internal = true;
        };
      };
    };

    config = {
      boot.loader.efi.canTouchEfiVariables = true;
    };
  };
}
