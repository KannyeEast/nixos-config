# mkBtrfsRaid.nix
# returns a disko.devices.disk fragment for one raid btrfs filesystem
# has to be merged into a disko.devices.disk configuration
#
# disko has no multi-device type, so the array is expressed the way mkfs.btrfs takes it:
#
# > head device
#   contains the actual content (subvolumes, mountpoints)
#   and a mkfs invocation that lists the other devices
#
# > member devices
#   contains a placeholder entry with an empty partition table
#   that way disko still accounts for the disk without writing to it
#
# the caller must also add, for every mountpoint on the array:
# > fileSystems."<mountpoint>".device = lib.mkForce "/dev/disk/by-label/<label>";
# disko points them at the head device by path. If that is the disk that fails the path also fails
# but the array can still mount by label
#
# for detailed raid profiles visit: https://wiki.tnonline.net/w/Btrfs/Profiles
{
  name,
  devices,
  data ? "raid1",
  # metadata profile (-m) should normally follow the data profile, but issues with raid5/6 parity
  # could cause the metadata to corrupt and break the entire filesystem, so we mirror instead
  metadata ? if data == "raid5" || data == "raid6" then "raid1" else data,
  label ? name,
  destroy ? true,
  content ? { },
}:
let
  # list of min disk requirements for various raid configurations
  minimum = {
    single = 1;
    dup = 1;
    raid0 = 2;
    raid1 = 2;
    raid1c3 = 3;
    raid1c4 = 4;
    raid10 = 4;
    raid5 = 3;
    raid6 = 4;
  };

  diskCount = builtins.length devices;

  # the first (head) disk in the list; carries the real filesystem
  headDisk =
    if diskCount == 0 then throw "mkBtrfsRaid ${name}: no devices given" else builtins.head devices;
  # all disks in the devices list apart from the head disk
  members = builtins.tail devices;

  # compares and checks if the passed profile fulfills the minimum device count for that raid configuration
  checkProfile =
    profile:
    if !(minimum ? ${profile}) then
      throw "mkBtrfsRaid ${name}: unknown profile ${profile}"
    else if diskCount < minimum.${profile} then
      throw "mkBtrfsRaid ${name}: ${profile} needs ${toString minimum.${profile}} devices, given ${toString diskCount}"
    else
      profile;
in
# member disks disko configuration
builtins.listToAttrs (
  builtins.genList (index: {
    name = "#${name}-member-${toString index}";
    value = {
      type = "disk";
      device = builtins.elemAt members index;
      inherit destroy;
      content = {
        type = "gpt";
        partitions = { };
      };
    };
  }) (builtins.length members)
)
# head disk disko configuration
// {
  ${name} = {
    type = "disk";
    device = headDisk;
    inherit destroy;
    content = content // {
      type = "btrfs";
      extraArgs =
        (content.extraArgs or [ ])
        ++ [
          "-f" # force
          "-L" # label
          label
          "-d" # data profile
          (checkProfile data)
          "-m" # metadata profile
          (checkProfile metadata)
        ]
        ++ members;
    };
  };
}
