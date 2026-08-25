hostDir:
{
  lib,
  inputs,
  config,
  ...
}:
let
  inherit (config.flake.modules)
    nixos
    ;

  data = builtins.fromJSON (builtins.readFile (hostDir + "/host.json"));
in
{
  flake.nixosConfigurations.${data.host.name} = inputs.nixpkgs.lib.nixosSystem {
    inherit (data.host)
      system
      ;
    specialArgs = {
      inherit
        inputs
        ;
      inherit (data)
        flake
        host
        user
        hardware
        locale
        network
        ;
    };
    modules = [
      inputs.disko.nixosModules.disko
      (hostDir + "/hardware.nix")
      (hostDir + "/disko.nix")
    ]
    ++ lib.optional (builtins.pathExists (hostDir + "/storage.nix")) (hostDir + "/storage.nix")
    ++ map (role: nixos.${role}) data.host.roles;
  };
}
