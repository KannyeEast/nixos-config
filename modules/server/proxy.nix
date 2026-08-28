{
  flake.modules.nixos.proxy =
    { config, pkgs, user, network, ... }:
    {
      config = {
        sops.secrets.cloudflare-token = { };

        sops.templates."caddy.env" = {
          content = ''
            CLOUDFLARE_API_TOKEN=${config.sops.placeholder.cloudflare-token}
          '';
          restartUnits = [ "caddy.service" ];
        };
      
        environment.persistence."/persist".directories = [
          {
            directory = "/var/lib/caddy";
            user = "caddy";
            group = "caddy";
            mode = "0700";
          }
        ];
        
        services.caddy = {
          enable = true;
          email = user.email;
          environmentFile = config.sops.templates."caddy.env".path;
          
          package = pkgs.caddy.withPlugins {
            plugins = [ "github.com/caddy-dns/cloudflare@v0.2.1" ];
            hash = "sha256-F7d4HwM4oCkQrFMr4SFSC0r52ONxY+PW6z5BJawW8Ok";
          };
          
          virtualHosts."*.${network.domain}".extraConfig = ''
            tls {
              dns cloudflare {env.CLOUDFLARE_API_TOKEN}
              resolvers 1.1.1.1
            }
            abort
          '';
        };
      }; 
    };
}