{ inputs, config, lib, ... }:
let 
    inherit (config.flake.modules) nixos;
    inherit (lib) mkOption types optionals;
in
{
    flake.modules.nixos.hardware = { config, host, ... }:
    let
        inherit (config.profile) system;
        inherit (host) hardwareModel;
    in
    {
        imports = [
            nixos.amd
            nixos.intel
            nixos.nvidia
        ] ++ optionals (hardwareModel != null) [
            inputs.nixos-hardware.nixosModules.${hardwareModel}
        ];
        
        options = {
            profile.system = {
                dualBoot = mkOption {
                    type = types.bool;
                    default = false;
                    description = "Are you dual-booting NixOS";
                };  
                gpu = mkOption {
                    type = types.nullOr (types.enum [ "amd" "intel" "nvidia" ]);
                    default = null;
                    description = "Select your primary GPU manufacturer";
                };
            };
        };
        
        config = {
            internal.system.amd.enable = (system.gpu == "amd");
            internal.system.intel.enable = (system.gpu == "intel");
            internal.system.nvidia.enable = (system.gpu == "nvidia");
        
            hardware.graphics.enable = (system.gpu != null);
            time.hardwareClockInLocalTime = system.dualBoot;
        };
    };
}