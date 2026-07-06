{ config, lib, ... }:
let
    inherit (config.flake.modules) nixos homeManager;
    inherit (lib) mkEnableOption mkOption types elem;
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
            
            homeManager.browser
        ];
        
        options = {
            profile.desktop.experimental = mkEnableOption "Enable experimental suite";
        };
        
        config = {
            # @TODO: These might not be needed anymore? Depends on how the config evolves with roles (roles as replacement to program selection)
            # Experimental = Dev (Maybe keep though) || Base stays to import non configurable (or dotfiles) packages and the modules
            internal.desktop.experimental.enable = mkif desktop.experimental;
            
            environment.systemPackages = [
               pkgs.keepassxc                         
            ];
        };
    };
}