{ lib, ... }:
let
  inherit (lib)
    mkEnableOption
    mkIf
    ;
in
{
  flake.modules.nixos.nvidia =
    { config, ... }:
    let
      inherit (config.internal.system)
        nvidia
        ;
    in
    {
      options = {
        internal.system.nvidia.enable = mkEnableOption "Nvidia" // {
          internal = true;
        };
      };

      config = mkIf nvidia.enable {
        hardware.nvidia = {
          open = true;
          nvidiaSettings = true;
          modesetting.enable = true;
        };

        environment.etc."nvidia/nvidia-application-profiles-rc.d/50-limit-vram-niri.json".text =
          builtins.toJSON
            {
              rules = [
                {
                  pattern = {
                    feature = "procname";
                    matches = "niri";
                  };
                  profile = "Limit Free Buffer Pool On Wayland Compositors";
                }
              ];
              profiles = [
                {
                  name = "Limit Free Buffer Pool On Wayland Compositors";
                  settings = [
                    {
                      key = "GLVidHeapReuseRatio";
                      value = 0;
                    }
                  ];
                }
              ];
            };
      };
    };
}
