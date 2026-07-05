{ ... }:
let
    inherit (import ./_host.nix) hostname;
in
{
    flake.modules.nixos."${hostname}Hardware" = { config, lib, pkgs, modulesPath, ... }:
    {
        imports = [
            (modulesPath + "/installer/scan/not-detected.nix")
        ];
        
        boot.initrd.availableKernelModules = [ "xhci_pci" "thunderbolt" "vmd" "nvme" "usbhid" "usb_storage" "sd_mod" "rtsx_pci_sdmmc" ];
        boot.initrd.kernelModules = [ ];
        boot.kernelModules = [ "kvm-intel" ];
        boot.extraModulePackages = [ ];
        
        fileSystems."/" = {
            device = "/dev/disk/by-uuid/d4da0e1b-662c-47b5-9ea9-52790921b02e";
            fsType = "ext4";
        };
        
        fileSystems."/boot" = {
            device = "/dev/disk/by-uuid/71D6-F436";
            fsType = "vfat";
            options = [ "fmask=0077" "dmask=0077" ];
        };
        
        swapDevices = [
            { device = "/dev/disk/by-uuid/88b93704-d8bd-41e4-8e4a-5f22f20ae077"; }
        ];
        
        nixpkgs.hostPlatform = lib.mkDefault "x86_64-linux";
        hardware.cpu.intel.updateMicrocode = lib.mkDefault config.hardware.enableRedistributableFirmware;
    }; 
}
