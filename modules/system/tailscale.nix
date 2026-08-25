{
  flake.modules.nixos.tailscale =
    { config, ... }:
    {
      config = {
        services.tailscale.enable = true;

        networking.firewall = {
          trustedInterfaces = [ config.services.tailscale.interfaceName ];
          allowedUDPPorts = [ config.services.tailscale.port ];
        };
      };
    };
}