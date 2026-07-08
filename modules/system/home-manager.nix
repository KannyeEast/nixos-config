{ inputs, ... }:
let
in
{
    flake.modules.nixos.homeManager = { config, host, ... }:
    let
        inherit (config.internal) system;
        inherit (host) username;
    in
    {
        imports = [
            inputs.home-manager.nixosModules.home-manager
        ];
        
        config = {
            home-manager = {
                useUserPackages = true;
                useGlobalPkgs = true;
                backupFileExtension = "backup";
                users.${username} = {
                    home = {
                        username = username;
                        homeDirectory = "/home/${username}";
                        
                        # Home-manager version  
                        stateVersion = system.version; 
                    };
                };
            };
        };
    };
}