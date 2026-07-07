# AGENTS.md — nixos-config

## What this repo is
- Opinionated, single-source-of-truth NixOS config. Not a customization framework.
- Host-driven, multi-host, **single-user** (multi-user is out of scope — never add structural support for it; `username` is a single value, never a `users` set).
- Dendritic / feature-first pattern: `flake-parts` + `import-tree` auto-import everything under `hosts/` and `modules/`. Organize by what things *do* (`desktop`, `dev`, `server`), never by where they run.

## Architecture
- **Flake**: `flake.nix` only declares inputs and calls `flake-parts.mkFlake` with `import-tree [ ./hosts ./modules ]`. All inputs set `inputs.nixpkgs.follows = "nixpkgs"`. Group inputs with comment headers (`# Core`, `# Profiles`, etc.).
- **Every `.nix` file is a flake-parts module** exporting into `flake.modules.nixos.<name>` (or `flake.modules.homeManager.<name>` for HM-only concerns like the browser).
- **One concern per file.** Bundle only tightly-coupled settings. New feature = new file under `modules/<area>/`, auto-imported — never edit a central import list.
- **Hosts** (`hosts/<name>/`): `_host.nix` (plain attrset: hostname, system, publicKeys, ageFiles, hardwareModel), `default.nix` (builds `flake.nixosConfigurations.${hostname}` with `specialArgs = { inherit inputs host; }`), `hardware.nix` (`"${hostname}Hardware"` module), `profile.nix` (`"${hostname}Configuration"` — sets `profile.*` values and imports modules).
- **Aggregator modules** (`system.nix`, `base.nix`, `hardware.nix`) import their sibling leaf modules; hosts import aggregators, not leaves.

## Module template (follow exactly)
```nix
{ config, lib, ... }:                       # Outer = flake-parts module
let
    inherit (config.flake.modules) nixos;   # Only flake-level attrs at outer level
    inherit (lib) mkOption mkIf types;      # Inherit lib helpers, don't repeat lib. everywhere
in
{
    flake.modules.nixos.<camelCaseName> = { config, pkgs, host, ... }:
    let
        inherit (config.profile) system;    # Reference custom options via inherit
    in
    {
        imports = [ ... ];
        options = { ... };
        config = { ... };
    };
}
```
- Keep the `imports` / `options` / `config` block order, even when a section is empty.
- Gate optional features with `config = mkIf <internal>.enable { ... };`.

## Options policy (A/B/C test — the most important rule)
An option is warranted **only if**: **(A)** host-specific (hosts legitimately differ), **(B)** frequently changing (experimental toggles), or **(C)** convenience / referenced in many places (hostname, locale, username). Everything else: **hardcode it in its feature file.**
- Several values can coexist → list the host opts into (e.g. `hardware = [ "nvidia" "intel" ]`).
- Only one value valid at a time → **no enum**; hard-wire the preferred choice (bootloader = systemd-boot, one display manager). Exception: single-choice that varies per host keeps an enum (e.g. gpu vendor).
- No dead/unused options. Extensible pattern ≠ dead code. Delete by omission.

## Option namespaces
- `profile.*` — user-facing knobs set by hosts (`profile.system`, `profile.user`, `profile.desktop`). Always `mkOption` with `type`, `default`, `description`.
- `internal.*` — machinery, always marked `internal = true` (e.g. `mkEnableOption "X" // { internal = true; }`). Enable flags derived from `profile` values (e.g. `internal.system.nvidia.enable = elem "nvidia" system.hardware`), not set directly by hosts (temporary exceptions carry a `@TODO`).

## Naming & style
- File names: **kebab-case**. Module/variable names: **camelCase**.
- 4-space indentation.
- Prefer `inherit` over dotted paths; use a plain variable only on namespace collision (e.g. `iNvidia = config.internal.system.nvidia;`).
- Comments explain *why* (hardware caveats, upstream links). Open questions are inline `# @TODO:` comments — keep them, add them for known compromises.
- Nvidia: open drivers; unfree allowed globally.

## Boundaries
- **Ricing lives in dotfiles, not Nix** (`mkOutOfStoreSymlink` so edits don't need rebuilds). Infrastructure lives in Nix.
- Secrets: agenix (`.age` files in `secrets/`, keys/files declared per-host in `_host.nix`; `secrets/secrets.nix` derives its mapping from all hosts). Migration to sops-nix planned. Never commit plaintext secrets.
- No long-lived divergent branches; shareable-vs-personal is solved by design (generic names, secrets), not branching.

## Workflow
- `just check` — validate flake evaluates. `just test` — build & run VM. `just switch` — rebuild (nh). `just fmt` — nixfmt + deadnix.
- Test in the VM (`debug` module provides the `nixosvmtest` user) before switching.
- Consult `PLANNING.md` before structural changes — it's the decision record; don't re-litigate settled verdicts (e.g. no den, no multi-user).