{ lib, ... }:
let
  inherit (lib)
    mkEnableOption
    mkIf
    ;
in
{
  flake.modules.nixos.hardware =
    { config, pkgs, ... }:
    let
      inherit (config.internal.system)
        intel
        ;
    in
    {
      options = {
        internal.system.intel.enable = mkEnableOption "Intel GPU support" // {
          internal = true;
        };
      };

      config = mkIf intel.enable {
        hardware.graphics.extraPackages = [
          # modern intel GPUs (Xe iGPU and ARC)
          pkgs.intel-media-driver # VA-API (iHD) userspace
          pkgs.vpl-gpu-rt # oneVPL (QSV) runtime
        ];

        environment.sessionVariables = {
          LIBVA_DRIVER_NAME = "iHD";
        };

        boot.kernelParams = [ "i915.enable_guc=3" ];
      };
    };
}
