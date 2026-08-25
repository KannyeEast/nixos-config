{
  flake.modules.nixos.locale =
    { locale, ... }:
    {
      config = {
        time.timeZone = locale.timeZone;

        i18n.defaultLocale = locale.default;
        i18n.extraLocaleSettings = {
          LC_CTYPE = locale.extra;
          LC_ADDRESS = locale.extra;
          LC_MEASUREMENT = locale.extra;
          LC_MESSAGES = locale.extra;
          LC_MONETARY = locale.extra;
          LC_NAME = locale.extra;
          LC_NUMERIC = locale.extra;
          LC_PAPER = locale.extra;
          LC_TELEPHONE = locale.extra;
          LC_TIME = locale.extra;
          LC_COLLATE = locale.extra;
        };

        console.useXkbConfig = true;
        services.xserver = {
          xkb.layout = locale.xkb.layout;
          xkb.variant = locale.xkb.variant;
        };
      };
    };
}
