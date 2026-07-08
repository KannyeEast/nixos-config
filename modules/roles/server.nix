{ config, ... }:
let
    inherit (config.flake.modules) nixos homeManager;
in
{
    flake.modules.nixos.server = { ... }:
    {
        imports = [
            # System
            nixos.boot
            nixos.homeManager
            nixos.locale
            nixos.user
            # nixos.secrets
            
            # Hardware (Does a server need this?)
            nixos.hardware
            
            # Server
        ];
        
        config = { 
            home-manager.sharedModules = [
                # System
                # homeManager.git
                
                # Server
            ];
        };
    };
}