{ lib, ... }:
let
    inherit (lib) mkEnableOption mkIf lists;
in
{
    flake.modules.nixos.nvidia = { config, host, ... }:
    let
        inherit (config.internal.system) nvidia;
        inherit (host) hardware;
    in
    {
        options = {
            internal.system.nvidia.enable = mkEnableOption "Nvidia" // { internal = true; };
        };
        
        config = mkIf nvidia.enable {
            hardware.nvidia = {
                open = true;
                nvidiaSettings = true;
                modesetting.enable = true;
            };
            
            environment.etc."nvidia/nvidia-application-profiles-rc.d/50-limit-vram-niri.json".text = builtins.toJSON {
                rules = [{
                    pattern = { feature = "procname"; matches = "niri"; };
                    profile = "Limit Free Buffer Pool On Wayland Compositors";
                }];
                profiles = [{
                    name = "Limit Free Buffer Pool On Wayland Compositors";
                    settings = [{ key = "GLVidHeapReuseRatio"; value = 0; }];
                }];
            };
        };
    };
}