{
  flake.modules.nixos.proxy =
    { config, pkgs, user, network, ... }:
    {
      config = {
        sops.secrets.cloudflare-token = { };

        sops.templates."cloudflare.env".content = ''
          CF_DNS_API_TOKEN=${config.sops.placeholder.cloudflare-token}
        '';
      
        environment.persistence."/persist".directories = [
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
            credentialsFile = config.sops.templates."cloudflare.env".path;
            group = config.services.caddy.group;
            reloadServices = [ "caddy.service" ];
          };
        };
        
        services.caddy = {
          enable = true;
          globalConfig = "auto_https disable_certs";
          virtualHosts."*.${network.domain}".extraConfig = ''
            tls /var/lib/acme/${network.domain}/fullchain.pem /var/lib/acme/${network.domain}/key.pem
            abort
          '';
        };
      }; 
    };
}