{ inputs, config, ... }:
let
    inherit (config.flake.modules) nixos;
in
{
    flake.modules.nixos.browser = { ... }:
    let
    in
    {
        imports = [
            inputs.zen-browser.homeModules.beta
            
            nixos.browserContainers
            nixos.browserExtensions
            nixos.browserMods
            nixos.browserPolicies
            nixos.browserSearch
            nixos.browserTabs
            nixos.browserUserChrome
        ];
        
        programs.zen-browser = {
            enable = true;
            setAsDefaultBrowser = true;
        };
    };
}