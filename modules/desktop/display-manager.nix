{ lib, ... }:
let
  inherit (lib)
    optionalAttrs
    optionalString
    ;
in
{
  flake.modules.nixos.displayManager =
    { pkgs, host, ... }:
    let
      hostConfigDir = ../../hosts/${host.name}/home/.config/system;
      sddmDir = hostConfigDir + "/sddm";

      hasSddmTheme = builtins.pathExists (sddmDir + "/theme.json");

      sddm =
        if hasSddmTheme then
          builtins.fromJSON (builtins.readFile (sddmDir + "/theme.json"))
        else
          {
            package = "";
            theme = "";
          };

      sddmTheme = pkgs.runCommand "sddm-theme-${sddm.theme}" { } (
        ''
          dest=$out/share/sddm/themes/${sddm.theme}
          mkdir -p "$dest"
          cp -r ${pkgs.${sddm.package}}/share/sddm/themes/${sddm.theme}/. "$dest"/
          chmod -R u+w "$dest"
          cp ${sddmDir + "/theme.conf"} "$dest"/theme.conf
        ''
        + optionalString (sddm ? hint) ''
          substituteInPlace "$dest"/Main.qml --replace-fail \
            'Component.onCompleted: {' \
            'Text {
                      id: hintMessage
                      text: "${sddm.hint}"
                      color: textColor
                      font.pointSize: helpFontSize
                      font.family: helpFont
                      anchors {
                          bottom: parent.bottom
                          bottomMargin: 30
                          horizontalCenter: parent.horizontalCenter
                      }
                  }

                  Component.onCompleted: {'
        ''
      );
    in
    {
      config = {
        services.displayManager.sddm = {
          enable = true;
          wayland.enable = true;
          package = pkgs.kdePackages.sddm;
          extraPackages = [ pkgs.kdePackages.qt5compat ];
        }
        // optionalAttrs hasSddmTheme {
          theme = "${sddmTheme}/share/sddm/themes/${sddm.theme}";
        };
      };
    };
}
