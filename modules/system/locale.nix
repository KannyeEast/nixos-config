{ ... }:
{
    flake.modules.nixos.locale = { host, ... }:
    let
        inherit (host) locale;
    in
    {
        config = {
            time.timeZone = locale.timeZone;
            
            i18n.defaultLocale = locale.localeDefault;
            i18n.extraLocaleSettings = {
                LC_CTYPE = locale.localeExtra;
                LC_ADDRESS =  locale.localeExtra;
                LC_MEASUREMENT =  locale.localeExtra;
                LC_MESSAGES =  locale.localeExtra;
                LC_MONETARY =  locale.localeExtra;
                LC_NAME =  locale.localeExtra;
                LC_NUMERIC =  locale.localeExtra;
                LC_PAPER =  locale.localeExtra;
                LC_TELEPHONE =  locale.localeExtra;
                LC_TIME =  locale.localeExtra;
                LC_COLLATE =  locale.localeExtra;
            };
        };
    };
}