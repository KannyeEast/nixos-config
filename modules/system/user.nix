{ lib, ... }:
let
  inherit (lib)
    filter
    mapAttrsToList
    ;
in
{
  flake.modules.nixos.user =
    { config, user, ... }:
    let
      hosts = import ../../lib/listHosts.nix lib;

      knownUsers = filter (k: k != "") (mapAttrsToList (_: h: h.user.publicKey or "") hosts);
    in
    {
      config = {
        sops.secrets."user-password".neededForUsers = true;
        
        environment.persistence."/persist".directories = [
          {
            directory = "/home/${user.name}";
            user = user.name;
            group = "users";
            mode = "0700";
          }
        ];

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

          hashedPasswordFile = config.sops.secrets.user-password.path;
          openssh.authorizedKeys.keys = knownUsers;
        };

        security.sudo.extraConfig = "Defaults lecture=never";

        nix.settings.trusted-users = [
          "root"
          "@wheel"
        ];
      };
    };
}
