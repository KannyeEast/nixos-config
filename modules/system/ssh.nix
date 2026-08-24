{ lib, ... }:
let
  inherit (lib)
    attrNames
    filterAttrs
    genAttrs
    listToAttrs
    mapAttrs
    nameValuePair
    concatMap
    optional
    ;

  forges = {
    "github.com" = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIOMqqnkVzrm0SdG6UOoqKLsabgH5C9okWi0dh2l9GKJl";
    "codeberg.org" = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIVIC02vnjFyL+I4RHfvIGNtOgJMe769VTF1VR4EB3ZB";
    "gitlab.com" = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIAfuCHKVTjquxvt6CM6tdG4SLp1Btn/nOeHHE5UOzRdf";
  };

  hostsDir = ../../hosts;

  hostNames = attrNames (
    filterAttrs (n: t: t == "directory" && builtins.pathExists (hostsDir + "/${n}/host.json")) (
      builtins.readDir hostsDir
    )
  );

  hosts = listToAttrs (
    concatMap (
      n:
      let
        key = (builtins.fromJSON (builtins.readFile (hostsDir + "/${n}/host.json"))).hostKey or "";
      in
      optional (key != "") (
        nameValuePair n {
          hostNames = [
            n
            "${n}.local"
          ];
          publicKey = key;
        }
      )
    ) hostNames
  );
in
{
  flake.modules.nixos.ssh =
    { ... }:
    {
      config = {
        services.openssh = {
          enable = true;
          openFirewall = true;

          hostKeys = [
            {
              path = "/persist/etc/ssh/ssh_host_ed25519_key";
              type = "ed25519";
            }
          ];
        };

        programs.ssh.knownHosts = mapAttrs (_: key: { publicKey = key; }) forges // hosts;
      };
    };

  flake.modules.homeManager.ssh =
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
