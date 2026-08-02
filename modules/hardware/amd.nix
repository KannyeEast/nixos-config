{ lib, ... }:
let
  inherit (lib) mkEnableOption mkIf;
in
{
  flake.modules.nixos.amd =
    { config, pkgs, ... }:
    let
      inherit (config.internal.system) amd;
    in
    {
      options = {
        internal.system.amd.enable = mkEnableOption "Amd" // {
          internal = true;
        };
      };

      config = mkIf amd.enable {
        hardware.graphics.enable32Bit = true;
        # These might not be supported on all (older) iGPUs
        # ROCm/HIP >> drop if you don't do GPU compute
        systemd.tmpfiles.rules = [ "L+    /opt/rocm   -    -    -     -    ${pkgs.rocmPackages.clr}" ];
      };
    };
}
