{ lib, ... }:
let
    inherit (lib) mkEnableOption mkIf;
in
{
    flake.modules.nixos.debug = { config, ... }:
    let
        inherit (config.internal.system) debug;
    in
    {   
        options = {
            internal.system.debug.enable = mkEnableOption "Debug mode" // { internal = true; };
        };
    
        config = mkIf debug.enable {
            # nixos-rebuild build-vm-with-bootloader --flake .#default
            # nixos-rebuild build-vm --flake .#default
            # Test user for debugging
            users.users.nixosvmtest = {
                isNormalUser = true;
                initialPassword = "test";
                group = "nixosvmtest";
            };
            
            users.groups.nixosvmtest = { };
            
            virtualisation.vmVariantWithBootLoader = {
                virtualisation = {
                    memorySize = 8192;
                    cores = 4;
                    
                    services = {
                        xserver.drivers = [ "virtio" ];
                        qemuGuest.enable = true;
                        spice-vdagentd.enable = true;
                        spice-autorandr.enable = true;
                    };
                };
                environment.sessionVariables = {
                    LIBGL_ALWAYS_SOFTWARE = "1";
                    WLR_RENDERER = "pixman"; 
                    NIRI_DISABLE_HW_RENDER_CHECK = "1"; 
                };
            };
            
            virtualisation.vmVariant = {
                virtualisation = {
                    memorySize = 8192;
                    cores = 4;
                    
                    services = {
                        xserver.drivers = [ "virtio" ];
                        qemuGuest.enable = true;
                        spice-vdagentd.enable = true;
                        spice-autorandr.enable = true;
                    };
                };
                environment.sessionVariables = {
                    LIBGL_ALWAYS_SOFTWARE = "1";
                    WLR_RENDERER = "pixman"; 
                    NIRI_DISABLE_HW_RENDER_CHECK = "1"; 
                };
            };
        };
    };
}
