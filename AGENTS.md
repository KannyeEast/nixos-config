# AGENTS.md — nixos-config

## What this repo is
- Opinionated, single-source-of-truth NixOS config. Not a customization framework.
- Host-driven, multi-host, **single-user** (multi-user is out of scope — never add structural support for it; `username` is a single value, never a `users` set).
- Dendritic / feature-first pattern: `flake-parts` + `import-tree` auto-import everything under `hosts/` and `modules/`. Organize by what things *do* (`desktop`, `dev`, `server`), never by where they run.

## Architecture
- **Flake**: `flake.nix` only declares inputs and calls `flake-parts.mkFlake` with `import-tree [ ./hosts ./modules ]`. All inputs set `inputs.nixpkgs.follows = "nixpkgs"`. Group inputs with comment headers (`# Core`, `# Profiles`, etc.).
- **Every `.nix` file is a flake-parts module** exporting into `flake.modules.nixos.<name>` or `flake.modules.homeManager.<name>`. Names are flat camelCase at exactly two levels (`nixos.browserContainers`, never `nixos.browser.containers` — a third level silently corrupts the module merge).
- **Home-manager modules** (anything touching `home.*`, `xdg.*`, or HM `programs.*`) register under `flake.modules.homeManager.*` and enter the system ONLY via `home-manager.sharedModules` (or `users.<name>.imports`) — never via a NixOS `imports` list.
- **One concern per file.** New feature = new file under `modules/<area>/`, auto-imported — never edit a central import list.
- **Aggregator modules** (`system.nix`, `base.nix`, `hardware.nix`) import their sibling leaf modules; hosts import aggregators, not leaves.

## Hosts: host.json is the source of truth
`hosts/<name>/` contains:
- `host.json` — written by the installer, read by everything. Loaded via `builtins.fromJSON (builtins.readFile ./host.json)` and passed to all modules as the `host` specialArg. Must be git-added or flakes won't see it.
- `default.nix` — builds `flake.nixosConfigurations.${hostname}` with `specialArgs = { inherit inputs host; }`.
- `hardware.nix` — `"${hostname}Hardware"` module (generated `fileSystems`/initrd; regenerate with `nixos-generate-config --show-hardware-config` on the machine, never hand-copy UUIDs).
- `profile.nix` — `"${hostname}Configuration"`: imports aggregators, sets `profile.*` values.
- `dotfiles/` — raw config files symlinked into `~/.config` (hot-editable, no rebuild).

### host.json schema
```json
{
    "hostname": "zephyrus",
    "system": "x86_64-linux",
    "username": "user",
    "roles": [ "base", "desktop" ],
    "hardware": {
        "platform": "laptop",
        "gpu": [ "nvidia", "intel" ],
        "gpuArchitecture": "ada-lovelace",
        "modules": [ "asus-zephyrus-gu605my" ]
    },
    "locale": { "timeZone": "...", "localeDefault": "...", "localeExtra": "..." },
    "secrets": { "publicKeys": [ "..." ], "ageFiles": [ "..." ] }
}
```
- A field earns its place ONLY if (a) Nix can't compute it at eval time AND (b) some module reads it. Derived values (dGPU role, hybrid detection, driver flags) live in modules, not in the schema.
- **Writer boundary**: host.json is everything the installer writes (facts + identity). profile.nix is everything a human writes (taste). Never make the installer edit .nix files.
- `hardware.modules` lists nixos-hardware module names, imported via `map (m: inputs.nixos-hardware.nixosModules.${m}) (hardware.modules or [ ])`. Trust policy lives in the installer (it validates names against the live attr list); Nix imports whatever the json says.

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
        inherit (config.profile) system;    # inherit when the name maps 1:1
        hw = host.hardware;                 # plain binding on rename/default/collision
        model = host.hardware.model or null; # `or` needs a selection — inherit can't default
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
An option is warranted **only if**: **(A)** host-specific (hosts legitimately differ), **(B)** frequently changing (experimental toggles), or **(C)** convenience / installer-written / referenced in many places. Everything else: **hardcode it in its feature file.**
- **Prefer facts over options**: if the host-specific bit is derivable from host.json, derive it and delete the option (e.g. nvidia `open`/`powerManagement` derive from `gpuArchitecture` via the generation-order list; `internal.system.nvidia.enable = elem "nvidia" host.hardware.gpu`). Use `mkDefault` on derived values so a quirky host can override with raw `hardware.*` settings in profile.nix — no option ceremony.
- Several values can coexist → list the host opts into. Only one value valid at a time → no enum; hard-wire the preferred choice (bootloader = systemd-boot, one display manager).
- No dead/unused options. Delete by omission.

## Option namespaces
- `profile.*` — human-set knobs in profile.nix (`profile.system`, `profile.user`, `profile.desktop`). Always `mkOption` with `type`, `default`, `description`.
- `internal.*` — machinery, always `internal = true` (`mkEnableOption "X" // { internal = true; }`). Derived from `host` facts or `profile` values, not set directly by hosts (temporary exceptions carry a `@TODO`).

## Boundaries
- **Nix makes it work, dotfiles make it pretty.** Nix owns packages, hardware, services, and the session environment (`TERMINAL`, `XKB_DEFAULT_*`). Ricing lives in `hosts/<name>/dotfiles/` via `mkOutOfStoreSymlink` (live-editable). The interface between the two is the environment, not generated config.
- Console keymap stays hardcoded (`console.keyMap = "us"`) as fallback; xkb env vars handle everything graphical.
- Secrets: agenix today (`.age` in `secrets/`, keys/files in host.json `secrets.*`; `secrets/secrets.nix` aggregates across hosts for the agenix CLI). sops-nix migration planned. Never commit plaintext secrets; `.env` is untracked scratch.
- No long-lived divergent branches; shareable-vs-personal is solved by design, not branching.

## Naming, style, encoding
- File names: **kebab-case**. Module/variable names: **camelCase**. 4-space indent.
- Comments explain *why*; open questions are inline `# @TODO:`.
- **Files must be UTF-8, no BOM, LF line endings, no trailing NUL bytes.** The Windows editor has corrupted files before (truncation, NUL padding, UTF-16 saves). If eval fails with a bizarre parse error, check `file <path>` first. Keep `.gitattributes` with `* text=auto eol=lf`.

## Workflow
- `just check` — flake evaluates. `just test <host>` — build & run VM. `just switch <host>` — rebuild via nh. `just fmt` — nixfmt + deadnix. `just clean` — GC.
- Test in the VM (`debug` module provides the `nixosvmtest` user), then one real reboot before layering more changes — `switch` succeeding proves activation, not stage-1 boot.
- Debug tricks: `nix eval .#nixosConfigurations.<host>.config.system.build.toplevel --show-trace` for the trace `just check` hides; `options.<path>.definitionsWithLocations` in `nix repl` (`:lf .`) to find where conflicting values come from; `mkForce` is the legitimate tool against upstream modules that set plain-priority values.
- Consult `PLANNING.md` before structural changes — it's the decision record; don't re-litigate settled verdicts (no den, no multi-user, no wrapper-modules for niri).

## Reference sites
- **Options & packages**: https://mynixos.com (NixOS + home-manager options, package search — check here before claiming an option doesn't exist) · https://search.nixos.org (packages, `unstable` channel) · https://home-manager-options.extranix.com (HM options by release)
- **lib functions**: https://noogle.dev (search `lib.*` / `builtins.*` signatures)
- **Hardware**: https://github.com/NixOS/nixos-hardware (valid `hardware.modules` names)
- **niri**: https://niri-wm.github.io/niri/ (config reference, includes, nvidia quirks)
- **Zen browser flake**: https://github.com/0xc000022070/zen-browser-flake (HM module options)
