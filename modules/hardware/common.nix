{ inputs, config, lib, ... }:
let 
    inherit (config.flake.modules) nixos;
    inherit (lib) elem;
in
{
    flake.modules.nixos.hardware = { config, host, ... }:
    let
        inherit (config.profile) system;
        inherit (host) hardware;
    in
    {
        imports = [
            nixos.amd
            nixos.intel
            nixos.nvidia
        ] ++ map (m:
            inputs.nixos-hardware.nixosModules.${m}
        ) (hardware.modules or [ ]);
        
        config = {
            internal.system.amd.enable = elem "amd" hardware.gpu;
            internal.system.intel.enable = elem "intel" hardware.gpu;
            internal.system.nvidia.enable = elem "nvidia" hardware.gpu;
        
            hardware.graphics.enable = hardware.gpu != [ ];
            time.hardwareClockInLocalTime = system.bootloader.dualBoot;
        };
    };
}