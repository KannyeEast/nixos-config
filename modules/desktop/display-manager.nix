{ lib, ... }:
{
  flake.modules.nixos.displayManager =
    { pkgs, host, ... }:
    let
      inherit (host) hostname;
      
      hostConfigDir = ../../hosts/${hostname}/home/.config/system;
      sddmDir = hostConfigDir + "/sddm";
      
      hasSddmTheme = builtins.pathExists (sddmDir + "/theme.json");
      
      sddm = if hasSddmTheme 
        then builtins.fromJSON (builtins.readFile (sddmDir + "/theme.json"))
        else { package = ""; theme = ""; };
        
      sddmTheme = pkgs.runCommand "sddm-theme-${sddm.theme}" { } ''
        dest=$out/share/sddm/themes/${sddm.theme}
        mkdir -p "$dest"
        cp -r ${pkgs.${sddm.package}}/share/sddm/themes/${sddm.theme}/. "$dest"/
        cp ${sddmDir + "/theme.conf"} "$dest"/theme.conf
      '';
    in
    {
      config = {
        services.displayManager.sddm = {
          enable = true;
          wayland.enable = true;
          package = pkgs.kdePackages.sddm;
        } // lib.optionalAttrs hasSddmTheme {
          theme = "${sddmTheme}/share/sddm/themes/${sddm.theme}";
        };
      };
    };
}
