{ config, lib, ... }:
let
    inherit (lib) mkIf;
in
{
    flake.modules.homeManager.git = { config, ... }:
    let
        inherit (config.profile) user;
    in
    {
        options = {
            # Git settings
        };
    
        config = {
            programs.git = {
                enable = true;
                userName = "<name>";
                userEmail = "<email>";
                signing = {
                    key = "<key>";
                    signByDefault = true;
                };
            };
            
            # For now also GitHub
            programs.gh = {
                enable = true;
                gitCredentialHelper.enable = true;
            };
        };
    };
}