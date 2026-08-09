{ ... }:
let
  inherit (builtins.fromJSON (builtins.readFile ./host.json)) hostname;
in
{
  imports = [
    (import ../../lib/mkHost.nix ./.)
  ];

  flake.modules.nixos."${hostname}Configuration" =
    { pkgs, ... }:
    {
      config = {
        profile.system = {
          # Grub attributes
          bootloader.settings = {
            theme = "${pkgs.sleek-grub-theme.override { withStyle = "dark"; }}";
            gfxmodeEfi = "1920x1080";
            splashImage = null;
          };
          # Plymouth attributes
          bootloader.plymouth = {
            theme = "loader_2";
            themePackages = [
              (pkgs.adi1090x-plymouth-themes.override {
                selected_themes = [ "loader_2" ];
              })
            ];
          };
        };

        profile.user = {
          xkb.layout = "us";
          xkb.variant = "";
        };

        profile.desktop = {

          displayManager = {
            settings = {
              theme = "where_is_my_sddm_theme";
            };
            extraPackages = [
              (pkgs.where-is-my-sddm-theme.override {
                themeConfig.General = {
                  background = "";
                  backgroundFill = "#0f1115";
                  backgroundFillMode = "fill";

                  font = "Inter";
                  basicTextColor = "#9aa1b1";
                  hideCursor = false;

                  passwordCharacter = "•";
                  passwordMask = true;
                  passwordFontSize = 28;
                  passwordInputWidth = 0.22;
                  passwordInputRadius = 12;
                  passwordInputBackground = "#171a21";
                  passwordInputBorderWidth = 1;
                  passwordInputBorderColor = "#262b36";
                  passwordTextColor = "#e6e8ee";
                  passwordCursorColor = "#8aa2ff";
                  passwordInputCursorVisible = true;
                  cursorBlinkAnimation = true;

                  wrongPasswordBorderColor = "#ff6b7a";
                  wrongPasswordBorderRadius = 12;

                  showUsersByDefault = true;
                  showUserRealNameByDefault = false;
                  usersFontSize = 16;

                  showSessionsByDefault = true;
                  sessionsFontSize = 12;

                  helpFont = "Inter";
                  helpFontSize = 11;
                };
              })
            ];
          };
        };
      };
    };
}
