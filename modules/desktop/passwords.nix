{
  flake.modules.homeManager.desktop = {
    config = {
      xdg.autostart.enable = true;
      programs.keepassxc = {
        autostart = true;
        enable = true;
      };
    };
  };
}
