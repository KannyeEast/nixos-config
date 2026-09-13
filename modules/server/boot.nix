{
  flake.modules.nixos.server =
    {
      config = {
        boot.loader.systemd-boot.enable = true; 
        boot.loader.systemd-boot.configurationLimit = 10;
      };
    };
}
