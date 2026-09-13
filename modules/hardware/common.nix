{ inputs, lib, ... }:
let
  inherit (lib)
    elem
    length
    mkIf
    mkMerge
    optional
    optionalAttrs
    ;
in
{
  flake.modules.nixos.hardware =
    { config, host, hardware, ... }:
    let
      inherit (config.internal)
        system
        ;
      
      gpus = hardware.gpu or [ ];
      busId = hardware.busId or { };
      
      # two GPUs with one of them being nvidia: the machine can do prime offload
      hybrid = elem "nvidia" gpus && length gpus > 1;
      
      # prime needs the PCI address of both cards 
      # to find the id run: lspci -nn | grep -E 'VGA|3D
      prime = hybrid && busId ? nvidia && (busId ? intel || busId ? amd);
    in
    {
      imports = map (module: inputs.nixos-hardware.nixosModules.${module}) (hardware.modules or [ ]);

      config = mkMerge [
        (mkIf prime {
          hardware.nvidia.prime = {
            offload.enable = true;
            nvidiaBusId = busId.nvidia;
          }
          // optionalAttrs (busId ? amd) { amdgpuBusId = busId.amd; }
          // optionalAttrs (busId ? intel) { intelBusId = busId.intel; };
        })
        {
          warnings = optional (hybrid && !prime)
            "${host.name}: hybrid graphics but hardware.busId is missing or incomplete, prime offload disabled";
        
          hardware.graphics.enable = gpus != [ ];
          hardware.enableRedistributableFirmware = true;
          
          internal.system.amd.enable = elem "amd" gpus;
          internal.system.intel.enable = elem "intel" gpus;
          internal.system.nvidia.enable = elem "nvidia" gpus;

          # windows expects the RTC in local time
          time.hardwareClockInLocalTime = system.dualBoot.enable;
        }
      ];
    };
}
