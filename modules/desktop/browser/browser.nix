{ inputs, config, ... }:
let
  inherit (config.flake.modules)
    homeManager
    ;
in
{
  flake.modules.homeManager.browser = {
    imports = [
      inputs.zen-browser.homeModules.beta

      homeManager.browserBookmarks
      homeManager.browserContainers
      homeManager.browserExtensions
      homeManager.browserMods
      homeManager.browserPolicies
      homeManager.browserSearch
      homeManager.browserStorageManaged
      homeManager.browserStorageSync
      homeManager.browserTabs
      homeManager.browserUserChrome
    ];

    programs.zen-browser = {
      enable = true;
      setAsDefaultBrowser = true;
    };
  };
}
