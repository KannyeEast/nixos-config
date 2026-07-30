# Keybinds

Everything the config establishes. Bindings marked **(dotfiles)** come from
`hosts/<host>/home/`, everything else is set by a module and applies to every
host.

## zsh

| Key | Action | Source |
|---|---|---|
| `Tab` | fzf completion menu | fzf-tab |
| `Ctrl-R` | fuzzy history search | fzf |
| `Ctrl-T` | insert file path (fd-backed) | fzf |
| `Alt-C` | cd into directory (fd-backed) | fzf |
| `Ctrl-P` | history substring search, backward | **(dotfiles)** |
| `Ctrl-N` | history substring search, forward | **(dotfiles)** |
| `Ctrl-X` `s` | prefix the current line with `sudo` | oh-my-zsh sudo |
| `Ctrl-W` | delete one path segment | **(dotfiles)** |
| `Esc` | enter vi command mode | **(dotfiles)** `bindkey -v` |

Inside any fzf window: `Ctrl-J`/`Ctrl-K` or arrows to move, `Enter` to accept,
`Esc` to cancel.

Sudo is on `Ctrl-X s` rather than the usual `Esc` `Esc` because `KEYTIMEOUT=1`
leaves 10ms to type the second `Esc`. Any `Esc`-prefixed binding - which
includes every `Alt` combination - has the same problem under vi mode.

## tmux

Prefix is `Ctrl-Space` **(dotfiles)**.

| Key | Action | Source |
|---|---|---|
| `Alt-H` / `Alt-L` | previous / next window (no prefix) | **(dotfiles)** |
| `prefix "` | split vertically, keep cwd | **(dotfiles)** |
| `prefix %` | split horizontally, keep cwd | **(dotfiles)** |
| `prefix b` | toggle the status bar | **(dotfiles)** |
| `prefix c` | new window | tmux default |
| `prefix d` | detach session | tmux default |
| `prefix z` | zoom / unzoom pane | tmux default |
| `prefix x` | kill pane | tmux default |
| `prefix [` | enter copy mode | tmux default |
| `prefix R` | reload config | tmux-sensible |
| `prefix Ctrl-S` | save session | tmux-resurrect |
| `prefix Ctrl-R` | restore session | tmux-resurrect |

Copy mode is vi-style **(dotfiles)**:

| Key | Action |
|---|---|
| `v` | begin selection |
| `Ctrl-V` | toggle rectangle selection |
| `y` | copy selection and exit (to system clipboard via tmux-yank) |

## niri

@TODO: fill in once the KDL is declarative.
