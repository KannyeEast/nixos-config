# nixos-config

A dendritic multi-host NixOS config that stays host-driven. Each machine is described as
data in `hosts/<host>/host.json` and the modules assemble themselves from that.

Application config stays in plain dotfiles under `hosts/<host>/home/`,
which mimics `/home/<user>` and is then symlinked out of the store rather than generated into it. Editing
`niri/bindings.kdl` or `keepassxc.ini` works the way it always has: change the
file, the change applies, and it's already in the repo.

Nix owns packages, services and system state; the dotfiles own everything you'd normally tweak by
hand.

## Branches

| Branch | Contents                                             |
|---|------------------------------------------------------|
| `main` | The config only, without my custom hosts added to it |
| `dev` | My personal version                                  |

Clone `main` unless you specifically want to read my host definitions. The
installer creates your own either way.

## Install

From the NixOS installer ISO:

```sh
git clone -b main https://codeberg.org/KanyeSouth/nixos-config
cd nixos-config
sudo ./install.sh
```


The installer asks for hostname, roles, user, locale, hardware, disk and
optional wifi, then partitions, generates SSH and age keys, writes the host
files and runs `nixos-install`. Everything it writes is shown for review before
anything destructive happens.

### Reinstalling an existing host

When the disk layout changes and the host files and keys should survive, you can reinstall an existing host:

```sh
sudo ./install.sh -i
```

## Day to day

```sh
just switch       # rebuild and activate
just boot         # activate on next boot
just build        # build only, then show the diff
just check        # evaluate every output
just update       # update flake inputs
just edit-secrets # decrypt, edit and re-encrypt with sops
```

`just switch` pulls, initialises submodules, stages untracked files so Nix can
see them, and refuses to run while the browser is open.
