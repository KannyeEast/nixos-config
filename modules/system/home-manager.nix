{ inputs, ... }:
{
    flake.modules.nixos.homeManager = { config, host, ... }:
    let
        inherit (config.internal) system;
        inherit (host) user;
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
                extraSpecialArgs = { inherit inputs host; };
                users.${user.name} = {
                    home = {
                        username = user.name;
                        homeDirectory = "/home/${user.name}";
                        
                        # Home-manager version  
                        stateVersion = system.version; 
                    };
                };
            };
        };
    };
}