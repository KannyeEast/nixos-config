{ inputs, lib, ... }:
let
    inherit (lib) mkEnableOption mkIf;
in
{
    flake.modules.nixos.homeManager = { config, ... }:
    let
        inherit (config.internal.user) homeManager;
        inherit (config.internal) system;
        inherit (config.profile) user;
    in
    {
        imports = [
            inputs.home-manager.nixosModules.home-manager
        ];
        
        
        config = {
            # Create user profile for home-manager
            home-manager = {
                useUserPackages = true;
                useGlobalPkgs = true;
                backupFileExtension = "backup";
                users.${user.username} = {
                    imports = [ ../../home ];
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