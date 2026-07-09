# secrets/ — sops-nix (agenix remnants are legacy)

## Model
- One file per host: `secrets/<hostname>.yaml` (+ `secrets/common.yaml` for fleet-wide values). Labels stay readable, values are encrypted — that is expected and fine in a public repo.
- Recipients live in `.sops.yaml`: your personal age key (`~/.config/sops/age/keys.txt`, generated once with `age-keygen`) **plus** that host's key. A host's key is its SSH host key converted: `ssh-keyscan <host> | ssh-to-age` (or `ssh-to-age < /etc/ssh/ssh_host_ed25519_key.pub` locally). Every rule must include BOTH — host-only means you can't edit; you-only means the machine can't boot-decrypt.
- Access matrix: each host reads only its own file + common.yaml. Revoking a machine = remove its anchor from `.sops.yaml` + `sops updatekeys secrets/*.yaml`.
- The machine decrypts at activation with `sops.age.sshKeyPaths = [ "/etc/ssh/ssh_host_ed25519_key" ]`. Your personal key never appears in any Nix file.

## Iron rules
- **Never route a secret value through Nix options** — anything Nix renders lands world-readable in `/nix/store`. Consume secrets only as runtime paths (`config.sops.secrets."label".path`) or `sops.placeholder` inside `sops.templates`. This includes browser policies, pins, extension settings.
- Encrypted files must be `git add`ed (flake) — but NEVER commit plaintext. There is no such thing as a "gitignored secrets json": gitignored files are invisible to flake evaluation, so that pattern breaks eval *and* tempts plaintext on disk. Secret-but-needed-at-eval doesn't exist; redesign the consumer.
- `neededForUsers = true` for anything consumed during user creation (hashedPassword).
- Guard optional declarations with `builtins.pathExists` so a missing secrets file skips its block instead of failing eval.

## Editing
- Interactive: `sops secrets/<host>.yaml` — decrypts into $EDITOR, re-encrypts on save. Plaintext never touches disk.
- Scripted: decrypt to /tmp, modify, copy back, then **`sops -e -i`** (in-place). NEVER `sops -e x > y` shell redirects — the shell truncates the target to 0 bytes before sops runs.
- After changing recipients in `.sops.yaml`: `sops updatekeys secrets/*.yaml` (creation rules only apply automatically to newly created files).
- New keys in a yaml need a matching `sops.secrets."label"` declaration before anything can consume them — declaring is what makes the value appear under `/run/secrets/`.

## Bootstrap order for a new host
host keys exist (`ssh-keygen -A` in the target / nixos-enter) → `ssh-to-age` the pubkey → add anchor + rule to `.sops.yaml` → `updatekeys` → commit → install/rebuild. Wrong order = first boot can't decrypt the password secret.
