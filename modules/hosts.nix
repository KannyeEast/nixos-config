{ lib, ... }:
let
  inherit (lib) mapAttrsToList;
in
{
  imports = mapAttrsToList (n: _: import ../lib/mkHost.nix (../hosts + "/${n}")) (
    import ../lib/listHosts.nix lib
  );
}
