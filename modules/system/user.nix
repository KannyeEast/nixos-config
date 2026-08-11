{ lib, ... }:
{
  flake.modules.nixos.user =
    { config, host, ... }:
    let
      inherit (host) user;
      inherit (config) sops;

      hostsDir = ../../hosts;

      hostNames = lib.attrNames (
        lib.filterAttrs (n: t: t == "directory" && builtins.pathExists (hostsDir + "/${n}/host.json")) (
          builtins.readDir hostsDir
        )
      );

      allKeys = lib.concatMap (
        n: (builtins.fromJSON (builtins.readFile (hostsDir + "/${n}/host.json"))).user.sshKeys or [ ]
      ) hostNames;
    in
    {
      config = {
        sops.secrets."userPassword".neededForUsers = true;

        users.mutableUsers = false;

        # Create user profile
        users.users.${user.name} = {
          isNormalUser = true;
          uid = 1000;
          home = "/home/${user.name}";
          extraGroups = [
            "wheel" # sudo/root privileges
            "networkmanager" # network configuration
          ];

          hashedPasswordFile = sops.secrets.userPassword.path;
          openssh.authorizedKeys.keys = allKeys;
        };

        security.sudo.extraConfig = "Defaults lecture=never";

        nix.settings.trusted-users = [
          "root"
          "@wheel"
        ];
      };
    };
}
