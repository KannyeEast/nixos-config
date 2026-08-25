{
  flake.modules.homeManager.passwords =
    { ... }:
    {
      config = {
        xdg.autostart.enable = true;
        programs.keepassxc = {
          autostart = true;
          enable = true;
        };
      };
    };
}
