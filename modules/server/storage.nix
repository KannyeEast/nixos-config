{ ... }:
{
  flake.modules.nixos.storage =
    { ... }:
    {
      config = {
        services.btrfs.autoScrub = {
          enable = true;
          interval = "monthly";
          fileSystems = [ "/srv/media" ];
        };
        
        services.smartd = {
          enable = true;
          autodetect = true;
          # @TODO: Add notifications to SMART scans
          #notifications = { };
        };
      };
    };
}
