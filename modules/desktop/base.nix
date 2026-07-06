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
        # Does this stay here or should roles import this?
        imports = [
            nixos.audio
            nixos.bluetooth
            nixos.desktopEnvironment
            nixos.desktopShell
            nixos.displayManager
            nixos.experimental
            nixos.fonts
        ];
        
        options = {
            profile.desktop.modules = mkOption {
                type = types.listOf (types.enum [ "experimental" "optionals" ]);
                default = [ ];
                description = "Which optional program groups to enable";
            };
        };
        
        config = {
            # @TODO: These might not be needed anymore? Depends on how config evolves with roles (roles as replacement to program selection)
            # Experimental = Dev (Maybe keep though) || Base stays to import non configurable (or dotfiles) packages and the modules
            internal.desktop.experimental.enable = elem "experimental" desktop.modules;
        };
    };
}