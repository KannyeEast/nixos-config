# Set flag for debugging
if [ -n "${ZSH_DEBUGRC+1}" ]; then
    zmodload zsh/zprof
fi



# Set the directory we want to store zinit and plugins
ZINIT_HOME="${XDG_DATA_HOME:-${HOME}/.local/share}/zinit/zinit.git"

# Download zinit if not already there
if [ ! -d "$ZINIT_HOME" ]; then
    mkdir -p "${dirname $ZINIT_HOME}"
    git clone https://github.com/zdharma-continuum/zinit.git "$ZINIT_HOME"
fi

# Source and load zinit
source "${ZINIT_HOME}/zinit.zsh"

# Add zsh plugins
zinit light zsh-users/zsh-syntax-highlighting
zinit light zsh-users/zsh-autosuggestions
zinit light zsh-users/zsh-completions
zinit light softmoth/zsh-vim-mode
zinit light fdellwing/zsh-bat
zinit light Aloxaf/fzf-tab

# Add snippets
zinit snippet OMZP::git
zinit snippet OMZP::sudo

# Load completions
autoload -Uz compinit && compinit -C

zinit cdreplay -q

# Initialize OhMyPosh
eval "$(oh-my-posh init zsh --config $HOME/.config/ohmyposh/config.toml)"

# Keybindings
bindkey -v
bindkey '^p' history-search-backward
bindkey '^n' history-search-forward
bindkey '^a' vi-movement-mode

# History
HISTSIZE=5000
HISTFILE=~/.zsh_history
SAVEHIST=$HISTSIZE
HISTDUP=erase
setopt appendhistory
setopt sharehistory
setopt hist_ignore_space
setopt hist_ignore_all_dups
setopt hist_save_no_dups
setopt hist_ignore_dups
setopt hist_find_no_dups
setopt GLOB_DOTS

# Completion styling
zstyle ':completion:*' matcher-list 'm:{a-z}={A-Za-z}'
zstyle ':completion:*' list-colors "${(s.:.)LS_COLORS}"
zstyle ':completion:*' menu no
zstyle ':fzf-tab:complete:cd:*' fzf-preview 'ls -aFh --color $realpath'
zstyle ':fzf-tab:complete:__zoxide_z:*' fzf-preview 'ls -aFh --color $realpath'

# Environment variables
export HYPRSHOT_DIR=$HOME/Pictures/Screenshots

# Aliases 
alias ls='eza --icons -a --group-directories-first'
alias lls='eza --icons -a -lT -L 1 --git --header'

alias grep='grep --color=auto'

alias v='nvim'
alias vi='nvim'
alias vim='nvim'

alias c='clear'

alias dotcommit="git add . && git commit -m '.' && git push origin main"

alias rebuild='sudo nixos-rebuild switch --flake ~/.nixos# --show-trace'

alias debug_zsh='time ZSH_DEBUGRC=1 zsh -i -c exit'

# Shell integration
eval "$(fzf --zsh)"
eval "$(zoxide init --cmd cd zsh)"


#######################################################
# SPECIAL FUNCTIONS
#######################################################

# Automatically do an ls after each cd, z, or zoxide
cd ()
{
	if [ -n "$1" ]; then
		builtin cd "$@" && ls
	else
		builtin cd ~ && ls
	fi
}

# don't append "not found command" to history
# https://www.zsh.org/mla/users//2014/msg00715.html
# https://superuser.com/questions/902241/how-to-make-zsh-not-store-failed-command
zshaddhistory() {
   local j=1
   while ([[ ${${(z)1}[$j]} == *=* ]]) {
     ((j++))
   }
   whence ${${(z)1}[$j]} >| /dev/null || return 1
 }



# Set flag for debugging
if [ -n "${ZSH_DEBUGRC+1}" ]; then
    zprof
fi