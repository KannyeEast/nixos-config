{ config, lib, ... }:
let
    inherit (config.flake.modules) homeManager;
    inherit (lib) mkIf;
in
{
    flake.modules.homeManager.git = { config, ... }:
    let
        inherit (config.internal.user) homeManager;
    in
    {
        config = mkIf homeManager.enable {
        
        };
    };
}