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

## Branches

| Branch | Contents                                             |
|---|------------------------------------------------------|
| `main` | The config only, without my custom hosts added to it |
| `dev` | My personal version                                  |

Clone `main` unless you specifically want to read my host definitions. The
installer creates your own either way.

## Install

### Local install

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

### Remote install
> [!WARNING]
> nixos-anywhere requires a distro to be already installed on the remote target
> and the ability to ssh into it

1. Grab your remote target address:
```sh
ip -a 
```

```sh
# Clone the repo; pick whichever branch you want:
git clone https://codeberg.org/KanyeSouth/nixos-config                    # dev (my personal config)
git clone -b main https://codeberg.org/KanyeSouth/nixos-config            # main (config only)
cd nixos-config

# Run the installer and follow its instructions
./install.sh --remote
```

The installer asks for hostname, roles, user, locale, hardware, disk and
optional wifi, then partitions, generates SSH and age keys, writes the host
files and runs `nixos-install`. Everything it writes is shown for review before
anything destructive happens.

## Structure

```
nixos-config/
├── hosts/
│   └── <host>/
│       ├── home/           # This hosts configuration of provided modules/programs
│       │   ├── .config/
│       │   ├── .zshrc
│       │   ...
│       ├── host.json
│       ├── secrets.json
│       ├── hardware.nix
│       └── disko.nix
├── modules/                # Declare and preconfigure modules/programs
│   ├── desktop/
│   ├── server/
│   ...
└── flake.nix
```