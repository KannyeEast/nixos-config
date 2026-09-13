{ lib, ... }:
let
  inherit (lib)
    mkIf
    mkMerge
    ;
in
{
  flake.modules.nixos.system =
    { config, ... }:
    let
      # tailscale only enables itself if the host has a valid authkey in secrets.json
      secrets = builtins.fromJSON (builtins.readFile config.sops.defaultSopsFile);
      hasAuthKey = secrets ? "tailscale-authkey";
    in
    {
      config = mkMerge [
        (mkIf hasAuthKey {
          sops.secrets.tailscale-authkey = { };
          services.tailscale.authKeyFile = config.sops.secrets.tailscale-authkey.path;
        })

        {
          # persist the authkey
          internal.system.impermanence.directories = [
            {
              directory = "/var/lib/tailscale";
              mode = "0700";
            }
          ];

          # magicdns resolves through resolved
          services.resolved.enable = true;

          services.tailscale = {
            enable = true;

            # open UDP ports to allow direct connections
            openFirewall = true;
          };
        }
      ];
    };
}
