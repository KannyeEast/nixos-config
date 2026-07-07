{ lib, ... }:
let
    inherit (lib) mkOption types;
in
{
    flake.modules.nixos.locale = { config, ... }:
    let
        inherit (config.profile) system;
    in
    {
        options = {
            profile.system = {
                timeZone = mkOption {
                    type = types.str;
                    default = "America/New_York";
                    description = "Set to your local time zone";
                };
                locale = {
                    default = mkOption {
                        type = types.str;
                        default = "en_US.UTF-8";
                        description = "Set the language and characters for the system";
                    };
                    extra = mkOption {
                        type = types.str;
                        default = "en_US.UTF-8";
                        description = "Additional language support";
                    };
                };
            };
        };
        
        config = {
            time.timeZone = system.timeZone;
            
            i18n.defaultLocale = system.locale.default;
            i18n.extraLocaleSettings = {
                LC_CTYPE = system.locale.extra;
                LC_ADDRESS =  system.locale.extra;
                LC_MEASUREMENT =  system.locale.extra;
                LC_MESSAGES =  system.locale.extra;
                LC_MONETARY =  system.locale.extra;
                LC_NAME =  system.locale.extra;
                LC_NUMERIC =  system.locale.extra;
                LC_PAPER =  system.locale.extra;
                LC_TELEPHONE =  system.locale.extra;
                LC_TIME =  system.locale.extra;
                LC_COLLATE =  system.locale.extra;
            };
        };
    };
}