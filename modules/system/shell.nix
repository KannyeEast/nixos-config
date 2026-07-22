{ ... }:
{
    flake.modules.nixos.shell = { pkgs, ... }:
    {
        config = {
            environment.sessionVariables = {
                TERMINAL = "alacritty";
                EDITOR = "emacs";
            };
        
            environment.systemPackages = [
                pkgs.alacritty
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
