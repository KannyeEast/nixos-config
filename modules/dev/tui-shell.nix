{ inputs, ... }:
{
    flake.modules.nixos.tuiShell = { pkgs, host, ... }:
    let
        inherit (host) user;
    in
    {
        config = {
            environment.sessionVariables = {
                # undo
                UNDO_CAPTURE_SHELL = "1";
                
                # bat
                MANPAGER = "sh -c 'col -bx | bat -l man -p'";
                MANROFFOPT = "-c";
                
                # fd
                FZF_DEFAULT_COMMAND = "fd --type f --hidden --exclude .git";
                FZF_CTRL_T_COMMAND = "fd --hidden --exclude .git";
                FZF_ALT_C_COMMAND = "fd --type d --hidden --exclude .git";
                

                EDITOR = "emacs"; # Move this to its own module
            };

            users.users.${user.name}.shell = pkgs.zsh;

            environment.shells = [
                pkgs.zsh
            ];

            environment.systemPackages = [
                pkgs.emacs # Move this to its own module
                
                inputs.undo.packages.${pkgs.stdenv.hostPlatform.system}.default # CTRL + Z for tui
                pkgs.bat # Prettier cat pages
                pkgs.eza # better ls
                pkgs.fd # better find
                pkgs.fzf # fuzzy find
                pkgs.ripgrep # recursive search
                pkgs.starship # tui prompt
                pkgs.zoxide # better cd
                pkgs.zsh-completions # autocompletion
                pkgs.jq
            ];
            
            programs.tmux = {
                enable = true;
                terminal = "tmux-256color";
                extraConfig = ''
                    set -ga terminal-features "*:RGB"
                    set -g @continuum-restore 'on'
                '';
                plugins = [
                    pkgs.tmuxPlugins.sensible
                    pkgs.tmuxPlugins.yank
                    pkgs.tmuxPlugins.resurrect
                    pkgs.tmuxPlugins.continuum
                ];
            };
            
            programs.zsh = {
                enable = true;
                autosuggestions.enable = true;
                syntaxHighlighting.enable = true;

                interactiveShellInit = ''
                    source ${pkgs.oh-my-zsh}/share/oh-my-zsh/lib/clipboard.zsh
                    source ${pkgs.oh-my-zsh}/share/oh-my-zsh/plugins/copyfile/copyfile.plugin.zsh
                    source ${pkgs.oh-my-zsh}/share/oh-my-zsh/plugins/copypath/copypath.plugin.zsh
                    source ${pkgs.oh-my-zsh}/share/oh-my-zsh/plugins/extract/extract.plugin.zsh
                    source ${pkgs.oh-my-zsh}/share/oh-my-zsh/plugins/sudo/sudo.plugin.zsh
                    source ${inputs.undo.packages.${pkgs.stdenv.hostPlatform.system}.default}/share/undo/undo.zsh
                    source ${pkgs.zsh-fzf-tab}/share/fzf-tab/fzf-tab.plugin.zsh
                    source ${pkgs.zsh-history-substring-search}/share/zsh-history-substring-search/zsh-history-substring-search.zsh
                    source ${pkgs.zsh-you-should-use}/share/zsh/plugins/you-should-use/you-should-use.plugin.zsh
                   
                    eval "$(fzf --zsh)" 
                    eval "$(zoxide init --cmd cd zsh)"
                '';

            };
        };
    };
}