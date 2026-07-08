{ config, ... }:
let
    inherit (config.flake.modules) nixos homeManager;
in
{
    flake.modules.nixos.dev = { ... }:
    {
        imports = [
            nixos.debug
            nixos.direnv
        ];
        
        config = { 
            home-manager.sharedModules = [

            ];
        };
    };
}