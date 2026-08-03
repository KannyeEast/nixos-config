{ inputs, config, ... }:
let
  inherit (config.flake.modules) homeManager;
in
{
  # @TODO: Theme zen from the shared palette
  # Part of the stylix work. Zen pulls its colours from the one palette
  # source like everything else, no hand-maintained copy here.
  flake.modules.homeManager.browser =
    { ... }:
    {
      imports = [
        inputs.zen-browser.homeModules.beta

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
