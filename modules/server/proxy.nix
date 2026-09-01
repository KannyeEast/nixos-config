{ lib, ... }:
let
  inherit (lib)
    mapAttrs'
    nameValuePair
    mkOption
    optionalString
    types
    ;
in
{
  flake.modules.nixos.proxy =
    {
      config,
      user,
      network,
      ...
    }:
    {
      options = {
        internal.server.proxy.services = mkOption {
          type = types.attrsOf (types.submodule ({ name, ... }: {
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
              policy = mkOption {  
                type = types.enum [ "bypass" "one_factor" "two_factor" "deny" ];
                default = "two_factor";
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
          }));
          default = { };
          internal = true;
          description = "Reverse proxy configuration and how it should be authorized and forwarded";
        };
      };
      
      config = {
        sops.secrets.cloudflare-token = { };

        sops.templates."cloudflare.env".content = ''
          CF_DNS_API_TOKEN=${config.sops.placeholder.cloudflare-token}
        '';

        internal.system.impermanence.directories = [
          {
            directory = "/var/lib/caddy";
            user = "caddy";
            group = "caddy";
            mode = "0700";
          }
          "/var/lib/acme"
        ];

        security.acme = {
          acceptTerms = true;
          defaults.email = user.email;
          certs.${network.domain} = {
            domain = network.domain;
            extraDomainNames = [ "*.${network.domain}" ];
            dnsProvider = "cloudflare";
            dnsResolver = "1.1.1.1:53";
            environmentFile = config.sops.templates."cloudflare.env".path;
            group = config.services.caddy.group;
            reloadServices = [ "caddy.service" ];
          };
        };

        services.caddy = {
          enable = true;
          globalConfig = "auto_https disable_certs";
          virtualHosts = {
            "*.${network.domain}".extraConfig = ''
              tls /var/lib/acme/${network.domain}/fullchain.pem /var/lib/acme/${network.domain}/key.pem
              abort
            '';
          }
          // mapAttrs' (
            name: service:
            nameValuePair "${service.subdomain}.${network.domain}" {
              extraConfig = ''
                ${optionalString (service.policy != "bypass") ''
                  forward_auth 127.0.0.1:9091 {
                    uri /api/authz/forward-auth
                    copy_headers Remote-User Remote-Groups Remote-Name Remote-Email
                  }
                ''}
                reverse_proxy ${service.address}:${toString service.port}
                ${service.extraConfig}
              '';
            }
          ) config.internal.server.proxy.services;
        };

        networking.firewall.interfaces.${config.services.tailscale.interfaceName}.allowedTCPPorts = [
          80
          443
        ];
      };
    };
}
