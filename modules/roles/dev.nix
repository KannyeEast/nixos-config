{ config, lib, ... }:
let
  inherit (config.flake.modules)
    nixos
    ;

  inherit (lib)
    optionals
    ;
in
{
  flake.modules.nixos.dev =
    { host, ... }:
    let
      # roles[0] is the primary role (desktop or server)
      primary = builtins.head host.roles;
    in
    {
      imports = [
        nixos.debug
        nixos.direnv
        nixos.tuiShell
      ]
      ++ optionals (primary == "desktop") [
        nixos.ide
      ]
      ++ optionals (primary == "server") [
      ];
    };
}
