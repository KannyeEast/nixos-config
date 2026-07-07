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
            nixos.fonts
        ];
        
        config = { 
            home-manager.sharedModules = [
                homeManager.browser
            ];
            
            environment.systemPackages = [
               pkgs.keepassxc                         
            ];
        };
    };
}