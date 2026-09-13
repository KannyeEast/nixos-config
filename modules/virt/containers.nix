{ lib, ... }:
let
  inherit (lib)
    mkIf
    ;
in
{
  flake.modules.nixos.virt =
    { pkgs, host, ... }:
    {
      config = mkIf (host.class == "desktop") {
        virtualisation.podman = {
          enable = true;

          # containers run as the invoking user, so a throwaway image cannot
          # touch anything the user could not touch anyway
          dockerCompat = true;

          # lets containers resolve each other by name on a user-defined network
          defaultNetwork.settings.dns_enabled = true;
        };

        environment.systemPackages = [ pkgs.podman-compose ];
      };
    };
}
