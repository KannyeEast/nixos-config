{ inputs, ... }:
let
in
{
    flake.modules.nixos.homeManager = { config, ... }:
    let
        inherit (config.internal) system;
        inherit (config.profile) user;
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
                users.${user.username} = {
                    home = {
                        username = user.username;
                        homeDirectory = "/home/${user.username}";
                        
                        # Home-manager version  
                        stateVersion = system.version; 
                    };
                };
            };
        };
    };
}