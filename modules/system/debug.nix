{ lib, ... }:
let
    inherit (lib) mkEnableOption mkIf;
in
{
    flake.modules.nixos.debugging = { config, pkgs, ... }:
    let
        inherit (config.internal.system) debugging;
    in
    {   
        options = {
            internal.system.debugging.enable = mkEnableOption "Debug mode" // { internal = true; };
        };
    
        config = mkIf debugging.enable {
            # nixos-rebuild build-vm-with-bootloader --flake .#default
            # nixos-rebuild build-vm --flake .#default
            # Test user for debugging
            users.users.nixosvmtest = {
                isNormalUser = true;
                initialPassword = "test";
                group = "nixosvmtest";
                extraGroups = [ "seat" ];
            };
            
            users.groups.nixosvmtest = { };
            
            environment.sessionVariables = {
                LIBGL_ALWAYS_SOFTWARE = "1";
                WLR_RENDERER = "pixman"; 
                NIRI_DISABLE_HW_RENDER_CHECK = "1"; 
            };
            
            virtualisation.vmVariantWithBootLoader = {
                virtualisation = {
                    memorySize = 8192;
                    cores = 4;
                };         
            };
            
            virtualisation.vmVariant = {
                virtualisation = {
                    memorySize = 8192;
                    cores = 4;
                };         
            };
            
            # virtualisation.qemu.drivers = {};
        };
    };
}
