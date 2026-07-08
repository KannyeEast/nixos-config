{ lib, ... }:
let
    inherit (lib) mkEnableOption mkIf lists;
in
{
    flake.modules.nixos.nvidia = { config, host, ... }:
    let
        inherit (config.internal.system) nvidia;
        inherit (host) hardware;
        
        listArchitecture = [ "fermi" "kepler" "maxwell" "pascal" "volta" "turing" "ampere" "ada-lovelace" "blackwell" ];
        indexArchitecture = a: lists.findFirstIndex (x: x == a) (-1) listArchitecture;
        checkArchitecture = generation: indexArchitecture (hardware.gpuArchitecture or null) >= indexArchitecture generation;
        
        hybridLaptop = hardware.platform == "laptop" && builtins.length hardware.gpu > 1;
    in
    {
        options = {
            internal.system.nvidia.enable = mkEnableOption "Nvidia" // { internal = true; };
        };
        
        config = mkIf nvidia.enable {
            hardware.nvidia = {
             open = true;
             powerManagement.enable = checkArchitecture "turing";
             powerManagement.finegrained = false;
             nvidiaSettings = true;
            
             dynamicBoost.enable = hybridLaptop && checkArchitecture "ampere";
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