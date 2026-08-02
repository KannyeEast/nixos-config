{
  inputs,
  config,
  lib,
  ...
}:
let
  inherit (config.flake.modules) nixos;
  inherit (lib) mkMerge mkIf elem;
in
{
  flake.modules.nixos.hardware =
    { config, host, ... }:
    let
      inherit (config.profile) system;
      inherit (host) hardware;
    in
    {
      imports = [
        nixos.amd
        nixos.intel
        nixos.nvidia
      ]
      ++ map (m: inputs.nixos-hardware.nixosModules.${m}) (hardware.modules or [ ]);

      config = mkMerge [
        (mkIf (elem "nvidia" hardware.gpu && elem "intel" hardware.gpu) {
          hardware.nvidia.prime = {
            offload.enable = true;
            nvidiaBusId = "PCI:1:0:0";
            intelBusId = "PCI:0:2:0";
          };
        })
        (mkIf (elem "nvidia" hardware.gpu && elem "amd" hardware.gpu) {
          hardware.nvidia.prime = {
            offload.enable = true;
            nvidiaBusId = "PCI:1:0:0";
            amdgpuBusId = "PCI:5:0:0";
          };
        })
        {
          internal.system.amd.enable = elem "amd" hardware.gpu;
          internal.system.intel.enable = elem "intel" hardware.gpu;
          internal.system.nvidia.enable = elem "nvidia" hardware.gpu;

          hardware.graphics.enable = hardware.gpu != [ ];
          time.hardwareClockInLocalTime = system.bootloader.refind.enable;
        }
      ];
    };
}
