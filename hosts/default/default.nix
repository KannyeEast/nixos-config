{ inputs, config, ... }:
let
    inherit ( config.flake.modules) nixos;
    inherit (import ./_host.nix) hostname system;
    host = import ./_host.nix;
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
    - VM's/Docker
    - Disko
    - Impermanence 
    - Stylix
    */
    
    # @TODO: Refactor modules to work with role system
} 