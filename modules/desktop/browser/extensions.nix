{ lib, ... }:
let
    inherit (lib) mkOption types;
in
{
    flake.modules.nixos.browserExtensions = { ... }:
    {
        options = {
            profile.desktop.browser.extensions = {
                # entry = about:debugging#/runtime/this-firefox
                # id    = https://addons.mozilla.org/en-US/firefox/addon/<id>
                install = mkOption {
                    type = types.attrsOf (types.either types.str types.attrs);
                    default = { };
                    description = "Extensions keyed by addon entry. A string is an AMO id, { id, pinned } controls navbar placement, anything else is a raw ExtensionSettings entry";
                };

                settings = mkOption {
                    type = types.attrsOf types.anything;
                    default = { };
                    description = "Extension settings (policies 3rdparty). Does not work for every extension";
                };
            };
        };
    };

    flake.modules.homeManager.browserExtensions = { osConfig, ... }:
    let
        inherit (osConfig.profile.desktop.browser) extensions;

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

        # Normalize the three accepted shapes into ExtensionSettings entries.
        # Raw entries never carry an `id` field, so that is the discriminator
        mkExtensionSettings = builtins.mapAttrs (_: entry:
            if builtins.isString entry
            then mkExtensionEntry { id = entry; }
            else if entry ? id
            then mkExtensionEntry entry
            else entry);
    in
    {
        config = {
            programs.zen-browser.policies = {
                ExtensionSettings = mkExtensionSettings extensions.install;
                "3rdparty".Extensions = extensions.settings;
            };
        };
    };
}
