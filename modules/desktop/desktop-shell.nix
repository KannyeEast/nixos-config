{ inputs, ... }:
{
    flake.modules.nixos.desktopShell = { pkgs, ... }:
    {
        config = {
            # @TODO: Custom quickshell
             environment.systemPackages = [
                inputs.quickshell.packages.${pkgs.stdenv.hostPlatform.system}.default
                pkgs.kdePackages.qtsvg 
                pkgs.kdePackages.qtmultimedia 
                pkgs.kdePackages.qtvirtualkeyboard 
                pkgs.kdePackages.qt5compat
            ];
        };
    };
}