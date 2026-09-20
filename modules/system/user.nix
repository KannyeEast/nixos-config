{ lib, ... }:
let
  inherit (lib)
    elem
    filter
    filterAttrs
    mapAttrsToList
    optional
    unique
    ;
in
{
  flake.modules.nixos.system =
    {
      config,
      host,
      user,
      cluster,
      ...
    }:
    let
      hosts = import ../../lib/validHosts.nix;
      home = "/home/${user.name}";
      
      # members naming this host in their ssh.to; cluster decides who can reach who
      inbound = filterAttrs (_: member: elem host.name (member.ssh.to or [ ])) (cluster.members or { });

      # the members own key or the user key from host.json if the member doesnt provide one
      keys = unique (
        filter (key: key != "") (
          mapAttrsToList (name: member: member.ssh.key or (hosts.${name}.user.publicKey or "")) inbound
        )
      );
    in
    {
      config = {
        # a server requires an outside connection
        assertions = optional (host.class == "server") {
          assertion = keys != [ ];
          message = "${host.name}: no ssh keys authorised. Check members.*.ssh.to in cluster.json";
        };

        # decrypt user password early to be available at login; password will be in the nix/store so it needs to be hashed
        sops.secrets."user-password".neededForUsers = true;

        internal.system.impermanence.directories = [
          {
            directory = home;
            user = user.name;
            group = "users";
            mode = "0700";
          }
        ];

        users.mutableUsers = false;
        users.users.${user.name} = {
          isNormalUser = true;
          uid = 1000;
          inherit home;

          extraGroups = [
            "wheel" # sudo/root privileges
            "networkmanager" # network configuration
          ];

          hashedPasswordFile = config.sops.secrets.user-password.path;
          openssh.authorizedKeys.keys = keys;
        };

        security.sudo.extraConfig = "Defaults lecture=never";

        # @wheel is the user; root stays trusted for recovery
        nix.settings.trusted-users = [
          "root"
          "@wheel"
        ];
      };
    };
}
