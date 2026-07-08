{ inputs, config, ... }:
let
    inherit ( config.flake.modules) nixos;
    
    host = builtins.fromJSON (builtins.readFile ./host.json);
    inherit (host) hostname system;
in
{
    flake.nixosConfigurations.${hostname} = inputs.nixpkgs.lib.nixosSystem {
        inherit system;
        specialArgs = { inherit inputs host; };
        modules = [
            nixos."${hostname}Configuration"
            nixos."${hostname}Hardware"
        ];
    };
    
    /*
    Planned additions:
    - DevEnv
    - Docker (compose)
    - Disko
    - Impermanence 
    */
    
    # @TODO: This file should move to lib/ and be generic
} 