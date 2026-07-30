{ ... }:
let
    inherit (builtins.fromJSON (builtins.readFile ./host.json)) hostname;
in
{
    imports = [
        (import ../../lib/mkHost.nix ./.)
    ];

    flake.modules.nixos."${hostname}Configuration" = { ... }:
    {
        config = {
            profile.system = {
                bootloader.settings = { };
                bootloader.plymouth = { };

                bootloader.refind = {
                    enable = false;
                    theme.name = null;
                    theme.source = null;
                };
            };

            profile.user = {
                xkb.layout = "us";
                xkb.variant = "";
            };

            profile.desktop = {
                displayManager.settings = { };
                displayManager.extraPackages = [ ];
            };
        };
    };
}
