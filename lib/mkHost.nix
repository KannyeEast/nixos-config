hostDir:
    { inputs, config, ... }:
    let
        inherit (config.flake.modules) nixos;
    
        host = builtins.fromJSON (builtins.readFile (hostDir + "/host.json"));
        inherit (host) hostname system;
    in
    {
        flake.nixosConfigurations.${hostname} = inputs.nixpkgs.lib.nixosSystem {
            inherit system;
            specialArgs = { inherit inputs host; };
            modules = [
                nixos."${hostname}Configuration"
                nixos."${hostname}Hardware"
                #nixos."${hostname}Disko"
            ] ++ map (role: nixos.${role}) host.roles;
    
            # Planned additions: DevEnv, Docker (compose), Disko, Impermanence
        };
    }
