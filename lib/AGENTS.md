# lib/ — plain functions, not modules

## What lives here
Reusable Nix **functions** (take arguments, return values). Nothing in `lib/` is a flake-parts module, and `lib/` is deliberately **outside the import-tree roots** (`./hosts`, `./modules`) — files here are only evaluated where they are explicitly `import`ed.

That exclusion is load-bearing: if a file from here ever moves under `hosts/` or `modules/`, import-tree will auto-import it *in addition to* the explicit `import`, and duplicate definitions (e.g. two `flake.nixosConfigurations.<name>`) will conflict. Don't move these files without removing the explicit imports.

## mkHost.nix — the host assembler
Contract: `import ../../lib/mkHost.nix ./.` (called from a host's profile.nix, outer level) →
- reads `<hostDir>/host.json`,
- registers `flake.nixosConfigurations.${hostname}` with `specialArgs = { inherit inputs host; }`,
- composes modules: `"${hostname}Configuration"`, `"${hostname}Hardware"`, plus `map (role: nixos.${role}) host.roles`.

Every host goes through this function; per-host assembly logic belongs here, not in per-host files. If a new cross-host mechanism is needed (disko, impermanence wiring), extend mkHost rather than adding boilerplate to each host.

## Style
- Files here are functions: first line is the argument (`hostDir:`), not a module header.
- No `flake.modules.*` registrations from lib/ — registration is the caller's job.
- Templates/examples with placeholder syntax (`<name>`) don't belong in `.nix` files anywhere in the repo — nixfmt parses every `.nix` file during `just fmt`.
