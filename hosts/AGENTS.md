# hosts/ — one directory per machine

## Anatomy of `hosts/<name>/`
- `host.json` — **absolute essential infrastructure only**: identity + facts Nix cannot detect at eval time (hostname, system, username, roles, hardware facts, locale). Everything that is taste or tunable is a `profile.*` option set in profile.nix instead. Written by the installer, hand-edited until then. Must be `git add`ed — flakes cannot see untracked files.
- `profile.nix` — registers `flake.modules.nixos."${hostname}Configuration"` and sets `profile.*` values. Also pulls in the assembler: `imports = [ (import ../../lib/mkHost.nix ./.) ];` — this import lives at the **outer (flake-parts) level**, never inside the inner NixOS module.
- `hardware.nix` — registers `"${hostname}Hardware"`. Generated content only: regenerate with `nixos-generate-config --show-hardware-config` on the machine. Never hand-copy UUIDs between machines — stale UUIDs are an unbootable initrd (`Timed out waiting for device`).
- `dotfiles/` — raw config files symlinked into `~/.config` by the dotfiles module (`mkOutOfStoreSymlink`). Hot-editable, no rebuild. New files need `git add` + one rebuild to create the symlink.

## Rules
- The directory name is cosmetic; `host.json`'s `hostname` field is authoritative (module names, `nixosConfigurations` attr, `networking.hostName`). Keep them in sync anyway for sanity.
- Roles in host.json map to `flake.modules.nixos.<role>` via mkHost. Every listed role must exist in `modules/roles/`.
- A host.json field must have a consumer. Derived values (dGPU role, hybrid detection) belong in modules, not here.
- The repo is expected at `~/nixos-config` on the machine (dotfile symlink targets, nh). If that convention changes, it changes via the flakePath option, not by editing modules.

## Adding a host
1. `mkdir hosts/<name>` + write `host.json` (or let the installer).
2. `profile.nix` with the mkHost import + profile values; `hardware.nix` from generate-config.
3. Add the host's age recipient to `.sops.yaml` (`ssh-keyscan <host> | ssh-to-age`), `sops updatekeys secrets/*.yaml`, create `secrets/<name>.yaml`.
4. `git add hosts/<name>` before building anything.
