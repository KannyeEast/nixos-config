{ inputs, config, ... }:
let
    inherit (config.flake.modules) homeManager;
in
{
    # @TODO: Check if we can suppress the extensions forced window popup
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