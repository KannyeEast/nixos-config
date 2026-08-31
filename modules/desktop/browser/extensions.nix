{ lib, ... }:
let
  inherit (lib)
    mapAttrs
    ;
in
{
  flake.modules.homeManager.browserExtensions =
    let
      mkExtensionEntry =
        {
          id,
          pinned ? false,
        }:
        let
          base = {
            install_url = "https://addons.mozilla.org/firefox/downloads/latest/${id}/latest.xpi";
            installation_mode = "force_installed";
          };
        in
        if pinned then base // { default_area = "navbar"; } else base // { default_area = "menupanel"; };

      mkExtensionSettings = mapAttrs (
        _: entry:
        if builtins.isString entry then mkExtensionEntry { id = entry; } else mkExtensionEntry entry
      );

      extensions = {
        "uBlock0@raymondhill.net" = {
          id = "ublock-origin";
          pinned = true;
        };
        "keepassxc-browser@keepassxc.org" = {
          id = "keepassxc-browser";
          pinned = true;
        };
        "78272b6fa58f4a1abaac99321d503a20@proton.me" = {
          id = "proton-pass";
          pinned = true;
        };
        "{d867162c-4c38-4c5f-aca4-db6a6592d7da}" = "youtube-tweaks"; # Redundant with custom extensions
        "{b8326f03-322f-4112-96bd-e7996548d99f}" = "theater-mode-for-youtube"; # Redundant with custom extensions
        "deArrow@ajay.app" = "dearrow";
        "sponsorBlocker@ajay.app" = "sponsorblock";
        "firefox@tampermonkey.net" = "tampermonkey";
        "{b86e4813-687a-43e6-ab65-0bde4ab75758}" = "localcdn-fork-of-decentraleyes";
        "harper@writewithharper.com" = "private-grammar-checker-harper";
        "{9076cefe-e6f8-4883-a480-9f968bd09249}" = "reddit-nsfw-unblocker";
        "gdpr@cavi.au.dk" = "consent-o-matic";
      };
    in
    {
      config = {
        programs.zen-browser.policies.ExtensionSettings = mkExtensionSettings extensions // {
          "*" = {
            blocked_install_message = "Modify the nixos-config to install extension";
            install_sources = [ "https://addons.mozilla.org/*" ];
            installation_mode = "blocked";
          };
        };
      };
    };
}
