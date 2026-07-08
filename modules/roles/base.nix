{ config, ... }:
let
    inherit (config.flake.modules) nixos homeManager;
in
{
    flake.modules.nixos.base = { ... }:
    {
        imports = [
            nixos.boot
            nixos.homeManager
            nixos.locale
            nixos.system
            nixos.user
            # nixos.secrets
            nixos.hardware
        ];
        
        config = { 
            home-manager.sharedModules = [
                # homeManager.git
            ];
        };
    };
}