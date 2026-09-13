{ lib, ... }:
let
  inherit (lib)
    literalExpression
    mapAttrsToList 
    mkOption
    types
    ;
in
{
  flake.modules.nixos.server =
    { config, ...}:
    {
      options = {
        internal.services = mkOption {
          default = { };
    
          description = ''
            What a service offers the rest of this host. Declared by the `server` class,
            because a descriptor describes serving and only a server serves.
    
            A producer sets its slice unconditionally and never asks who is listening.
            A module that also runs on a desktop must emit this under
            `optionalAttrs (host.class == "server")` — `mkIf` will not do, because the
            option does not exist there at all.
          '';
    
          example = literalExpression ''
            {
              jellyfin = {
                route = { port = 8096; expose = "relay"; hasAuth = true; };
                metrics.port = 8096;
                volumes = [ "media" ];
                backup.paths = [ "/var/lib/jellyfin" ];
                notify = [ "jellyfin.service" ];
              };
            }
          '';
    
          type = types.attrsOf (
            types.submodule (
              { name, ... }:
              {
                options = {
                  route = mkOption {
                    default = null;
                    description = "Read by the proxy";
                    type = types.nullOr (
                      types.submodule {
                        options = {
                          port = mkOption {
                            type = types.port;
                          };
                          address = mkOption {
                            type = types.str;
                            default = "127.0.0.1";
                          };
                          subdomain = mkOption {
                            type = types.str;
                            default = name;
                          };
                          expose = mkOption {
                            type = types.enum [ "private" "tunnel" "relay" ];
                            default = "private";
                            description = "How this service should be exposed";
                          };
                          access = mkOption {
                            type = types.enum [ "open" "1fa" "2fa" "blocked" ];
                            default = "1fa";
                            description = "Mapped to the auth provider's vocabulary by auth.nix.";
                          };
                          hasAuth = mkOption {
                            type = types.bool;
                            default = false;
                            description = "Service has its own authentication";
                          };
                          groups = mkOption {
                            type = types.listOf types.str;
                            default = [ "admin" ];
                          };
    
                          extraConfig = mkOption {
                            type = types.lines;
                            default = "";
                          };
                        };
                      }
                    );
                  };
    
                  metrics = mkOption {
                    default = null;
                    description = "Read by the observer";
                    type = types.nullOr (
                      types.submodule {
                        options = {
                          port = mkOption {
                            type = types.port;
                          };
                          path = mkOption {
                            type = types.str;
                            default = "/metrics";
                          };
                          interval = mkOption {
                            type = types.str;
                            default = "30s";
                          };
                        };
                      }
                    );
                  };
  
                  volumes = mkOption {
                    type = types.listOf types.str;
                    default = [ ];
                    description = ''
                      Volume names this service needs, asserted against what the fleets define.
                      Per service rather than per host, so the error names the service.
                    '';
                  };
    
                  backup = {
                    paths = mkOption {
                      type = types.listOf types.str;
                      default = [ ];
                      description = "Paths included in the backup. Empty means this service is not backed up";
                    };
                    exclude = mkOption {
                      type = types.listOf types.str;
                      default = [ ];
                      description = "Subpaths excluded from included paths; cache, thumbnails, etc.";
                    };
                  };
    
                  notify = mkOption {
                    type = types.listOf types.str;
                    default = [ ];
                    description = "Units that should send a notification on failure";
                  };
    
                };
              }
            )
          );
        };
      };
      
      config = {
        assertions = mapAttrsToList (name: service: {
          assertion =
            service.route == null
            || !(service.route.expose != "private" && service.route.access == "open" && !service.route.hasAuth);
          message = "internal.services.${name} is exposed with no authentication";
        }) config.internal.services;
      };
    };
}