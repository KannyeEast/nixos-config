{ lib, ... }:
let
    inherit (lib) mkOption types;
in
{
    flake.modules.nixos.shell = { config, pkgs, ... }:
    let
        inherit (config.profile) user;
    in
    {
        options = {
            profile.user = {
                terminal = mkOption {
                    type = types.package;
                    default = pkgs.alacritty;
                    description = "Preferred user terminal";
                };
            };
        };
        
        config = {
            environment.sessionVariables = {
                TERMINAL = user.terminal;
                EDITOR = emacs;
            };
        
            environment.systemPackages = [
                user.terminal
                pkgs.emacs
                
                pkgs.bat
                pkgs.eza
                pkgs.fzf
                pkgs.oh-my-posh
                pkgs.tmux
                pkgs.zoxide
            ];
        };
    };
}
