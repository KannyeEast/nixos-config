{ lib, ... }:
let
  inherit (lib)
    attrNames
    attrValues
    concatMap
    elem
    filter
    genAttrs
    mkIf
    optionalAttrs
    unique
    ;
in
{
  flake.modules.nixos.syncthing =
    {
      config,
      host,
      user,
      syncthing,
      ...
    }:
    let
      allHosts = attrNames syncthing;
      self = syncthing.${host.name} or { };
      sharedWith = self.to or { };

      # folders this host declares, plus folders other hosts declare toward it
      outgoing = concatMap (folderList: folderList) (attrValues sharedWith);
      incoming = concatMap (peerName: syncthing.${peerName}.to.${host.name} or [ ]) allHosts;
      folders = unique (outgoing ++ incoming);

      # every host that shares a given folder with this one, in either direction
      membersOf =
        folder:
        filter (
          peerName:
          elem folder (sharedWith.${peerName} or [ ])
          || elem folder (syncthing.${peerName}.to.${host.name} or [ ])
        ) allHosts;

      peers = unique (concatMap membersOf folders);
      root = "/home/${user.name}";
    in
    {
      config = mkIf (folders != [ ]) {
        internal.system.impermanence.directories = [
          {
            directory = "/var/lib/syncthing";
            user = user.name;
            group = config.users.users.${user.name}.group;
            mode = "0700";
          }
        ];

        services.syncthing = {
          enable = true;
          user = user.name;
          group = config.users.users.${user.name}.group;
          configDir = "/var/lib/syncthing";
          dataDir = root;

          openDefaultPorts = false;
          overrideDevices = true;
          overrideFolders = true;

          settings = {
            # Caddy proxies with a different host header
            gui.insecureSkipHostcheck = true;
            gui.address = "127.0.0.1:8384";

            options = {
              globalAnnounceEnabled = false;
              localAnnounceEnabled = false;
              relaysEnabled = false;
              natEnabled = false;
              urAccepted = -1;
            };

            devices = genAttrs peers (
              peerName:
              {
                id = syncthing.${peerName}.id;
              }
              // optionalAttrs (syncthing.${peerName} ? address) {
                addresses = [ syncthing.${peerName}.address ];
              }
            );

            folders = genAttrs folders (folder: {
              path = "${root}/${folder}";
              devices = membersOf folder;
              versioning = {
                type = "simple";
                params.keep = "10";
              };
            });
          };
        };

        networking.firewall.interfaces.${config.services.tailscale.interfaceName} = {
          allowedTCPPorts = [
            22000
          ];
          allowedUDPPorts = [
            22000
          ];
        };
      };
    };
}
