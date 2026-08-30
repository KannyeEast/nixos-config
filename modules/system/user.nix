{ lib, ... }:
let
  inherit (lib)
    elem
    filter
    filterAttrs
    mapAttrsToList
    ;
    
  hosts = import ../../lib/listHosts.nix lib;
in
{
  flake.modules.nixos.user =
    { config, host, user, ssh, ... }:
    let  
      inbound = filterAttrs (_: value: elem host.name (value.to or [ ])) ssh; 
      
      keys = filter (key: key != "") (
        mapAttrsToList (name: value: value.key or (hosts.${name}.user.publicKey or "")) inbound
      );
    in
    {
      config = {
        assertions = [
        {
          assertion = keys != [ ];
          message = "no ssh keys authorised for ${host.name}. Check fleet.json ssh.*.to";
        }
        ];
      
        sops.secrets."user-password".neededForUsers = true;

        internal.system.impermanence.directories = [
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
          openssh.authorizedKeys.keys = keys;
        };

        security.sudo.extraConfig = "Defaults lecture=never";

        nix.settings.trusted-users = [
          "root"
          "@wheel"
        ];
      };
    };
}
