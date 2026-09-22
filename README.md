# nixos-config

## Philosophy

The goal of this config is to be truly host-dependent. Each machine is described
as data in `hosts/<host>/host.json` and the modules assemble themselves from that.

Modules under modules/ are only declared and preconfigured with what I believe every host needs.
A shared baseline and nothing more.

Everything beyond that baseline is driven through classic dotfiles living in `hosts/<host>/home/`,
which mimics `/home/<user>` and is symlinked out of the store rather than generated into it.
This means each host can be completely different while still building on the same module set.
You don't configure your desktop experience in Nix; you drop a `.config/` tree into `home/` and it gets symlinked into place.
If a host doesn't need something, it just doesn't have the file.

Nix owns packages, services and system state; the dotfiles own everything you'd
normally tweak by hand. Same modules, different hosts.

## Hosts

| Host | Class | Runs |
|---|---|---|
| `laptop` | desktop | niri, quickshell, zen; dev tooling, libvirt and docker |
| `node1` | server | caddy, authelia, AdGuard Home, restic, syncthing |

## Branches

| Branch | Contents                                             |
|---|------------------------------------------------------|
| `main` | The config only, without my custom hosts added to it |
| `dev` | My personal version                                  |

Clone `main` unless you specifically want to read my host definitions. The
installer creates your own either way.

## Install

### Local

1. Flash the NixOS ISO onto a bootable USB and boot into it 
2. Run the following commands: 

```sh
# Clone the repo; pick whichever branch you want:
git clone https://codeberg.org/KanyeSouth/nixos-config                    # dev (my personal config)
git clone -b main https://codeberg.org/KanyeSouth/nixos-config            # main (config only)
cd nixos-config

# Run the installer and follow its instructions
./install.sh
```

### Remote
> [!WARNING]
> nixos-anywhere requires a distro to be already installed on the remote target
> and the ability to ssh into it

```sh
# Clone the repo; pick whichever branch you want:
git clone https://codeberg.org/KanyeSouth/nixos-config                    # dev (my personal config)
git clone -b main https://codeberg.org/KanyeSouth/nixos-config            # main (config only)
cd nixos-config

# Run the installer and follow its instructions
./install.sh --remote
```

The installer asks for hostname, class, addons, user, locale, hardware, disk and
optional wifi, then partitions, generates SSH and age keys, writes the host
files and runs `nixos-install` (or `nixos-anywhere`). Everything it writes is shown for review before
anything destructive happens.

## Structure

```
nixos-config/
├── docs/
├── lib/
├── hosts/
│   ├── cluster.json        # relationship of each machine in this config
│   └── <host>/
│       ├── home/           # optional; desktop only; dotfiles mirrored into /home/<user>
│       │   ├── .config/
│       │   ├── .zshrc
│       │   ...
│       ├── host.json       # describes this host machine
│       ├── secrets.json
│       ├── storage.nix     # optional; configure additional storage drives
│       ├── hardware.nix    # nix generated 
│       └── disko.nix       # configures boot drive
├── modules/                # bundles of preconfigured modules/programs for <class> and <addons>
│   ├── desktop/
│   ├── server/
│   ...
└── flake.nix               # maps the hosts
```

## Docs

| Document | Covers |
|---|---|
| [architecture](docs/architecture.md) | how modules become a host |
| [hosts](docs/hosts.md) | `host.json`, `cluster.json`, adding a machine |
| [system](docs/system.md) | secrets, network profiles, impermanence |
| [server](docs/server.md) | the service descriptor, storage, backups |
| [gateway](docs/gateway.md) | proxy, authentication, dns |
| [virt](docs/virt.md) | guests and containers |
| [keybinds](docs/keybinds.md) | desktop bindings |