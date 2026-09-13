{ lib, ... }:
let
  inherit (lib)
    filterAttrs
    genAttrs
    mapAttrs
    optionalAttrs
    ;
    
  # treat forges as known ssh connections so it doesnt prompt on a fresh install 
  forges = {
    "github.com" = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIOMqqnkVzrm0SdG6UOoqKLsabgH5C9okWi0dh2l9GKJl";
    "codeberg.org" = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIVIC02vnjFyL+I4RHfvIGNtOgJMe769VTF1VR4EB3ZB";
    "gitlab.com" = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIAfuCHKVTjquxvt6CM6tdG4SLp1Btn/nOeHHE5UOzRdf";
  };
in
{
  flake.modules.nixos.system = 
  { config, host, ... }:
  let
    hosts = import ../../lib/validHosts.nix;
    root = config.internal.system.impermanence.root;
    
    # every host in the config with a public host key; machines trust each other by default
    knownHosts = mapAttrs (name: data: {
      hostNames = [
        name
        "${name}.local"
      ];
      inherit (data.host) publicKey;
    }) (filterAttrs (_: data: (data.host.publicKey or "") != "") hosts);
  in
  {
    config = {
      services.openssh = {
        enable = true;
        openFirewall = true;
        
        settings = {
          PasswordAuthentication = true;
          KbdInteractiveAuthentication = true;
        };

        hostKeys = [
          {
            path = "${root}/etc/ssh/ssh_host_ed25519_key";
            type = "ed25519";
          }
        ];
      };

      programs.ssh.knownHosts = (mapAttrs (_: key: { publicKey = key; }) forges) // knownHosts;
    }
    // optionalAttrs (host.class == "server") {
      internal.services.ssh.backup.paths = [ "${root}/etc/ssh" ];
    };
  };

  flake.modules.homeManager.system =
    { config, ... }:
    {
      config = {
        programs.ssh = {
          enable = true;
          enableDefaultConfig = false;

          settings = genAttrs (builtins.attrNames forges) (_: {
            IdentityFile = [ "${config.home.homeDirectory}/.ssh/id_ed25519" ];
            IdentitiesOnly = true;
          });
        };
      };
    };
}
