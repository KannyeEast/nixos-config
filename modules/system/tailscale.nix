{
  flake.modules.nixos.tailscale =
    { config, ... }:
    {
      config = {
        sops.secrets.tailscale-authkey = { };
        
        environment.persistence."/persist".directories = [
          { directory = "/var/lib/tailscale"; mode = "0700"; }
        ];
        
        services.resolved.enable = true;
        services.tailscale = {
          enable = true;
          authKeyFile = config.sops.secrets.tailscale-authkey.path;
          openFirewall = true;
        };

        networking.firewall.interfaces.${config.services.tailscale.interfaceName}.allowedTCPPorts = [ 80 443 ];
      };
    };
}