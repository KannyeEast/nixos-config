{
  flake.modules.nixos.proxy =
    { config, network, ... }:
    {
      config = {
        environment.persistence."/persist".directories = [
          {
            directory = "/var/lib/caddy";
            user = "caddy";
            group = "caddy";
            mode = "0700";
          }
        ];
        
        services.caddy.enable = true;

        # lets caddy pull *.ts.net certs straight from tailscaled
        services.tailscale.permitCertUid = "caddy";
        systemd.services.caddy.after = [ "tailscaled.service" ];

        # only reachable over the tailnet, not from the LAN
        networking.firewall.interfaces.${config.services.tailscale.interfaceName}
          .allowedTCPPorts = [ 443 ];

        services.caddy.virtualHosts.${network.domain}.extraConfig = ''
          tls {
            get_certificate tailscale
          }
        '';
      }; 
    };
}