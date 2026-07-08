{ config, ... }:
let
    inherit (config.flake.modules) nixos homeManager;
in
{
    flake.modules.nixos.server = { ... }:
    {
        imports = [
            nixos.base
            
        ];
        
        config = { 
            home-manager.sharedModules = [ ];
        };
    };
}