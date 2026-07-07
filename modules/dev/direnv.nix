{ ... }:
let
in
{
    flake.modules.nixos.direnv = { ... }:
    let
    in
    { 
        config = {
            programs.direnv = {
                enable = true;
                nix-direnv.enable = true;
            };
        };
    };
}