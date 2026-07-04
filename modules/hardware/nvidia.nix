{ lib, ... }:
let
    inherit (lib) mkEnableOption mkOption mkIf types;
in
{
    flake.modules.nixos.nvidia = { config, ... }:
    let
        inherit (config.profile.system) nvidia;
        iNvidia = config.internal.system.nvidia;    # Cannot inherit as nvidia is already present
    in
    {
        options = {
            internal.system.nvidia.enable = mkEnableOption "Nvidia stack" // { internal = true; };
            profile.system.nvidia = {
                powerManagement = mkOption {
                    type = types.bool;
                    default = false;
                    description = "Set to true for Turing (RTX 20-series) and newer GPUs";
                };
                finegrained = mkOption {
                    type = types.bool;
                    default = false;
                    description = "Fully disables the GPU when not in use";
                };
                dynamicBoost = mkOption {
                    type = types.bool;
                    default = false;
                    description = "Set to true for laptops with iGPU and a NVIDIA dGPU";
                };
            };
        };
        
        config = mkIf iNvidia.enable {
            # hardware.nvidia.prime >> Doesnt work on wayland so no need to configure that
            # https://discourse.nixos.org/t/why-nixos-using-dgpu-instead-of-igpu/73973
            hardware.nvidia = {
             # Open-Source drivers
             open = true;
             
             powerManagement = {
                 # Nvidia power management. Experimental, and can cause sleep/suspend to fail.
                 enable = nvidia.powerManagement;
                 # Fine-grained power management. Turns off GPU when not in use.
                 finegrained = nvidia.finegrained;
             };
             
             # Enable the Nvidia settings menu,
             # accessible via `nvidia-settings`.
             nvidiaSettings = true;
            
             dynamicBoost.enable = nvidia.dynamicBoost;
            };
        };
    };
}