{
  flake.modules.nixos.storage = {
    config = {
      services.btrfs.autoScrub = {
        enable = true;
        interval = "monthly";
        fileSystems = [
          "/"
          "/srv/media"
          "/srv/vault"
        ];
      };

      services.smartd = {
        enable = true;
        autodetect = true;

        defaults.autodetected = "-a -o on -S on -s (S/../.././05|L/../../6/06) -M daily";
      };
    };
  };
}
