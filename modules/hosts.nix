{ lib, ... }:
let
  dir = ../hosts;
  names = lib.attrNames (
    lib.filterAttrs (n: t: t == "directory" && builtins.pathExists (dir + "/${n}/host.json")) (
      builtins.readDir dir
    )
  );
in
{
  imports = map (n: import ../lib/mkHost.nix (dir + "/${n}")) names;
}
