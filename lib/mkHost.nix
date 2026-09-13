# mkHost.nix
# builds nixosConfigurations.<name> from hosts/<name>/.
# 
# required in the host directory:
#   host.json, secrets.json, disko.nix, and hardware.nix
# optional:
#   storage.nix, and home/ on a desktop host for declarative dotfiles
# optional, directly under hosts/:
#   cluster.json
name:
{
  inputs,
  config,
  lib,
  ...
}:
let
  inherit (config.flake.modules)
    homeManager
    nixos
    ;
  
  inherit (lib)
    optional
    unique
    ;

  hostDir = ../hosts + "/${name}";
  
  # host.json; describes this machine;
  # addons = generic capabilities that only affect this host
  hostData = (import ./validHosts.nix).${name};
  
  # storage.nix; describes additional disks outside the main disko.nix configuration
  storageFile = hostDir + "/storage.nix";
  
  # cluster.json; describes the relationship of each host
  # addons = unique assignments that one host performs on behalf of the entire cluster; 
  clusterFile =
    if builtins.pathExists ../hosts/cluster.json then
      builtins.fromJSON (builtins.readFile ../hosts/cluster.json)
    else
      { };
      
  # combines this hosts class with unconditional imports (system/ + hardware/) and optional addons
  declaredRoles = unique (
     [ "system" "hardware" hostData.host.class ]
     ++ (hostData.host.addons or [ ])
     ++ (clusterFile.members.${name}.addons or [ ])
  );
  
  # validates if declared roles are defined as either nixos.<> or homeManager.<> modules
  unknownRoles = builtins.filter (role: !(nixos ? ${role} || homeManager ? ${role})) declaredRoles; 
  validRoles = 
    if unknownRoles == [ ] then
      declaredRoles
    else 
      throw "${name}: unknown role(s) ${builtins.concatStringsSep ", " unknownRoles}";
  
  # creates a map of all valid roles combined to be imported as modules 
  select = set: map (role: set.${role}) (builtins.filter (role: set ? ${role}) validRoles);
in
{
  flake.nixosConfigurations.${name} = inputs.nixpkgs.lib.nixosSystem {
    inherit (hostData.host)
      system
      ;
    specialArgs = {
      inherit
        inputs
        ;
      inherit (hostData)
        flake
        user
        hardware
        locale
        ;
      cluster = clusterFile; 
      host = hostData.host // { inherit name; }; # pass both the derived host name and host.json contents as specialArgs for the config to use
    };
    modules = [
      inputs.disko.nixosModules.disko
      (hostDir + "/hardware.nix")
      (hostDir + "/disko.nix")
      { home-manager.sharedModules = select homeManager; }
    ]
    ++ select nixos
    ++ optional (builtins.pathExists storageFile) storageFile;
  };
}
