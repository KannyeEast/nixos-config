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
      inputs.disko.nixosModules.disko
      (hostDir + "/hardware.nix")
      (hostDir + "/disko.nix")
    ]
    ++ map (role: nixos.${role}) host.roles;
  };
}
