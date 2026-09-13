{ lib, ... }:
let
  inherit (lib)
    attrValues
    filterAttrs
    mapAttrs'
    nameValuePair
    ;
in
{
  flake.modules.nixos.server =
    { config, ... }:
    let
      btrfs = filterAttrs (_: fileSystem: fileSystem.fsType == "btrfs") config.fileSystems;

      # scrub works on a whole filesystem, so two subvolumes of the same device would scrub it twice
      scrubbable = attrValues (mapAttrs' (mount: fileSystem: nameValuePair fileSystem.device mount) btrfs);
    in
    {
      config = {
        services.btrfs.autoScrub = {
          enable = true;
          interval = "monthly";
          fileSystems = scrubbable;
        };

        services.smartd = {
          enable = true;
          autodetect = true;

          # short self-test nightly at 05:00, long test Saturdays at 06:00
          defaults.autodetected = "-a -o on -S on -s (S/../.././05|L/../../6/06) -M daily";
        };
      };
    };
}