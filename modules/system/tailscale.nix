{ ... }:
{
  flake.modules.nixos.tailscale =
    { config, ... }:
    {
      config = {
        services.tailscale.enable = true;

        # strict rp_filter drops tailscale's packets when another VPN
        # owns the default route, which ProtonVPN does on the laptop
        networking.firewall = {
          trustedInterfaces = [ config.services.tailscale.interfaceName ];
          allowedUDPPorts = [ config.services.tailscale.port ];
        };
      };
    };
}