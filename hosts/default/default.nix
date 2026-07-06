{ inputs, config, ... }:
let
    inherit ( config.flake.modules) nixos;
    
    host = import ./_host.nix;
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