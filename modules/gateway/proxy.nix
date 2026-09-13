{ lib, ... }:
let
  inherit (lib)
    filterAttrs
    mapAttrs'
    nameValuePair
    optionalString
    ;
in
{
  flake.modules.nixos.gateway =
    {
      config,
      user,
      cluster,
      ...
    }:
    let
      domain = cluster.domain or (throw "gateway: cluster.json defines no domain");

      routed = filterAttrs (_: service: service.route != null) config.internal.services;

      # some services offer their own authentication; can also be left open deliberately for public access
      guarded = service: !service.route.hasAuth && service.route.access != "open";

      # auto_https disable_certs stops caddy picking a certificate; exact matches have to name the
      # acme files itself or it serves nothing at all
      tls = "tls /var/lib/acme/${domain}/fullchain.pem /var/lib/acme/${domain}/key.pem";
    in
    {
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
          certs.${domain} = {
            inherit domain;
            extraDomainNames = [ "*.${domain}" ];
            dnsProvider = "cloudflare";
            dnsResolver = "1.1.1.1:53";
            environmentFile = config.sops.templates."cloudflare.env".path;
            group = config.services.caddy.group;
            reloadServices = [ "caddy.service" ];
          };
        };

        services.caddy = {
          enable = true;

          # certifications come from acme, and not from caddy
          globalConfig = "auto_https disable_certs";

          virtualHosts = {
            "*.${domain}".extraConfig = ''
              ${tls}
              abort
            '';
          }
          // mapAttrs' (
            _: service:
            nameValuePair "${service.route.subdomain}.${domain}" {
              extraConfig = ''
                ${tls}
                ${optionalString (guarded service) ''
                  forward_auth 127.0.0.1:9091 {
                    uri /api/authz/forward-auth
                    copy_headers Remote-User Remote-Groups Remote-Name Remote-Email
                  }
                ''}
                reverse_proxy ${service.route.address}:${toString service.route.port}
                ${service.route.extraConfig}
              '';
            }
          ) routed;
        };

        networking.firewall.interfaces.${config.services.tailscale.interfaceName}.allowedTCPPorts = [
          80
          443
        ];
      };
    };
}
