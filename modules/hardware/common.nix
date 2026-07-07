{ inputs, config, lib, ... }:
let 
    inherit (config.flake.modules) nixos;
    inherit (lib) mkOption types elem optionals;
in
{
    flake.modules.nixos.hardware = { config, host, ... }:
    let
        inherit (config.profile) system;
        hardwareModel = host.hardwareModel or null;
    in
    {
        imports = [
            nixos.amd
            nixos.intel
            nixos.nvidia
        ] ++ optionals (hardwareModel != null) [s
            # @TODO: This probably has the same infinite recursion but need to test
            inputs.nixos-hardware.nixosModules.${hardwareModel}
        ];
        
        options = {
            profile.system = {
                dualBoot = mkOption {
                    type = types.bool;
                    default = false;
                    description = "Are you dual-booting NixOS";
                };  
                hardware = mkOption {
                    type = types.listOf (types.enum [ "amd" "intel" "nvidia" ]);
                    default = [ ];
                    description = "Select your hardware manufacturer(s)";
                };
            };
        };
        
        config = {
            internal.system.amd.enable = elem "amd" system.hardware;
            internal.system.intel.enable = elem "intel" system.hardware;
            internal.system.nvidia.enable = elem "nvidia" system.hardware;
        
            hardware.graphics.enable = system.hardware != [ ];
            time.hardwareClockInLocalTime = system.dualBoot;
        };
    };
}