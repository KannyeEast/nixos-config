{ ... }:
let
in
{
    flake.modules.homeManager.browserSearch = { pkgs, ... }:
    let
        nixIcon = "${pkgs.nixos-icons}/share/icons/hicolor/scalable/apps/nix-snowflake.svg";
    in
    {
        config = {
            programs.zen-browser.profiles.default.search = {
                force = true;
                
                default = "Kagi";
                privateDefault = "Kagi";

                engines = {
                    "Kagi" = {
                        urls = [{
                            template = "https://kagi.com/search";
                            params = [
                                { name = "q"; value = "{searchTerms}"; }
                            ];
                        }];
                        icon = "https://kagi.com/favicon.ico";
                        definedAliases = [ "@k" ];
                    };
                    
                    "Nix Packages" = {
                        urls = [{
                            template = "https://search.nixos.org/packages";
                            params = [
                                { name = "channel"; value = "unstable"; }
                                { name = "type"; value = "packages"; }
                                { name = "query"; value = "{searchTerms}"; }
                            ];
                        }];
                        icon = nixIcon;
                        definedAliases = [ "@np" ];
                    };
                    
                    "Home Manager Options" = {
                        urls = [{
                            template = "https://home-manager-options.extranix.com/";
                            params = [
                                { name = "query";   value = "{searchTerms}"; }
                                { name = "release"; value = "master"; }
                            ];
                        }];
                        icon = nixIcon;
                        definedAliases = [ "@hm" ];
                    };
                    
                    "MyNixOS" = {
                        urls = [{
                            template = "https://mynixos.com/search";
                            params = [
                                { name = "q"; value = "{searchTerms}"; }
                            ];
                        }];
                        icon = nixIcon;
                        definedAliases = [ "@mn" ];
                    };
                    
                    "Noogle" = {
                        urls = [
                            {
                                template = "https://noogle.dev/q";
                                params = [
                                    { name = "term"; value = "{searchTerms}"; }
                                ];
                            }
                        ];
                        icon = nixIcon;
                        definedAliases = [ "@ng" ];
                    };
                    
                    "Color Codes" = {
                        urls = [{
                            template = "https://htmlcolorcodes.com/hex-to-rgb/";
                        }];
                        icon = "https://htmlcolorcodes.com/favicon.ico";
                        definedAliases = [ "@hex" "@rgb" ];
                    };

                    "bing".metaData.hidden = true;
                    "google".metaData.hidden = true;
                    "ddg".metaData.hidden = true;
                    "ebay".metaData.hidden = true;
                    # @TODO: Add the rest of default engines
                };
            };
        };
    };
}
