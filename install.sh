#!/usr/bin/env nix-shell
#!nix-shell -i bash -p bash jq openssh ssh-to-age age sops mkpasswd nixos-install-tools git
#
# Bootstrap a host for this flake:
#   * host SSH key   -> decrypts secrets at activation (sops-nix)
#   * user SSH key   -> sops editing recipient + git signing key
#   * .sops.yaml     -> merged: new users/hosts/rules appended, existing kept
#   * secrets.yaml   -> userPassword (mkpasswd) + user private key, sops-encrypted
#   * hardware.nix   -> generated hardware config embedded in the dendritic module
#
# Usage:
#   @TODO: The host itself can later be declared in the script itself. For now just specify
#   sudo ./install.sh hosts/default          # on the running (installed) system
#   sudo ./install.sh hosts/default /mnt     # from the ISO, after mounting target
#
# Admin key (manual, one-time): the PUBLIC half is committed to the repo as
# id_admin.pub and used as the encryption recipient. The PRIVATE half (for
# editing secrets later) is brought e.g. via boot USB to
# <user home>/.config/sops/age/ — either as keys.txt (age identity) or as
# id_ed25519 (SSH key), which gets converted to keys.txt automatically.
# Override the recipient explicitly with: ADMIN_AGE=age1... ./install.sh ...

set -euo pipefail

# ─── Arguments / paths ──────────────────────────────────────────────────────
HOST_DIR="${1:?usage: install.sh <host-dir> [target-root]}"
TARGET_ROOT="${2:-}"                      # empty = running system, /mnt = ISO install

REPO_ROOT="$(git rev-parse --show-toplevel)"

# Normalize to a clean repo-relative path — sops matches path_regex against
# the path relative to .sops.yaml, so a trailing slash (tab completion!),
# ./ prefix, or absolute path would bake a regex that can never match
# ("error loading config: no matching creation rules found").
HOST_DIR="$(realpath --relative-to="$REPO_ROOT" "$HOST_DIR")"
[[ "$HOST_DIR" == ..* ]] && { echo "!! host dir must live inside the repo"; exit 1; }

cd "$REPO_ROOT"

HOST_JSON="$HOST_DIR/host.json"
HOSTNAME="$(jq -re .hostname "$HOST_JSON")"
USER_NAME="$(jq -re .user.name "$HOST_JSON")"

# Never ~ or $HOME: the invoking user is not the target user.
USER_HOME="$TARGET_ROOT/home/$USER_NAME"
USER_KEY="$USER_HOME/.ssh/id_$USER_NAME"
HOST_KEY="$TARGET_ROOT/etc/ssh/ssh_host_ed25519_key"
SECRETS="$HOST_DIR/secrets.yaml"

echo ">> Bootstrapping host '$HOSTNAME' for user '$USER_NAME'"
[[ -n "$TARGET_ROOT" ]] && echo ">> Target root: $TARGET_ROOT"

# ─── 1. Host key (sops-nix decryption at activation) ────────────────────────
# NixOS generates this on first boot; when installing from the ISO it does
# not exist yet, so create it now — secrets.yaml must be encrypted to it
# BEFORE the first boot, or activation cannot decrypt the user password.
if [[ ! -f "$HOST_KEY.pub" ]]; then
    echo ">> Generating host SSH key (requires root): $HOST_KEY"
    install -d -m 755 "$(dirname "$HOST_KEY")"
    ssh-keygen -t ed25519 -N "" -C "root@$HOSTNAME" -f "$HOST_KEY"
fi
HOST_AGE="$(ssh-to-age < "$HOST_KEY.pub")"
echo ">> Host age key: $HOST_AGE"

# ─── 2. User key (editing recipient, git signing) ───────────────────────────
if [[ ! -f "$USER_KEY.pub" ]]; then
    echo ">> Generating user SSH key: $USER_KEY"
    install -d -m 700 "$USER_HOME/.ssh"
    ssh-keygen -t ed25519 -N "" -C "$USER_NAME@$HOSTNAME" -f "$USER_KEY"
    chmod 600 "$USER_KEY"
fi
USER_PUB="$(cat "$USER_KEY.pub")"
USER_AGE="$(ssh-to-age < "$USER_KEY.pub")"
echo ">> User age key: $USER_AGE"

# ─── 3. Admin key (manual, one-time) ─────────────────────────────────────────
# Recipient resolution order:
#   1. ADMIN_AGE env var
#   2. id_admin.pub committed in the repo root (override: ADMIN_PUB_FILE=...)
#   3. age identity at <user home>/.config/sops/age/keys.txt
#   4. first age1... key in an existing .sops.yaml
# Independently of the recipient: an SSH key dropped at
# <user home>/.config/sops/age/id_ed25519 (e.g. from the boot USB) is
# converted into keys.txt once, so sops can decrypt/edit later on.
ADMIN_DIR="$USER_HOME/.config/sops/age"
ADMIN_PUB_FILE="${ADMIN_PUB_FILE:-$REPO_ROOT/id_admin.pub}"

if [[ -f "$ADMIN_DIR/id_ed25519" && ! -f "$ADMIN_DIR/keys.txt" ]]; then
    echo ">> Converting admin SSH key to age identity: $ADMIN_DIR/keys.txt"
    # NOTE: fails on passphrase-protected keys — strip the passphrase on a
    # copy first: ssh-keygen -p -N "" -f <copy>
    ssh-to-age -private-key -i "$ADMIN_DIR/id_ed25519" >> "$ADMIN_DIR/keys.txt"
    chmod 600 "$ADMIN_DIR/keys.txt"
fi

# Seed the repo copy of the admin public key when possible
if [[ ! -f "$ADMIN_PUB_FILE" && -f "$ADMIN_DIR/id_ed25519.pub" ]]; then
    echo ">> Seeding $ADMIN_PUB_FILE from $ADMIN_DIR/id_ed25519.pub"
    cp "$ADMIN_DIR/id_ed25519.pub" "$ADMIN_PUB_FILE"
fi

ADMIN_AGE="${ADMIN_AGE:-}"
if [[ -z "$ADMIN_AGE" && -f "$ADMIN_PUB_FILE" ]]; then
    ADMIN_AGE="$(ssh-to-age < "$ADMIN_PUB_FILE")"
fi
if [[ -z "$ADMIN_AGE" && -f "$ADMIN_DIR/keys.txt" ]]; then
    ADMIN_AGE="$(age-keygen -y "$ADMIN_DIR/keys.txt" | head -n1)"
fi
if [[ -z "$ADMIN_AGE" ]]; then
    ADMIN_AGE="$(grep -oE 'age1[0-9a-z]{58}' .sops.yaml 2>/dev/null | head -n1 || true)"
fi

if [[ -z "$ADMIN_AGE" ]]; then
    echo "!! No admin age key found. Either:"
    echo "!!   * commit the admin public key as $ADMIN_PUB_FILE, or"
    echo "!!   * copy the admin key (id_ed25519) or keys.txt into $ADMIN_DIR/, or"
    echo "!!   * pass it explicitly: ADMIN_AGE=age1... $0 $*"
    echo "!! (Generate a fresh identity with: age-keygen -o $ADMIN_DIR/keys.txt)"
    exit 1
fi
echo ">> Admin age key: $ADMIN_AGE"

# ─── 4. .sops.yaml ───────────────────────────────────────────────────────────
# Merge, don't overwrite: existing users/hosts/rules are preserved.
# YAML anchors must be unique per document, so anchors come from host.json:
#   user -> &<username>        host -> &<hostname>
# NOTE: the same username on two hosts therefore SHARES one anchor — the
# later install overwrites its value. Revisit once the script prompts.
# New users are inserted after the last user (before the '- &hosts:' line),
# new hosts after the last host (before 'creation_rules:'), and the rule
# block is appended at the end. Re-running with fresh keys for a known
# anchor updates its value in place.
USER_ANCHOR="$USER_NAME"

# The merge logic depends on this exact skeleton. Hand-written or
# placeholder layouts are backed up and recreated.
if [[ -f .sops.yaml ]] && ! { grep -Fqx 'keys:' .sops.yaml \
        && grep -Fqx '  - &users:' .sops.yaml \
        && grep -Fqx '  - &hosts:' .sops.yaml \
        && grep -Fqx 'creation_rules:' .sops.yaml; }; then
    echo "!! .sops.yaml has an unknown layout — backing up to .sops.yaml.bak"
    mv .sops.yaml .sops.yaml.bak
fi

if [[ ! -f .sops.yaml ]]; then
    echo ">> Creating .sops.yaml"
    cat > .sops.yaml <<EOF
keys:
  - &users:
    - &admin $ADMIN_AGE
  - &hosts:
creation_rules:
EOF
fi

# insert LINE before the first line exactly matching MARKER (loud on failure)
insert_before() {
    awk -v l="$1" -v m="$2" '
        !done && $0 == m { print l; done=1 }
        { print }
        END { if (!done) exit 1 }' \
        .sops.yaml > .sops.yaml.tmp \
        || { echo "!! .sops.yaml: marker '$2' not found"; exit 1; }
    mv .sops.yaml.tmp .sops.yaml
}

# set or update "- &ANCHOR VALUE"; when absent, insert before MARKER
upsert_key() {
    local anchor="$1" value="$2" marker="$3"
    if grep -q -- "- &$anchor " .sops.yaml; then
        sed -i -E "s|(- &$anchor ).*|\1$value|" .sops.yaml
    else
        insert_before "    - &$anchor $value" "$marker"
    fi
}

echo ">> Updating .sops.yaml"
upsert_key "admin"        "$ADMIN_AGE" "  - &hosts:"       # users block
upsert_key "$USER_ANCHOR" "$USER_AGE"  "  - &hosts:"       # append to users block
upsert_key "$HOSTNAME"    "$HOST_AGE"  "creation_rules:"   # append to hosts block

if ! grep -q -- "path_regex: $HOST_DIR/secrets" .sops.yaml; then
    cat >> .sops.yaml <<EOF
  - path_regex: $HOST_DIR/secrets\.yaml\$
    key_groups:
      - age:
          - *admin
          - *$USER_ANCHOR
          - *$HOSTNAME
EOF
fi

# ─── 5. secrets.yaml ─────────────────────────────────────────────────────────
# Own template instead of sops' default example content: write plaintext,
# then encrypt in place (creation rule matches because we cd'd to REPO_ROOT
# and use the repo-relative path).
# Only files that actually carry sops metadata are treated as existing
# secrets; anything else (placeholders) is backed up and recreated.
# NOTE: the update path (sops updatekeys) has to DECRYPT the data key, so it
# only works where the admin identity is available (e.g. keys.txt in place).
# The fresh-create path needs public keys only.
if [[ -f "$SECRETS" ]] && grep -q '^sops:' "$SECRETS"; then
    echo ">> $SECRETS exists — updating recipients only (sops updatekeys)"
    sops updatekeys --yes "$SECRETS"
else
    if [[ -f "$SECRETS" ]]; then
        echo ">> $SECRETS is not sops-encrypted — backing up to $SECRETS.bak"
        mv "$SECRETS" "$SECRETS.bak"
    fi
    echo ">> Set the login password for '$USER_NAME':"
    HASH="$(mkpasswd -m sha-512)"
    {
        echo "userPassword: $HASH"
        echo "userSshKey: |"
        sed 's/^/    /' "$USER_KEY"
    } > "$SECRETS"
    sops --encrypt --in-place "$SECRETS"
    echo ">> Created and encrypted $SECRETS"
fi

# ─── 6. Hardware configuration ───────────────────────────────────────────────
# Embed the generated hardware config directly into the dendritic module,
# reformatted to house style: comments stripped, imports list inlined,
# 2-space indentation doubled and nested at module depth (=> 8 spaces for
# top-level attributes), section blank lines kept.
# NOTE: re-running regenerates hardware.nix wholesale — hand edits are lost.
echo ">> Generating hardware configuration"
HW_RAW="$(nixos-generate-config --show-hardware-config ${TARGET_ROOT:+--root "$TARGET_ROOT"})"

HW_BODY="$(printf '%s\n' "$HW_RAW" \
    | sed -e '/^ *#/d' \
          -e '/^{ config, lib, pkgs, modulesPath, \.\.\. }:$/d' \
          -e '/^{$/d' -e '/^}$/d' \
    | awk '
        # Normalize the generated "hanging" style to house style:
        #   name =            name = {
        #     { a;      ->      a;
        #       b;              b;
        #     };              };
        # Works for { } and [ ] alike (imports, fileSystems, swapDevices, ...).
        BEGIN { sp = "                                                  " }
        pend != "" {
            n = match($0, /[^ ]/); ind = n - 1
            ch = substr($0, n, 1)
            if (ch == "{" || ch == "[") {
                print pend " " ch
                rest = substr($0, n + 1)
                sub(/^ +/, "", rest)
                if (length(rest) > 0) print substr(sp, 1, ind) rest
                inblk = 1; blkind = ind
                pend = ""
                next
            }
            print pend
            pend = ""
        }
        inblk == 1 {
            n = match($0, /[^ ]/); ind = n - 1
            if ($0 ~ /^ *[}\]];$/ && ind == blkind) {
                print substr(sp, 1, ind - 2) substr($0, n)
                inblk = 0
                next
            }
            print substr($0, 3)
            next
        }
        /=$/ { pend = $0; next }
        { print }' \
    | sed -E -e 's/^( +)/\1\1/' -e 's/^(.)/    \1/' \
    | cat -s \
    | awk 'NF { found=1 } found')"

{
cat <<'EOF'
{ ... }:
let
    inherit (builtins.fromJSON (builtins.readFile ./host.json)) hostname;
in
{
    flake.modules.nixos."${hostname}Hardware" = { config, lib, pkgs, modulesPath, ... }:
    {
EOF
printf '%s\n' "$HW_BODY"
cat <<'EOF'
    };
}
EOF
} > "$HOST_DIR/hardware.nix"
echo ">> Wrote $HOST_DIR/hardware.nix"

# ─── 7. Update host.json with the new user public key ───────────────────────
jq --arg key "$USER_PUB" '.user.sshKey = $key' "$HOST_JSON" > "$HOST_JSON.tmp"
mv "$HOST_JSON.tmp" "$HOST_JSON"

# ─── 8. Stage everything — flakes ignore untracked files ────────────────────
git add .

# ─── Summary ─────────────────────────────────────────────────────────────────
cat <<EOF

>> Done. Recipients for $SECRETS:
     admin: $ADMIN_AGE   (&admin)
     user:  $USER_AGE   (&$USER_ANCHOR)
     host:  $HOST_AGE   (&$HOSTNAME)

>> Reminders:
   * The NixOS config MUST contain:
       sops.secrets.userPassword.neededForUsers = true;
       users.users.$USER_NAME.hashedPasswordFile =
           config.sops.secrets.userPassword.path;
     Without neededForUsers the hash is decrypted too late -> no login.
   * After the first boot, fix ownership of the staged user files:
       chown -R $USER_NAME:users /home/$USER_NAME/.ssh /home/$USER_NAME/.config
   * Commit the staged files before building; then:
       nixos-install --flake .#$HOSTNAME   (from ISO)
       nixos-rebuild switch --flake .#$HOSTNAME   (on a running system)
EOF