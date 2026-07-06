{ ... }:
{
    flake.modules.homeManager.browser.extensions = { ... }:
    let
        mkExtensionSettings = builtins.mapAttrs (_: entry:
            if builtins.isAttrs entry
            then entry
            else mkExtensionEntry {id = entry;});
            
        mkExtensionEntry = { id, pinned ? false }:
        let
            base = {
                install_url = "https://addons.mozilla.org/firefox/downloads/latest/${id}/latest.xpi";
                installation_mode = "force_installed";
            };
        in
            if pinned
            then base // { default_area = "navbar"; }
            else base // { default_area = "menupanel"; };   
    in
    {
        # @TODO: Need to configure extension settings
        # Entry = about:debugging#/runtime/this-firefox
        # Id = https://addons.mozilla.org/en-US/firefox/addon/<extension>
        config = {
            programs.zen-browser.policies = {
                ExtensionSettings = mkExtensionSettings {
                    "vpn@proton.ch" = mkExtensionEntry {
                        id = "proton-vpn-firefox-extension";
                        pinned = true;
                    };
                    "uBlock0@raymondhill.net" = mkExtensionEntry {
                        id = "ublock-origin";
                        pinned = true;
                    };
                    "keepassxc-browser@keepassxc.org" = mkExtensionEntry {
                        id = "keepassxc-browser";
                        pinned = true;
                    };
                    "78272b6fa58f4a1abaac99321d503a20@proton.me" = mkExtensionEntry {
                        id = "proton-pass";
                        pinned = true;
                    };
                    "namlet@pax.red" = mkExtensionEntry {
                        id = "namlet";
                        pinned = true;
                    };
                    "{a6c4a591-f1b2-4f03-b3ff-767e5bedf4e7}" = mkExtensionEntry {
                        id = "user-agent-string-switcher";
                        pinned = true;
                    };
                    "{d867162c-4c38-4c5f-aca4-db6a6592d7da}" = "youtube-tweaks";
                    "deArrow@ajay.app" = "dearrow";
                    "sponsorBlocker@ajay.app" = "sponsorblock";
                    "firefox@tampermonkey.net" = "tampermonkey";
                    "{b86e4813-687a-43e6-ab65-0bde4ab75758}" = "localcdn-fork-of-decentraleyes";
                    "harper@writewithharper.com" = "private-grammar-checker-harper";
                    "{b8326f03-322f-4112-96bd-e7996548d99f}" = "theater-mode-for-youtube";
                    "{9076cefe-e6f8-4883-a480-9f968bd09249}" = "reddit-nsfw-unblocker";
                };
                
                "3rdparty".Extensions = {
                    "uBlock0@raymondhill.net" = {
                        # Where do I find settings?
                    };
                };
            };
        };
    };
}