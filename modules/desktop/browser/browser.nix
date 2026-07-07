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
            
            nixos.browser.containers
            nixos.browser.extensions
            nixos.browser.mods
            nixos.browser.policies
            nixos.browser.search
            nixos.browser.tabs
            nixos.browser.userChrome
        ];
        
        programs.zen-browser = {
            enable = true;
            setAsDefaultBrowser = true;
        };
    };
}