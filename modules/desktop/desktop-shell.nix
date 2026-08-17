{ inputs, ... }:
{
  flake.modules.nixos.desktopShell =
    { pkgs, ... }:
    {
      config = {
        # @TODO: Custom quickshell
        environment.systemPackages = [
          pkgs.kdePackages.qtsvg
          pkgs.kdePackages.qtmultimedia
          pkgs.kdePackages.qtvirtualkeyboard
          pkgs.kdePackages.qt5compat
          
          (pkgs.quickshell.withModules [ pkgs.qt6.qtmultimedia ])
        ];
        
        nixpkgs.overlays = [ inputs.quickshell.overlays.default ];
      };
    };
}