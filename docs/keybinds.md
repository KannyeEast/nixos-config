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

All **(dotfiles)**, from `.config/niri/bindings.kdl`. `Mod` is Super on a TTY
and Alt when niri runs nested in a window. `Mod+Shift+/` opens the in-session
overlay, which lists whatever carries a `hotkey-overlay-title`.

Where an action has both an hjkl and an arrow binding, only hjkl is listed —
the arrows do the same thing.

### Launching

| Key | Action |
|---|---|
| `Mod+Return` | terminal (alacritty) |
| `Mod+Space` | launcher (fuzzel) |
| `Mod+B` | browser (zen) |
| `Mod+E` | files (nautilus) |
| `Mod+P` | passwords (keepassxc) |
| `Super+Alt+L` | lock the screen |

### Moving around

Columns run left to right on an endless strip; windows stack vertically
*within* a column. So `H`/`L` change column, `J`/`K` move inside one.

| Key | Action |
|---|---|
| `Mod+H` / `Mod+L` | focus column left / right |
| `Mod+J` / `Mod+K` | focus window down / up in the column |
| `Mod+Home` / `Mod+End` | focus first / last column |
| `Mod+Ctrl+H` … `Mod+Ctrl+L` | move the column or window in that direction |
| `Mod+Ctrl+Home` / `Mod+Ctrl+End` | move column to start / end |
| `Mod+O` | overview |

### Columns

The tiling equivalent of "I have too many windows" — group them instead of
spreading them out.

| Key | Action |
|---|---|
| `Mod+W` | toggle tabbed display for the column |
| `Mod+[` / `Mod+]` | consume or expel a window sideways |
| `Mod+,` | consume the next window into this column |
| `Mod+.` | expel the bottom window out of this column |

### Sizing

| Key | Action |
|---|---|
| `Mod+R` / `Mod+Shift+R` | cycle preset column widths, forward / back |
| `Mod+Ctrl+Shift+R` | cycle preset window heights |
| `Mod+Ctrl+R` | reset window height |
| `Mod+-` / `Mod+=` | column 10% narrower / wider |
| `Mod+Shift+-` / `Mod+Shift+=` | window 10% shorter / taller |
| `Mod+F` | maximize column (keeps gaps) |
| `Mod+M` | maximize to screen edges (no gaps) |
| `Mod+Shift+F` | fullscreen |
| `Mod+Ctrl+F` | expand column into unused space |
| `Mod+C` / `Mod+Ctrl+C` | center column / all visible columns |
| `Mod+V` | toggle floating |
| `Mod+Shift+V` | jump between the floating and tiling layers |
| `Mod+Q` | close window |

### Workspaces and monitors

| Key | Action |
|---|---|
| `Mod+U` / `Mod+I` | focus workspace down / up |
| `Mod+Ctrl+U` / `Mod+Ctrl+I` | move column to workspace down / up |
| `Mod+Shift+U` / `Mod+Shift+I` | reorder the workspace itself |
| `Mod+1`…`9` | focus workspace by index, within the focused monitor |
| `Mod+Ctrl+1`…`9` | move column to workspace by index |
| `Mod+Shift+H` … `Mod+Shift+L` | focus monitor in that direction |
| `Mod+Shift+Ctrl+H` … `+L` | move column to that monitor |

Indices are per-monitor and positional, so `Mod+3` means a different
workspace depending on which screen has focus.

### Scroll

| Key | Action |
|---|---|
| `Mod` + wheel up/down | change workspace (rate-limited) |
| `Mod+Shift` + wheel | change column |
| `Mod+Ctrl` + wheel | move the column instead of focusing |

### Screenshots and session

| Key | Action |
|---|---|
| `Print` | interactive selection |
| `Ctrl+Print` / `Alt+Print` | whole screen / focused window |
| `Mod+Escape` | toggle keyboard-shortcut inhibiting — the escape hatch when an app swallows your binds |
| `Mod+Shift+P` | power off monitors |
| `Mod+Shift+E`, `Ctrl+Alt+Del` | quit niri (confirms first) |

Media and brightness keys work as labelled, and keep working while locked.
