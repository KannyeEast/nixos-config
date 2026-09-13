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
  flake.modules.nixos.system =
    {
      config,
      host,
      user,
      cluster,
      ...
    }:
    let
      home = config.users.users.${user.name}.home;
      group = config.users.users.${user.name}.group;
      
      members = cluster.members or { };
      all = attrNames members;
      
      self = members.${host.name}.syncthing or { };
      sharedWith = self.to or { };

      # folders this host offers, plus folders others offer to it
      outgoing = concatMap (folderList: folderList) (attrValues sharedWith);
      incoming = concatMap (peer: members.${peer}.syncthing.to.${host.name} or [ ]) all;
      folders = unique (outgoing ++ incoming);

      # every host that shares a given folder with this one, in either direction
      sharedBy =
        folder:
        filter (
          peer:
          elem folder (sharedWith.${peer} or [ ])
          || elem folder (members.${peer}.syncthing.to.${host.name} or [ ])
        ) all;

      peers = unique (concatMap sharedBy folders);
    in
    {
      config = mkIf (folders != [ ]) (
        {
        internal.system.impermanence.directories = [
          {
            directory = "/var/lib/syncthing";
            user = user.name;
            inherit group;
            mode = "0700";
          }
        ];

        services.syncthing = {
          enable = true;
          user = user.name;
          inherit group;
          configDir = "/var/lib/syncthing";
          dataDir = home;

          openDefaultPorts = false;
          overrideDevices = true;
          overrideFolders = true;

          settings = {
            # caddy proxies with a different host header
            gui.insecureSkipHostcheck = true;
            gui.address = "127.0.0.1:8384";

            # locked behind tailnet; discoverability and relays are turned off
            options = {
              globalAnnounceEnabled = false;
              localAnnounceEnabled = false;
              relaysEnabled = false;
              natEnabled = false;
              urAccepted = -1;
            };

            devices = genAttrs peers (
              peer:
              { id = members.${peer}.syncthing.id; }
              // optionalAttrs (members.${peer}.syncthing ? address) {
                addresses = [ members.${peer}.syncthing.address ];
              }
            );

            folders = genAttrs folders (folder: {
              path = "${home}/${folder}";
              devices = sharedBy folder;
              versioning = {
                type = "simple";
                params.keep = "10";
              };
            });
          };
        };

        networking.firewall.interfaces.${config.services.tailscale.interfaceName} = {
          allowedTCPPorts = [ 22000 ];
          allowedUDPPorts = [ 22000 ];
        };
        
        }
        // optionalAttrs (host.class == "server") {
          internal.services.sync = {
            route.port = 8384;
            notify = [ "syncthing.service" ];
          };
        }
      );
    };
}
