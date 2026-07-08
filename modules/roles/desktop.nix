{ config, ... }:
let
    inherit (config.flake.modules) nixos homeManager;
in
{
    flake.modules.nixos.desktop = { ... }:
    {
        imports = [
            # System
            nixos.boot
            nixos.homeManager
            nixos.locale
            nixos.user
            # nixos.secrets
            
            # Hardware
            nixos.hardware
            
            # Desktop
            nixos.audio
            nixos.bluetooth
            nixos.desktopEnvironment
            nixos.desktopShell
            nixos.displayManager
            nixos.fonts
            nixos.packages
        ];
        
        config = { 
            home-manager.sharedModules = [
                # System
                # homeManger.git
                
                # Desktop
                homeManager.browser
                homeManager.dotfiles
            ];
        };
    };
}