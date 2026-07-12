{ ... }:
let
in
{
    flake.modules.nixos.desktopShell = { pkgs, ... }:
    let
    in
    {
        config = {
            # @TODO: Do shell stuff here
             environment.systemPackages = [
                pkgs.kdePackages.qtsvg 
                pkgs.kdePackages.qtmultimedia 
                pkgs.kdePackages.qtvirtualkeyboard 
                pkgs.kdePackages.qt5compat
            ];
        };
    };
}