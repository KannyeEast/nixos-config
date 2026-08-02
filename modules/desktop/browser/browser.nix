{ inputs, config, ... }:
let
    inherit (config.flake.modules) homeManager;
in
{
    # @TODO: Theme zen from the shared palette
    # Part of the stylix work. Zen pulls its colours from the one palette
    # source like everything else, no hand-maintained copy here.

    # @TODO: Open new tabs (CTRL + T) in current container
    # A new tab opened from a containered tab should inherit that container,
    # since it almost always belongs to the same context. Escape hatch for
    # when it doesn't:
    #   CTRL + T          -> new tab, inherits current container
    #   CTRL + SHIFT + T  -> new tab, no container

    # @TODO: Keep login cookies while clearing the rest
    # Replaces the current Cookies.Allow policy, which is all-or-nothing per
    # site. Want per-cookie retention: keep cookie a and b for a site, drop
    # the rest. Automatic detection of which cookie is the session cookie
    # would be ideal but is not realistic; an explicit per-site list is fine.
    # Needed at minimum for: git forges, youtube, and every site currently
    # in Cookies.Allow.
    # NOTE: no Firefox policy or pref does per-cookie granularity. Only an
    # extension (Cookie AutoDelete or similar) can, which ties this to the
    # extension-settings TODO below.

    # @TODO: Declarative extension settings
    # Save for last, needs experimentation.
    flake.modules.homeManager.browser = { ... }:
    {
        imports = [
            inputs.zen-browser.homeModules.beta
            
            homeManager.browserContainers
            homeManager.browserExtensions
            homeManager.browserExtensionStorage
            homeManager.browserMods
            homeManager.browserPolicies
            homeManager.browserSearch
            homeManager.browserTabs
            homeManager.browserUserChrome
        ];
        
        programs.zen-browser = {
            enable = true;
            setAsDefaultBrowser = true;
        };
    };
}