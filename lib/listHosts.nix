lib:
let
  inherit (lib) mapAttrs filterAttrs;
  dir = ../hosts;
in
mapAttrs (n: _: builtins.fromJSON (builtins.readFile (dir + "/${n}/host.json"))) (
  filterAttrs (n: t: t == "directory" && builtins.pathExists (dir + "/${n}/host.json")) (
    builtins.readDir dir
  )
)
