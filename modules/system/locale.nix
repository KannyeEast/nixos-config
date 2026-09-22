{ lib, ... }:
let
  inherit (lib)
    genAttrs
    ;
in
{
  flake.modules.nixos.system =
    { locale, ... }:
    {
      config = {
        time.timeZone = locale.timeZone;

        i18n.defaultLocale = locale.default;
        i18n.extraLocaleSettings = genAttrs [
          "LC_CTYPE"
          "LC_ADDRESS"
          "LC_MEASUREMENT"
          "LC_MESSAGES"
          "LC_MONETARY"
          "LC_NAME"
          "LC_NUMERIC"
          "LC_PAPER"
          "LC_TELEPHONE"
          "LC_TIME"
          "LC_COLLATE"
        ] (_: locale.extra);

        console.useXkbConfig = true;
        services.xserver.xkb = {
          inherit (locale.xkb)
            layout
            variant
            ;
        };
      };
    };
}
