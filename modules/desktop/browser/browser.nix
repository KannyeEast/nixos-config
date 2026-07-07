{ inputs, config, ... }:
let
    inherit (config.flake.modules) homeManager;
in
{
    flake.modules.nixos.browser = { ... }:
    let
    in
    {
        imports = [
            inputs.zen-browser.homeModules.beta
            
            homeManager.browser.containers
            homeManager.browser.extensions
            homeManager.browser.mods
            homeManager.browser.policies
            homeManager.browser.search
            homeManager.browser.tabs
            homeManager.browser.userChrome
        ];
        
        programs.zen-browser = {
            enable = true;
            setAsDefaultBrowser = true;
        };
    };
}