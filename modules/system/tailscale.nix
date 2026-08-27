{
  flake.modules.nixos.tailscale =
    { config, ... }:
    {
      config = {
        environment.persistence."/persist".directories = [
          { directory = "/var/lib/tailscale"; mode = "0700"; }
        ];
        
        services.tailscale.enable = true;
        services.resolved.enable = true;

        networking.firewall.allowedUDPPorts = [ config.services.tailscale.port ];
      };
    };
}