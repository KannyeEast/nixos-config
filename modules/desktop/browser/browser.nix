{ inputs, config, ... }:
let
    inherit (config.flake.modules) nixos homeManager;
in
{
    # @TODO: Settings-testing round: audit which extensions read storage.managed
    # (unzip xpi, rg 'storage\.managed') and declare their settings via
    # extensions.settings. Verify default_area pinning still applies.
    # @TODO: After hoisting (containers/tabs done, search split): move the
    # host-side browser data to the private repo and feed it through the profile
    flake.modules.nixos.browser = { ... }:
    {
        imports = [
            nixos.browserExtensions
            nixos.browserTabs
        ];
    };
        
    flake.modules.homeManager.browser = { ... }:
    {
        imports = [
            inputs.zen-browser.homeModules.beta
            
            homeManager.browserContainers
            homeManager.browserExtensions
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