# validHosts.nix
# checks if directories listed under <dir>/ are valid entries based on listed requirements
# builds a name value pair, where name = host.name and value = host.json
let
  dir = ../hosts;
  entries = builtins.readDir dir;

  # checks if directory found under <dir>/ is valid host entry; a host is valid when a host.json file is found
  isHost = name: entries.${name} == "directory" && builtins.pathExists (dir + "/${name}/host.json");

  required = [
    "system"
    "class"
  ];

  # reads the found host.json file and checks its contents against the required attributes
  read =
    name:
    let
      data = builtins.fromJSON (builtins.readFile (dir + "/${name}/host.json"));
      missing = builtins.filter (key: !((data.host or { }) ? ${key})) required;
    in
    if missing == [ ] then
      data
    else
      throw "hosts/${name}/host.json: missing ${
        builtins.concatStringsSep ", " (map (key: "host.${key}") missing)
      }";
in
builtins.listToAttrs (
  map (name: {
    inherit name;
    value = read name;
  }) (builtins.filter isHost (builtins.attrNames entries))
)
