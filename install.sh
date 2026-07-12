#!/usr/bin/env nix-shell
#!nix-shell -i bash -p bash jq openssh ssh-to-age age sops mkpasswd nixos-install-tools git
#
# install.sh — bootstrap a host for this flake.
#
# Produces:
#   * host SSH key   -> decrypts secrets at activation (sops-nix)
#   * user SSH key   -> sops editing recipient + git signing key
#   * .sops.yaml     -> merged: new users/hosts/rules appended, existing kept
#   * secrets.yaml   -> userPassword (mkpasswd) + user private key, sops-encrypted
#   * hardware.nix   -> generated hardware config embedded in the dendritic module
#
# Re-runs are meant to be safe: existing keys are REUSED (never overwritten),
# a user key missing on disk is restored from secrets.yaml when possible,
# mismatches between disk and secrets.yaml are repaired toward the disk copy,
# and the script refuses to finish unless the host key can actually decrypt
# secrets.yaml (the lockout failure mode).
#
# Usage:
#   @TODO@TEMP: The host itself can later be declared in the script itself. For now just specify
#   sudo ./install.sh hosts/default          # on the running (installed) system
#   sudo ./install.sh hosts/default /mnt     # from the ISO, after mounting target
#
# Admin key (manual, one-time, OPTIONAL): the PUBLIC half is committed to the
# repo as id_admin.pub and used as an extra encryption recipient. The PRIVATE
# half (for editing secrets later) is brought e.g. via boot USB to
# <user home>/.config/sops/age/ — either as keys.txt (age identity) or as
# id_ed25519 (SSH key), which gets converted to keys.txt automatically.
# Override the recipient explicitly with: ADMIN_AGE=age1... ./install.sh ...
# Without an admin key, secrets are readable by the user + this host only.

set -euo pipefail

# ═══ Logging ═════════════════════════════════════════════════════════════════

log()  { echo ">> $*"; }
warn() { echo "!! $*" >&2; }
die()  { warn "$*"; exit 1; }

# ═══ sops helpers ════════════════════════════════════════════════════════════

# Run any sops command: try the caller's identities first (keys.txt /
# SOPS_AGE_KEY*), then retry with the host key as identity. Keeps the admin
# key optional — this host can always operate on its own secrets.
sops_host() {
    "$@" 2>/dev/null && return 0
    [[ -f "$HOST_KEY" ]] || return 1
    SOPS_AGE_KEY="$(ssh-to-age -private-key -i "$HOST_KEY" 2>/dev/null)" "$@"
}

# Decrypt one value from secrets.yaml; silent on failure so callers can
# branch on it.
sops_extract() {
    sops_host sops --decrypt --extract "$1" "$SECRETS" 2>/dev/null
}

# ═══ .sops.yaml helpers ══════════════════════════════════════════════════════

# insert LINE before the first line exactly matching MARKER (loud on failure)
insert_before() {
    awk -v l="$1" -v m="$2" '
        !done && $0 == m { print l; done=1 }
        { print }
        END { if (!done) exit 1 }' \
        .sops.yaml > .sops.yaml.tmp \
        || die ".sops.yaml: marker '$2' not found"
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

# ═══ Setup ═══════════════════════════════════════════════════════════════════

parse_args() {
    HOST_DIR="${1:?usage: install.sh <host-dir> [target-root]}"
    TARGET_ROOT="${2:-}"                  # empty = running system, /mnt = ISO install

    REPO_ROOT="$(git rev-parse --show-toplevel)"

    # Normalize to a clean repo-relative path — sops matches path_regex against
    # the path relative to .sops.yaml, so a trailing slash (tab completion!),
    # ./ prefix, or absolute path would bake a regex that can never match
    # ("error loading config: no matching creation rules found").
    HOST_DIR="$(realpath --relative-to="$REPO_ROOT" "$HOST_DIR")"
    [[ "$HOST_DIR" == ..* ]] && die "host dir must live inside the repo"

    cd "$REPO_ROOT"

    HOST_JSON="$HOST_DIR/host.json"
    HOSTNAME="$(jq -re .hostname "$HOST_JSON")"
    USER_NAME="$(jq -re .user.name "$HOST_JSON")"
    USER_ANCHOR="$USER_NAME"

    # Never ~ or $HOME: the invoking user is not the target user.
    USER_HOME="$TARGET_ROOT/home/$USER_NAME"
    USER_KEY="$USER_HOME/.ssh/id_$USER_NAME"
    HOST_KEY="$TARGET_ROOT/etc/ssh/ssh_host_ed25519_key"
    SECRETS="$HOST_DIR/secrets.yaml"

    ADMIN_DIR="$USER_HOME/.config/sops/age"
    ADMIN_PUB_FILE="${ADMIN_PUB_FILE:-$REPO_ROOT/id_admin.pub}"

    log "Bootstrapping host '$HOSTNAME' for user '$USER_NAME'"
    if [[ -n "$TARGET_ROOT" ]]; then
        log "Target root: $TARGET_ROOT"
    fi
}

# ═══ 1. Host key (sops-nix decryption at activation) ═════════════════════════
# NixOS generates this on first boot; when installing from the ISO it does
# not exist yet, so create it now — secrets.yaml must be encrypted to it
# BEFORE the first boot, or activation cannot decrypt the user password.

ensure_host_key() {
    if [[ -f "$HOST_KEY.pub" ]]; then
        log "Using existing host SSH key: $HOST_KEY"
    else
        log "Generating host SSH key (requires root): $HOST_KEY"
        install -d -m 755 "$(dirname "$HOST_KEY")"
        ssh-keygen -t ed25519 -N "" -C "root@$HOSTNAME" -f "$HOST_KEY"
    fi
    HOST_AGE="$(ssh-to-age < "$HOST_KEY.pub")"
    log "Host age key: $HOST_AGE"

    # Drift check: warn when .sops.yaml already pins a DIFFERENT key for this
    # host. Every secret encrypted to the old key is unreadable by this machine
    # until 'sops updatekeys' re-encrypts (step 5 does — if it can decrypt).
    [[ -f .sops.yaml ]] || return 0
    local old_age
    old_age="$(sed -nE "s/^ *- &$HOSTNAME (age1[0-9a-z]+) *$/\1/p" .sops.yaml | head -n1)"
    if [[ -n "$old_age" && "$old_age" != "$HOST_AGE" ]]; then
        warn "Host key for '$HOSTNAME' CHANGED:"
        warn "  old: $old_age"
        warn "  new: $HOST_AGE"
        warn "  secrets will be re-encrypted to the new key in step 5"
    fi
}

# ═══ 2. User key (editing recipient, git signing) ════════════════════════════
# Priority: key on disk > key stored in secrets.yaml > generate fresh.
# Restoring from secrets.yaml keeps disk / secrets.yaml / host.json in
# agreement instead of silently minting a key that mismatches the stored one.

ensure_user_key() {
    USER_KEY_GENERATED=0

    if [[ -f "$USER_KEY.pub" ]]; then
        log "Using existing user SSH key: $USER_KEY"
    elif [[ -f "$SECRETS" ]] && grep -q '^sops:' "$SECRETS" \
            && RESTORED_KEY="$(sops_extract '["userSshKey"]')" && [[ -n "$RESTORED_KEY" ]]; then
        log "Restoring user SSH key from $SECRETS"
        install -d -m 700 "$USER_HOME/.ssh"
        (umask 077; printf '%s\n' "$RESTORED_KEY" > "$USER_KEY")
        # ssh-keygen -y drops the comment; re-add the tag host.json dedupes on
        echo "$(ssh-keygen -y -f "$USER_KEY") $USER_NAME@$HOSTNAME" > "$USER_KEY.pub"
    else
        log "Generating user SSH key: $USER_KEY"
        install -d -m 700 "$USER_HOME/.ssh"
        ssh-keygen -t ed25519 -N "" -C "$USER_NAME@$HOSTNAME" -f "$USER_KEY"
        chmod 600 "$USER_KEY"
        USER_KEY_GENERATED=1
    fi

    USER_PUB="$(cat "$USER_KEY.pub")"
    USER_AGE="$(ssh-to-age < "$USER_KEY.pub")"
    log "User age key: $USER_AGE"
}

# ═══ 3. Admin key (manual, one-time, optional) ═══════════════════════════════
# Recipient resolution order:
#   1. ADMIN_AGE env var
#   2. id_admin.pub committed in the repo root (override: ADMIN_PUB_FILE=...)
#   3. age identity at <user home>/.config/sops/age/keys.txt
# NOTE: deliberately NO fallback to "first age1... key in .sops.yaml" — that
# could silently promote another host's key to admin recipient.
# Independently of the recipient: an SSH key dropped at
# <user home>/.config/sops/age/id_ed25519 (e.g. from the boot USB) is
# converted into keys.txt once, so sops can decrypt/edit later on.

resolve_admin_key() {
    if [[ -f "$ADMIN_DIR/id_ed25519" && ! -f "$ADMIN_DIR/keys.txt" ]]; then
        log "Converting admin SSH key to age identity: $ADMIN_DIR/keys.txt"
        # NOTE: fails on passphrase-protected keys — strip the passphrase on a
        # copy first: ssh-keygen -p -N "" -f <copy>
        ssh-to-age -private-key -i "$ADMIN_DIR/id_ed25519" >> "$ADMIN_DIR/keys.txt"
        chmod 600 "$ADMIN_DIR/keys.txt"
    fi

    # Seed the repo copy of the admin public key when possible
    if [[ ! -f "$ADMIN_PUB_FILE" && -f "$ADMIN_DIR/id_ed25519.pub" ]]; then
        log "Seeding $ADMIN_PUB_FILE from $ADMIN_DIR/id_ed25519.pub"
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
        log "No admin key found — continuing without one."
        log "(secrets stay readable by the user and this host only; add one"
        log " later via $ADMIN_PUB_FILE or ADMIN_AGE=age1... and re-run)"
    else
        log "Admin age key: $ADMIN_AGE"
    fi
}

# ═══ 4. .sops.yaml ═══════════════════════════════════════════════════════════
# Merge, don't overwrite: existing users/hosts/rules are preserved.
# YAML anchors must be unique per document, so anchors come from host.json:
#   user -> &<username>        host -> &<hostname>
# NOTE: the same username on two hosts therefore SHARES one anchor — the
# later install overwrites its value. Revisit once the script prompts.
# New users are inserted after the last user (before the '- &hosts:' line),
# new hosts after the last host (before 'creation_rules:'), and the rule
# block is appended at the end. Re-running with fresh keys for a known
# anchor updates its value in place.

write_sops_yaml() {
    # The merge logic depends on this exact skeleton. Hand-written or
    # placeholder layouts are backed up and recreated.
    if [[ -f .sops.yaml ]] && ! { grep -Fqx 'keys:' .sops.yaml \
            && grep -Fqx '  - &users:' .sops.yaml \
            && grep -Fqx '  - &hosts:' .sops.yaml \
            && grep -Fqx 'creation_rules:' .sops.yaml; }; then
        warn ".sops.yaml has an unknown layout — backing up to .sops.yaml.bak"
        mv .sops.yaml .sops.yaml.bak
        # Cleanup once verified (recoverable, see AGENTS.md):
        # rip .sops.yaml.bak
    fi

    if [[ ! -f .sops.yaml ]]; then
        log "Creating .sops.yaml"
        cat > .sops.yaml <<EOF
keys:
  - &users:
  - &hosts:
creation_rules:
EOF
    fi

    log "Updating .sops.yaml"
    if [[ -n "$ADMIN_AGE" ]]; then
        upsert_key "admin" "$ADMIN_AGE" "  - &hosts:"           # users block
    fi
    upsert_key "$USER_ANCHOR" "$USER_AGE"  "  - &hosts:"       # append to users block
    upsert_key "$HOSTNAME"    "$HOST_AGE"  "creation_rules:"   # append to hosts block

    if ! grep -q -- "path_regex: $HOST_DIR/secrets" .sops.yaml; then
        {
            printf '  - path_regex: %s/secrets\\.yaml$\n' "$HOST_DIR"
            printf '    key_groups:\n'
            printf '      - age:\n'
            if [[ -n "$ADMIN_AGE" ]]; then printf '          - *admin\n'; fi
            printf '          - *%s\n' "$USER_ANCHOR"
            printf '          - *%s\n' "$HOSTNAME"
        } >> .sops.yaml
    fi
}

# ═══ 5. secrets.yaml ═════════════════════════════════════════════════════════
# Own template instead of sops' default example content: write plaintext,
# then encrypt in place (creation rule matches because we cd'd to REPO_ROOT
# and use the repo-relative path).
# Only files that actually carry sops metadata are treated as existing
# secrets; anything else (placeholders) is backed up and recreated.
# NOTE: the update path (sops updatekeys) has to DECRYPT the data key, so it
# only works where a matching identity is available (admin keys.txt or the
# host key). The fresh-create path needs public keys only.

update_existing_secrets() {
    log "$SECRETS exists — updating recipients (sops updatekeys)"
    if ! sops_host sops updatekeys --yes "$SECRETS"; then
        warn "updatekeys could not decrypt $SECRETS — none of the available"
        warn "identities (admin keys.txt if any, host key) match its recipients."
        warn "Fix: bring the admin identity to $ADMIN_DIR, or recreate the"
        warn "secrets: mv $SECRETS $SECRETS.bak and re-run this script."
        exit 1
    fi

    # Keep the stored private key in agreement with the key on disk —
    # otherwise host.json authorizes one key while secrets.yaml carries
    # another (e.g. after the generate-fresh path in step 2).
    local stored_key disk_key
    stored_key="$(sops_extract '["userSshKey"]' || true)"
    disk_key="$(cat "$USER_KEY")"
    if [[ -z "$stored_key" ]]; then
        warn "Cannot read userSshKey from $SECRETS to compare against $USER_KEY"
    elif [[ "$stored_key" != "$disk_key" ]]; then
        if [[ "$USER_KEY_GENERATED" == 1 ]]; then
            log "Fresh user key generated — replacing stale userSshKey in $SECRETS"
        else
            log "userSshKey in $SECRETS differs from $USER_KEY — syncing to disk copy"
        fi
        sops_host sops set "$SECRETS" '["userSshKey"]' "$(jq -Rs . < "$USER_KEY")"
    fi
}

create_fresh_secrets() {
    if [[ -f "$SECRETS" ]]; then
        log "$SECRETS is not sops-encrypted — backing up to $SECRETS.bak"
        mv "$SECRETS" "$SECRETS.bak"
        # Cleanup once verified (recoverable, see AGENTS.md):
        # rip "$SECRETS.bak"
    fi

    log "Set the login password for '$USER_NAME':"
    local hash
    hash="$(mkpasswd -m sha-512)"
    {
        echo "userPassword: $hash"
        echo "userSshKey: |"
        sed 's/^/    /' "$USER_KEY"
    } > "$SECRETS"
    sops --encrypt --in-place "$SECRETS"
    log "Created and encrypted $SECRETS"
}

write_secrets() {
    if [[ -f "$SECRETS" ]] && grep -q '^sops:' "$SECRETS"; then
        update_existing_secrets
    else
        create_fresh_secrets
    fi
}

# ═══ 6. Hardware configuration ═══════════════════════════════════════════════
# Embed the generated hardware config directly into the dendritic module,
# reformatted to house style: comments stripped, imports list inlined,
# 2-space indentation doubled and nested at module depth (=> 8 spaces for
# top-level attributes), section blank lines kept.
# NOTE: re-running regenerates hardware.nix wholesale — hand edits are lost.

# stdin: nixos-generate-config output   stdout: module-body in house style
reformat_hardware_config() {
    sed -e '/^ *#/d' \
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
    | awk 'NF { found=1 } found'
}

generate_hardware_nix() {
    log "Generating hardware configuration"
    local hw_body
    hw_body="$(nixos-generate-config --show-hardware-config ${TARGET_ROOT:+--root "$TARGET_ROOT"} \
        | reformat_hardware_config)"

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
        printf '%s\n' "$hw_body"
        cat <<'EOF'
    };
}
EOF
    } > "$HOST_DIR/hardware.nix"
    log "Wrote $HOST_DIR/hardware.nix"
}

# ═══ 7. host.json (user.sshKeys list) ════════════════════════════════════════
# Upsert, not append: the user key is replaced by its comment tag
# ("<user>@<host>", set via ssh-keygen -C), so re-installs with fresh keys
# don't accumulate stale entries. All other keys (e.g. admin) are kept.

update_host_json() {
    jq --arg key "$USER_PUB" --arg tag "$USER_NAME@$HOSTNAME" \
        '.user.sshKeys = ((.user.sshKeys // [])
            | map(select(endswith(" " + $tag) | not))
            + [$key])' \
        "$HOST_JSON" > "$HOST_JSON.tmp"
    mv "$HOST_JSON.tmp" "$HOST_JSON"

    # Ensure the admin public key is authorized on this host as well
    if [[ -f "$ADMIN_PUB_FILE" ]]; then
        local admin_pub
        admin_pub="$(cat "$ADMIN_PUB_FILE")"
        jq --arg key "$admin_pub" \
            '.user.sshKeys = (.user.sshKeys
                | if index($key) then . else . + [$key] end)' \
            "$HOST_JSON" > "$HOST_JSON.tmp"
        mv "$HOST_JSON.tmp" "$HOST_JSON"
    fi
}

# ═══ 8. Sanity: the host must be able to decrypt its own secrets ═════════════
# This is the exact first-boot lockout mode (mutableUsers = false +
# undecryptable userPassword) — catch it here, not after a reboot.

verify_host_can_decrypt() {
    if SOPS_AGE_KEY="$(ssh-to-age -private-key -i "$HOST_KEY")" \
            sops --decrypt --extract '["userPassword"]' "$SECRETS" > /dev/null 2>&1; then
        log "Verified: host key decrypts $SECRETS"
    else
        warn "Host key $HOST_KEY CANNOT decrypt $SECRETS"
        warn "First boot would lock out every account (mutableUsers = false)."
        warn "Refusing to continue — check the &$HOSTNAME recipient in .sops.yaml,"
        warn "then re-run so updatekeys can re-encrypt."
        exit 1
    fi
}

# ═══ 9. Ownership — staged files belong to the target user ═══════════════════
# Everything above ran as root; hand the user's files back to the user, or
# git/sops will later refuse to work with them ("dubious ownership").
# From the ISO the user does not exist yet — NixOS assigns the first normal
# user uid 1000 / group 'users' (gid 100) on first boot, so fall back to
# numeric ids. (Single-user hosts only; a second user would not get 1000.)

fix_ownership() {
    local owner
    if [[ -z "$TARGET_ROOT" ]] && id -u "$USER_NAME" >/dev/null 2>&1; then
        owner="$USER_NAME:users"
    else
        owner="1000:100"
    fi

    chown "$owner" "$USER_HOME" 2>/dev/null || true
    chown -R "$owner" "$USER_HOME/.ssh" "$USER_HOME/.config" 2>/dev/null || true

    # The repo IS the user's config — transfer it too when it lives in their home
    case "$REPO_ROOT" in
        "$USER_HOME"/*) chown -R "$owner" "$REPO_ROOT" ;;
    esac
    log "Ownership of staged user files set to $owner"
}

# ═══ 10. Stage everything — flakes ignore untracked files ════════════════════

stage_files() {
    git add .
}

# ═══ Summary ═════════════════════════════════════════════════════════════════

print_summary() {
    cat <<EOF

>> Done. Recipients for $SECRETS:
     admin: ${ADMIN_AGE:-<none — user + host only>}   (&admin)
     user:  $USER_AGE   (&$USER_ANCHOR)
     host:  $HOST_AGE   (&$HOSTNAME)

>> Reminders:
   * The NixOS config MUST contain:
       sops.secrets.userPassword.neededForUsers = true;
       users.users.$USER_NAME.hashedPasswordFile =
           config.sops.secrets.userPassword.path;
     Without neededForUsers the hash is decrypted too late -> no login.
   * Ownership of staged files was set automatically (step 9). If git still
     complains about 'dubious ownership', build as $USER_NAME via 'nh os
     switch' (root never needs to read the repo then), or as a last resort:
       git config --global --add safe.directory <repo path>
   * Commit the staged files before building; then:
       nixos-install --flake .#$HOSTNAME   (from ISO)
       nixos-rebuild switch --flake .#$HOSTNAME   (on a running system)
EOF
}

# ═══ Main ════════════════════════════════════════════════════════════════════

main() {
    parse_args "$@"

    ensure_host_key             # 1. host identity (sops decryption at boot)
    ensure_user_key             # 2. user identity (editing, signing, ssh)
    resolve_admin_key           # 3. optional admin recipient
    write_sops_yaml             # 4. recipients + creation rules
    write_secrets               # 5. create or re-encrypt secrets.yaml
    generate_hardware_nix       # 6. hardware.nix in house style
    update_host_json            # 7. authorized keys upsert
    verify_host_can_decrypt     # 8. refuse to ship a lockout
    fix_ownership               # 9. user files belong to the user
    stage_files                 # 10. flakes ignore untracked files

    print_summary
}

main "$@"
