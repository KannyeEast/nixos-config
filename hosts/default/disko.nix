{ inputs, ... }:
let
    inherit (builtins.fromJSON (builtins.readFile ./host.json)) hostname;
in
{
    flake.modules.nixos."${hostname}Disko" = {}:
    {
        imports = [
            inputs.disko.nixosModules.disko
        ];
    };
}