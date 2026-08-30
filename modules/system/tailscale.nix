{ lib, ... }:
let
  inherit (lib)
    mkIf
    mkMerge
    ;
in
{
  flake.modules.nixos.tailscale =
    { config, ... }:
    let
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
          internal.system.impermanence.directories = [
            {
              directory = "/var/lib/tailscale";
              mode = "0700";
            }
          ];

          services.tailscale = {
            enable = true;
            openFirewall = true;
          };
        }
      ];
    };
}
