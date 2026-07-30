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
| `Esc` `Esc` | prefix the current line with `sudo` | oh-my-zsh sudo |
| `Esc` | enter vi command mode | **(dotfiles)** `bindkey -v` |

Inside any fzf window: `Ctrl-J`/`Ctrl-K` or arrows to move, `Enter` to accept,
`Esc` to cancel.

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

Sessions are auto-saved by tmux-continuum and restored on server start.

## Commands worth remembering

Not keybinds, but they come from the config and are easy to forget.

### undo

Reverts what the last command did to the filesystem. The shell hook is always
armed; nothing runs between commands.

| Command | Action |
|---|---|
| `undo` | revert the most recent command that changed files |
| `undo -i` | pick a session, cherry-pick individual entries |
| `undo redo` | re-apply an undone session |
| `undo diff` | show what a session changed |
| `undo list` | recent sessions, newest first |
| `undo doctor` | verify the install with a live capture/restore test |

Run `undo` on its own line, never chained with `&&`. It cannot see Go binaries,
static binaries, or anything under `sudo`. It is a safety net, not a backup.

### oh-my-zsh plugins

| Command | Action |
|---|---|
| `x <file>` | extract any archive format |
| `copypath [file]` | copy path to clipboard |
| `copyfile <file>` | copy file contents to clipboard |

Both copy commands need `wl-clipboard`, so they are desktop-only.

## niri

@TODO: fill in once the KDL is declarative.

## just

`just` on its own lists every recipe with its description.
