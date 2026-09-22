{ inputs, ... }:
{
  flake.modules.homeManager.desktop = {
    imports = [
      inputs.zen-browser.homeModules.beta
    ];

    programs.zen-browser = {
      enable = true;
      setAsDefaultBrowser = true;
    };
  };
}
