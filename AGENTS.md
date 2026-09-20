---
name: nixos-config
description: Multi-host NixOS configuration built from flake-parts modules. Assist with module authoring, host definitions and service wiring.
---

# AGENTS.md

## Role

You are a NixOS module author working in an established codebase with a
deliberate structure.

**Explain, then act.** State what you found and what you intend to change
before editing. Stop for confirmation on anything beyond a single obvious fix.
Do not bundle unrequested improvements into a change.

When something in this repository looks wrong, assume it is deliberate and say
so rather than fixing it. Most of it is.

## Stack

| Component | Version / channel |
|---|---|
| nixpkgs | `nixos-unstable` |
| flake-parts | `hercules-ci/flake-parts`, with its `modules` flakeModule |
| import-tree | imports every `.nix` under `modules/` |
| home-manager, sops-nix, disko, impermanence, nixos-hardware | all `follows` nixpkgs |
| formatter | `nixfmt` |
| task runner | `just` |
| activation | `nh` |


```
flake.nix          maps mkHost over every valid host
lib/               mkHost, validHosts, mkBtrfsRaid
hosts/<name>/      host.json, secrets.json, disko.nix, hardware.nix
modules/<bundle>/  one concern per file
docs/              architecture, hosts, system, server, gateway, virt
```

Read [`docs/architecture.md`](docs/architecture.md) before changing structure.
Modules merge across files; nothing is local.

## Commands

Use nix directly. The `just` recipes exist for the user's own workflow and wrap
these with extra steps you do not want.

```sh
# make new files visible to the flake — see below
git add --intent-to-add .

# evaluate every host; the verification bar for a change
nix flake check

# evaluate one option, to check a value rather than the whole tree
nix eval .#nixosConfigurations.laptop.config.services.openssh.enable

# build a host without activating it
nix build .#nixosConfigurations.node1.config.system.build.toplevel

# format; the flake sets nixfmt as its formatter
nix fmt
```

`nix flake check` passing is what "done" means. It evaluates both hosts and
catches type errors, missing options and bad references. It does not catch a
wrong PCI address, a broken unit, or a package that fails to build — `nix build`
does, and is worth it when a change touches packages rather than options.

Never claim a change works without one of them. Option names move between
nixpkgs releases and this flake tracks unstable.

Two things that will waste your time otherwise:

- **Flakes ignore untracked files.** A new module is invisible to evaluation
  until git knows about it. `git add --intent-to-add .` is the one git command
  you may run, and it is often the reason a new file "does nothing".
- The repository uses submodules. Where their content matters, evaluate
  `git+file://$PWD?submodules=1` rather than `.`.

## Standards

Module skeleton. `lib` comes in at the outer level, host data at the inner:

```nix
{ lib, ... }:
let
  inherit (lib)
    mkIf
    ;
in
{
  flake.modules.nixos.<bundle> =
    { config, host, ... }:
    let
      # anything derived from this host
    in
    {
      config = mkIf (host.class == "desktop") {
        # ...
      };
    };
}
```

Errors are `throw`, never `assert`, shaped `<file or host>: <what is wrong>`:

```nix
domain = cluster.domain or (throw "gateway: cluster.json defines no domain");
```

`mkIf` and `//` do not compose. `mkIf` returns
`{ _type = "if"; condition; content; }`, so merging onto it adds a key the
module system ignores and the definition disappears silently:

```nix
config = mkIf cond { ... } // optionalAttrs other { ... };   # broken
config = mkIf cond ({ ... } // optionalAttrs other { ... }); # correct
```

`internal.services` is declared only in `flake.modules.nixos.server`. On a
desktop the option does not exist, and `mkIf` still typechecks its contents, so
a module running on both classes uses `optionalAttrs`:

```nix
// optionalAttrs (host.class == "server") {
  internal.services.sync = { route.port = 8384; };
}
```

A default is correct when absence has a correct answer. When absence means
"unknown", throw — a wrong value evaluates fine and fails far from the cause:

```nix
hardware.modules or [ ]        # absent means none
busIds ? nvidia                # absent means unknown; do not invent one
```

Other rules:

- Module names are generic and swappable: `vpn.nix` not `tailscale.nix`,
  `dns.nix` not `adguard.nix`. `lib/` helpers are `mk*`.
- One concern per file. A new concern is a new file in the right bundle.
- Comments explain *why*, next to the code. `docs/` explains how parts relate.
  Never duplicate one into the other.
- `utils` is a module argument, not part of `lib`.
- systemd `Environment=` does not expand shell variables; use specifiers, `%t`
  is `XDG_RUNTIME_DIR` for user units.
- `DynamicUser` services keep state in `/var/lib/private/<name>`; persist that
  path, not the public one.
- Upstream NixOS options can be declared outside a `mkIf` while the thing they
  control is built inside it. Setting such an option with the gate off
  typechecks and does nothing — `virtualisation.docker.autoPrune` is the live
  example.

## Boundaries

### Always

- Run `nix flake check path:.` before reporting a change as working.
- Run `nix fmt` before finishing.
- Name the file and option you changed.
- Say when a change is unverified and why.

### Ask first

- **Anything under `hosts/`** — `host.json`, `cluster.json`, `disko.nix`,
  `storage.nix`, `hardware.nix`.
- **Secrets** — `secrets.json`, `.sops.yaml`, recipients, key paths.
- **New flake inputs** — each is a maintenance and supply-chain commitment.
- **Structural moves** — creating or renaming a bundle, moving files between
  bundles.

### Never

- **Delete anything.** No removing files, directories or whole blocks of
  config, and no renaming or moving — a rename is a delete plus a create. If
  something should go, say which path and why, and leave it. The user deletes.
- **Use git beyond `git add --intent-to-add`.** That one command is allowed,
  and only so evaluation can see new files. No staging, committing, pushing,
  pulling, branching, checking out, stashing or rewriting history. The user
  does all of it.
- **Run `disko` against an existing host.** It reformats disks.
- **Revert these without being asked.** Each is a decision, and each looks like
  a bug:

  | Setting | Why it looks wrong |
  |---|---|
  | `PasswordAuthentication = true` | reads as a hardening miss; it is deliberate |
  | `openssh.openFirewall = true` | ssh is deliberately not tailnet-only, to avoid lockout |
  | `defaultSopsFormat = "yaml"` on `.json` | sops-nix's json parser fails on these files |
  | `validateSopsFiles = false` | follows from the line above |
  | `docker.enable = mkForce false` | rootless is the point; `docker` group is root-equivalent |
  | `onShutdown = "shutdown"` | `suspend` makes an unrestorable state file when virtiofs is attached |
  | the proton restic repository path | renaming it loses backup history |
