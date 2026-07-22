{ inputs, config, ... }:
let
    inherit (config.flake.modules) homeManager;
in
{
    # Opinionated by design: all browser data is hardcoded in these modules,
    # there are no host options.
    # @TODO: Move the data to the private repo later
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