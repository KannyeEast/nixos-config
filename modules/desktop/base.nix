{ config, lib, ... }:
let
    inherit (config.flake.modules) nixos;
    inherit (lib) mkOption types elem;
in
{
    flake.modules.nixos.base = { config, pkgs, ... }:
    let
        inherit (config.profile) desktop;
    in
    {
        imports = [
            nixos.audio
            nixos.bluetooth
            nixos.optionals
            nixos.experimental
        ];
        
        options = {
            profile.desktop.modules = mkOption {
                type = types.listOf (types.enum [ "experimental" "optionals" ]);
                default = [ ];
                description = "Which optional program groups to enable";
            };
        };
        
        config = {
            internal.desktop.experimental.enable = elem "experimental" desktop.modules;
            internal.desktop.optionals.enable = elem "optionals" desktop.modules;
        };
    };
}