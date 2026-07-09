# modules/ — feature-first, auto-imported

Every `.nix` file here is a flake-parts module, auto-imported by import-tree. New feature = new file; no central import list exists to edit.

## Registration
- Names are **flat camelCase at exactly two levels**: `flake.modules.nixos.<name>` or `flake.modules.homeManager.<name>`. Never a third level (`nixos.browser.containers`) — it silently corrupts the module merge.
- Multiple files MAY define the *same* name; definitions merge (deferredModule). This is the preferred way to let sub-concerns contribute to an aggregate without a central import list.
- **Class rule**: anything touching `home.*`, `xdg.*`, or HM `programs.*` registers under `homeManager.*` and enters the system ONLY via `home-manager.sharedModules` (usually from a role) — never via a NixOS `imports` list. Symptom of violating this: "option home does not exist".
- HM modules read NixOS-level values (`profile.*`, `internal.*`) via `osConfig`, host facts via the `host` specialArg.

## Template
```nix
{ config, lib, ... }:                       # outer = flake-parts module
let
    inherit (config.flake.modules) nixos;   # flake-level attrs only
    inherit (lib) mkOption mkIf types;
in
{
    flake.modules.nixos.<camelCaseName> = { config, pkgs, host, ... }:
    let
        inherit (config.profile) system;    # inherit on 1:1 name match
        hw = host.hardware;                 # plain binding on rename/collision
        x = host.foo or null;               # `or` needs a selection — inherit can't default
    in
    {
        imports = [ ];
        options = { };
        config = { };
    };
}
```

## Options policy (A/B/C)
An option exists only if **(A)** hosts legitimately differ, **(B)** it changes frequently, or **(C)** it's installer-written / referenced in many places. Everything else is hardcoded in its feature file.
- **Facts over options**: derivable from host.json → derive it, delete the option (nvidia flags from `gpuArchitecture`; `internal.system.<vendor>.enable = elem "<vendor>" host.hardware.gpu`). Derived values get `mkDefault` so a host can override with raw `hardware.*` settings.
- **Delta options, not descriptions**: when per-host variation is additive, the module hardcodes the base set and exposes only `extra` / `exclude` (e.g. `profile.desktop.browser.extensions.extra`). One pair per concern, added only when two real hosts actually differ.
- Single-choice that never varies → hardcode the preferred tool (systemd-boot, sddm, zen). Single-choice that varies per host → enum from host facts.

## Namespaces
- `profile.*` — human knobs, set in a host's profile.nix. Always full `mkOption` (type, default, description).
- `internal.*` — machinery, `mkEnableOption "X" // { internal = true; }`, derived from host facts or profile values. Hosts don't set these (temporary exceptions carry `@TODO`).

## Roles (`modules/roles/`)
Roles are the only aggregators hosts consume: host.json `roles` → mkHost imports `nixos.<role>`. A role imports NixOS leaf modules and wires HM modules via `home-manager.sharedModules`. Leaf modules never import each other sideways without reason; shared plumbing goes in a role or a dedicated aggregate.

## Boundaries
- Nix owns packages, hardware, services, session env (`TERMINAL`, `XKB_DEFAULT_*`). Ricing lives in `hosts/<name>/dotfiles/` — the interface between them is the environment, not generated config.
- Secret values never pass through module options — everything rendered by Nix lands world-readable in `/nix/store`. Consume secrets as runtime paths (`config.sops.secrets.<label>.path`, `sops.placeholder` in templates). See `secrets/AGENTS.md`.
