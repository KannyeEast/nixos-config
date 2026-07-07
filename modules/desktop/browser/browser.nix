{ inputs, config, ... }:
let
    inherit (config.flake.modules) homeManager;
in
{
    flake.modules.homeManager.browser = { ... }:
    let
    in
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