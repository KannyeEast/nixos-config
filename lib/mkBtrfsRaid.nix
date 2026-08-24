{
  name,
  devices,
  raid ? "raid1",
  label ? name,
  destroy ? true,
  content ? { },
}:
let
  inherit (builtins) head tail length genList elemAt listToAttrs;
  members = tail devices;
in
# disko processes disks in attribute-name order and "#" sorts before
# alphanumerics, so these run first. That ordering matters: mkfs -f below
# overwrites these tables, and it would be destroyed if they ran after.
# They exist so disko lists every member in the wipe confirmation instead
# of silently claiming them.
listToAttrs (
  genList (i: {
    name = "#${name}-member-${toString i}";
    value = {
      type = "disk";
      device = elemAt members i;
      inherit destroy;
      content = {
        type = "gpt";
        partitions = { };
      };
    };
  }) (length members)
)
// {
  ${name} = {
    type = "disk";
    device = head devices;
    inherit destroy;
    content = content // {
      type = "btrfs";
      extraArgs =
        (content.extraArgs or [ ])
        ++ [ "-f" "-L" label "-d" raid "-m" raid ]
        ++ members;
    };
  };
}