#!/usr/bin/env bash

#
# installer.sh - bootstrap a host for this flake
#

set -Eeuo pipefail

# ── state ────────────────────────────────────────────────────────────────
# flags
METHOD="local"
VERBOSE=false
TARGET_ROOT=""

# host.json fields
HOSTNAME=""
SYSTEM=""
REPO_ROOT=""
ROLES=""
ADDONS=()
USERNAME=""
USEREMAIL=""
GPU=()
HW_MODULES=()
TIMEZONE=""
LOCALE=""
LOCALE_EXTRA=""

# Secrets / keys
KEYS_DIR=""
HOST_KEY_DIR="/persistent/etc/ssh"
HOST_KEY_FILE=""
HOST_AGE=""
USER_AGE=""
USER_PUB=""
HOST_ANCHOR=""
USER_ANCHOR=""
SECRETS=""
HOST_DIR=""
WIFI='{}'

# Dotfiles
DOTFILES_SRC=""

# ── palette ──────────────────────────────────────────────────────────────
FG="#c6c8d1"
MUTED="#6c7086"
CURSOR="#7aa2f7"
ACCENT="#9ece6a"
BASE="#1a1b26"

# ── gum theme ────────────────────────────────────────────────────────────
export GUM_INPUT_PROMPT="  "
export GUM_INPUT_WIDTH="60"
export GUM_INPUT_CURSOR_FOREGROUND="$CURSOR"
export GUM_INPUT_PROMPT_FOREGROUND="$FG"
export GUM_INPUT_HEADER_FOREGROUND="$FG"
export GUM_INPUT_PLACEHOLDER_FOREGROUND="$MUTED"

export GUM_CHOOSE_CURSOR="→ "
export GUM_CHOOSE_HEADER_FOREGROUND="$FG"
export GUM_CHOOSE_CURSOR_FOREGROUND="$CURSOR"
export GUM_CHOOSE_SELECTED_FOREGROUND="$ACCENT"

export GUM_FILTER_INDICATOR="→"
export GUM_FILTER_HEADER_FOREGROUND="$FG"
export GUM_FILTER_INDICATOR_FOREGROUND="$CURSOR"
export GUM_FILTER_MATCH_FOREGROUND="$ACCENT"
export GUM_FILTER_PLACEHOLDER_FOREGROUND="$MUTED"
export GUM_FILTER_PROMPT_FOREGROUND="$FG"

export GUM_CONFIRM_PROMPT_FOREGROUND="$FG"
export GUM_CONFIRM_SELECTED_BACKGROUND="$CURSOR"
export GUM_CONFIRM_SELECTED_FOREGROUND="$BASE"
export GUM_CONFIRM_UNSELECTED_FOREGROUND="$MUTED"

export GUM_SPIN_SPINNER_FOREGROUND="$CURSOR"
export GUM_FILE_HEADER_FOREGROUND="$FG"
export GUM_FILE_CURSOR_FOREGROUND="$CURSOR"
export GUM_FILE_DIRECTORY_FOREGROUND="$FG"

# ── logging ──────────────────────────────────────────────────────────────
logInfo() { gum log --level info "$*"; }
logWarn() { gum log --level warn "$*"; }
logError() { gum log --level error "$*"; }
logDebug() { gum log --level debug "$*"; }

die() { logError "$1"; exit "${2:-1}"; }

run() {
    logDebug "\$ $*"
    if [[ $VERBOSE == true ]]; then "$@"; return; fi

    # Spinner while the command runs; --show-error prints the captured output
    # only if it fails. Note: gum spin execs the command directly, so it can't
    # call shell functions (e.g. gitRepo) — pass real binaries.
    gum spin --title "$*" --show-error -- "$@"
}

# ── traps ────────────────────────────────────────────────────────────────
trapError() {
    local code=$? cmd=$BASH_COMMAND line=${BASH_LINENO[0]} fn=${FUNCNAME[1]:-main}
    logError "'$cmd' failed (exit $code) at $fn():$line"
    exit "$code"
}
trap trapError ERR

cleanup() {
    [[ -n ${KEYS_DIR:-} && -d ${KEYS_DIR:-} ]] && rm -rf "$KEYS_DIR"
    printf '\033[?25h' >&2
}
trap cleanup EXIT

# ── flags ────────────────────────────────────────────────────────────────
showFlags() {
    cat <<EOF
Usage: sudo ./installer.sh [OPTIONS]

Options:
      --iso               Install from an ISO. This will wipe the target disk
  -v, --verbose           Show every command and its output
  -h, --help              This message
EOF
}

parseArgs() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --iso)
                METHOD="iso"
                shift ;;
            -v|--verbose) VERBOSE=true; shift ;;
            -h|--help) showFlags; exit 0 ;;
            *) printf 'Unknown option: %s\n' "$1" >&2; showFlags; exit 1 ;;
        esac
    done
}

# ── shell packages ─────────────────────────────────────────────
declare -A MODULE_PKGS=(
    [base]="gum git jq"
    [locales]="glibcLocales"
    [secrets]="age mkpasswd openssh sops ssh-to-age"
    [iso]="nixos-install-tools disko"
)

# ── nix-shell ────────────────────────────────────────────────────────────
# Enter nix-shell with install method depending packages
shell() {
    if [[ -z ${IN_NIX_SHELL:-} ]]; then
        MODULES=("base" "secrets" "locales")
        case "$METHOD" in
            local) : ;;
            iso) MODULES+=("iso") ;;
        esac
    
        pkgs=""
        for mod in "${MODULES[@]}"; do
            pkgs+=" ${MODULE_PKGS[$mod]}"
        done
    
        printf 'Fetching dependencies (%s)...\n' "$METHOD"
        exec nix-shell -p $pkgs \
                    --run "INSTALLER_METHOD=$METHOD $(printf '%q ' bash "$0" "$@")"
    fi
}

# ── helpers ──────────────────────────────────────────────────────────────
gitRepo() { git -c safe.directory='*' "$@"; }

# ── gum wrappers ──────────────────────────────────────────
formHeader() {
    gum style --bold --foreground="$FG" \
        --border=rounded --border-foreground="$MUTED" \
        --padding="0 2" --margin="1 0" "$*"
}

formInput() {
    local __var="$1" label="$2" placeholder="${4:-${3:-$2}}" value
    while :; do
        value=$(gum input --header="$label" --placeholder="$placeholder") || die "Cancelled"
        [[ -n $value ]] && break
        logWarn "$label cannot be empty"
    done
    printf -v "$__var" '%s' "$value"
}

formInputOpt() {
    local __var="$1" label="$2" placeholder="${3:-$2}" value
    value=$(gum input --header="$label" --placeholder="$placeholder") || true
    printf -v "$__var" '%s' "$value"
}

formPassword() {
    local __var="$1" label="$2" confirm="${3:-true}" minlen="${4:-8}" pw pw2
    while :; do
        pw=$(gum input --password --header="$label" --placeholder="$label") || die "Cancelled"
        (( ${#pw} >= minlen )) || { logWarn "Min $minlen characters"; continue; }
        [[ $confirm == true ]] || break
        pw2=$(gum input --password --header="Repeat $label" --placeholder="Repeat $label") || die "Cancelled"
        [[ $pw == "$pw2" ]] && break
        logWarn "Mismatch — try again"
    done
    printf -v "$__var" '%s' "$pw"
}

formChoose() {
    local __var="$1" label="$2"; shift 2
    local selected
    selected=$(gum choose --header="$label" --selected="$1" --height=15 "$@") || die "Cancelled"
    printf -v "$__var" '%s' "$selected"
}

formMulti() {
    local __var="$1" label="$2"; shift 2
    local selected
    selected=$(gum choose --no-limit --header="$label" --height=15 "$@") || true
    local -n __ref="$__var"
    [[ -n $selected ]] && mapfile -t __ref <<< "$selected" || __ref=()
}

# formConfirm LABEL [DEFAULT] — returns 0 for yes, 1 for no
formConfirm() {
    local label="$1" default="${2:-n}"
    case "$default" in
        y|yes|1) default=true ;;
        n|no|0) default=false ;;
        *) default=false ;;
    esac
    gum confirm --default="$default" "$label"
}

# formFilter VAR LABEL OPTIONS [PLACEHOLDER]
formFilter() {
    local __var="$1" label="$2" options="$3" placeholder="${4:-$2}" selected
    [[ -n $options ]] || return 1
    selected=$(gum filter \
        --header="$label" \
        --height=15 \
        --placeholder="$placeholder" <<< "$options") || die "Cancelled"
    printf -v "$__var" '%s' "$selected"
}
# ── nixos-hardware module list ───────────────────────────────────────────
# Queries the flake input for all available nixosModules, returns them
# as nixos-hardware paths (e.g. "framework/13/common", "lenovo/thinkpad/x220")
listNixosHardwareModules() {
    local rev ref="github:NixOS/nixos-hardware"
    rev="$(jq -r '.nodes["nixos-hardware"].locked.rev // empty' "$REPO_ROOT/flake.lock" 2>/dev/null || true)"
    [[ -n $rev ]] && ref="$ref/$rev"

    local args=("$ref#nixosModules"
        --json --apply builtins.attrNames
        --extra-experimental-features 'nix-command flakes')

    local json="" err
    err="$(mktemp)"

    if ! json="$(timeout 120 nix eval "${args[@]}" 2>"$err")"; then
        logDebug "nix eval failed, retrying with --refresh: $(cat "$err")"
        if ! json="$(timeout 120 nix eval "${args[@]}" --refresh 2>"$err")"; then
            logWarn "Could not fetch nixos-hardware modules"
            logDebug "$(cat "$err")"
            rm -f "$err"
            return 1
        fi
    fi
    rm -f "$err"

    jq -r '.[]' <<< "$json" | sort
}

# ── timezone list ──────────────────────────────────────────────────────────
listSupportedTimezones() {
    local zones=""
    zones=$(timedatectl list-timezones 2>/dev/null || true)

    if [[ -z $zones ]]; then
        zones=$(find /usr/share/zoneinfo -type f -printf '%P\n' 2>/dev/null \
            | grep -v -E '^(posix|right|Etc)/' | sort || true)
    fi

    if [[ -z $zones ]]; then
        local tzdir
        tzdir=$(nix-build --no-out-link '<nixpkgs>' -A tzdata 2>/dev/null || true)
        if [[ -n $tzdir ]]; then
            zones=$(find "$tzdir/share/zoneinfo" -type f -printf '%P\n' 2>/dev/null \
                | grep -v -E '^(posix|right|Etc)/' | sort || true)
        fi
    fi

    printf '%s\n' "$zones"
}

# ── locale list ──────────────────────────────────────────────────────────
listSupportedLocales() {
    command -v locale &>/dev/null || return 1
    locale -a 2>/dev/null \
        | grep -iE '\.utf-?8$' \
        | sed -E 's/\.utf-?8$/.UTF-8/I' \
        | sort -u
}

# ── disk list ──────────────────────────────────────────────────────────
listDisks() {
    lsblk -dno NAME,SIZE,MODEL -e 7,11 2>/dev/null | awk 'NF'
}

# ── validation helpers ───────────────────────────────────────────────────
# validateHostname — loops formInput until the hostname passes regex + uniqueness
validateHostname() {
    while :; do
        formInput HOSTNAME "Hostname" "nixos" "my-nixos"
        if [[ ! $HOSTNAME =~ ^[a-z][a-z0-9-]{0,62}$ ]]; then
            logWarn "Lowercase letters, digits, and hyphens only"
            continue
        fi
        if [[ -d $REPO_ROOT/hosts/$HOSTNAME ]]; then
            logWarn "hosts/$HOSTNAME already exists"
            continue
        fi
        break
    done
}

# validateUsername — loops formInput until the username passes regex
validateUsername() {
    while :; do
        formInput USERNAME "Username" "$(whoami)" "login name"
        [[ $USERNAME =~ ^[a-z_][a-z0-9_-]{0,31}$ ]] && break
        logWarn "Lowercase letters, digits, hyphens, underscores; start with letter or underscore"
    done
}

# ── gather form ──────────────────────────────────────────────────────────
gatherForm() {

    while :; do
        # ── Identity ──────────────────────────────────────────────────
        formHeader "Identity"

        validateHostname
        formChoose SYSTEM "Architecture" "x86_64-linux" "aarch64-linux"

        # ── Roles ─────────────────────────────────────────────────────
        formHeader "Role"
        formChoose ROLE "Primary role" "desktop" "server"
        ADDONS=()
        if [[ $ROLE == "desktop" ]]; then
            formMulti ADDONS "Add-ons (space to toggle)" "dev"
        fi

        # ── User ──────────────────────────────────────────────────────
        formHeader "User"

        validateUsername
        formInputOpt USEREMAIL "Email" "$USERNAME@$HOSTNAME"

        # ── Locale ────────────────────────────────────────────────────
        formHeader "Locale"
        
        formFilter TIMEZONE "Timezone" "$(listSupportedTimezones)" "e.g. America/New_York, Europe/London..." \
            || die "No timezones found"

        formFilter LOCALE "Default locale" "$(listSupportedLocales)" "e.g. en_US.UTF-8, de_DE.UTF-8..." \
            || die "No locale found"
            
        LOCALE_EXTRA=$LOCALE

        # ── Hardware ──────────────────────────────────────────────────
        formHeader "Hardware"
        GPU=()
        HW_MODULES=()
        formMulti GPU "Select GPU. Both dGPU and iGPU" "nvidia" "amd" "intel"
        
        if formConfirm "Use nixos-hardware modules?" "n"; then            
            if formConfirm "Add a specific model from nixos-hardware?" "n"; then
                local models selection=""
                models="$(listNixosHardwareModules || true)"
                
                if [[ -n $models ]] && formFilter selection "Search for your model" "$models" "e.g. apple-macbook-pro-8-1, asus-rog-strix-x570e, ..."; then
                    HW_MODULES+=("$selection")
                else
                    formInputOpt selection "Module name" "https://github.com/NixOS/nixos-hardware"
                    [[ -n $selection ]] && HW_MODULES+=("$selection")
                fi
            else
                formMulti HW_MODULES "Common hardware modules (toggle what applies)" \
                    "common-cpu-amd" "common-cpu-intel" \
                    "common-gpu-amd" "common-gpu-intel" "common-gpu-nvidia" \
                    "common-pc-laptop-hdd" "common-pc-ssd"
            fi
        fi

        # ── Network (optional) ───────────────────────────────────────────
        formHeader "Network (optional)"
        WIFI='{}'
        if formConfirm "Add wifi or other network(s)?" "n"; then
            gatherWifi
        fi

        # ── Dotfiles (optional) ───────────────────────────────────────
        formHeader "Dotfiles (optional)"
        DOTFILES_SRC=""
        if formConfirm "Clone dotfiles from a source?" "n"; then
            formInputOpt DOTFILES_SRC "Git URL or local path" "https://github.com/... || ~/.config/..."
        fi

        # ── Summary ───────────────────────────────────────────────────
        formHeader "Review Configuration"
        showSummary

        if formConfirm "Is this correct?" "y"; then
            break
        fi
        logWarn "Redoing..."
    done

    # ── Derived state ─────────────────────────────────────────────────
    HOST_DIR="$REPO_ROOT/hosts/$HOSTNAME"
    SECRETS="hosts/$HOSTNAME/secrets.json"
    HOST_ANCHOR="$HOSTNAME"
    USER_ANCHOR="${USERNAME}_${HOSTNAME}"
}

# ── wifi gather ──────────────────────────────────────────────────────────
gatherWifi() {
    local name ssid psk

    while :; do
        formInput name "Connection name" "$ssid" "home"
        formInput ssid "SSID (network name)" "" "my-network"

        if jq -e --arg n "$name" 'has($n)' <<< "$WIFI" > /dev/null 2>&1; then
            logWarn "'$name' is already configured"
            continue
        fi

        formPassword psk "WPA password (8-63 chars)" false

        # Build the new network entry and merge it into WIFI
        WIFI=$(jq --argjson prev "$WIFI" \
            --arg name "$name" --arg ssid "$ssid" --arg psk "$psk" \
            '$prev + {
                ($name): {
                    connection: { id: $name, type: "wifi" },
                    wifi: { ssid: $ssid },
                    "wifi-security": { "key-mgmt": "wpa-psk", psk: $psk }
                }
            }' <<< "{}")

        logInfo "Added '$name' (ssid: $ssid)"
        formConfirm "Add another network?" "n" || break
    done
}

# ── summary ──────────────────────────────────────────────────────────────
showSummary() {
    local gpu_str modules_str addons_str
    local IFS=', '
    gpu_str="${GPU[*]:-skip}"
    modules_str="${HW_MODULES[*]:-skip}"
    addons_str="${ADDONS[*]}"

    local wifi_count wifi_str
    wifi_count="$(jq -r 'keys | length' <<< "$WIFI" 2>/dev/null || echo 0)"
    (( wifi_count > 0 )) && wifi_str="$wifi_count network(s)"

    gum style --border="rounded" --padding="1 2" --margin="1 0" \
        <<EOF
  Hostname       $HOSTNAME
  Architecture   $SYSTEM
  Role           $ROLE${addons_str:+ + $addons_str}
  User           $USERNAME <${USEREMAIL:-no email}>
  GPU            $gpu_str
  HW modules     $modules_str
  Timezone       $TIMEZONE
  Locale         $LOCALE / $LOCALE_EXTRA
  Wi-Fi          ${wifi_str:-skip}
  Dotfiles       ${DOTFILES_SRC:-skip}
EOF
}

# ── resolve target ───────────────────────────────────────────────────────
resolveTarget() {
    [[ $METHOD == iso ]] && TARGET_ROOT="/mnt" || TARGET_ROOT=""
    logDebug "target: ${TARGET_ROOT:-/}"
}

# ── generate keys ────────────────────────────────────────────────────────
generateUserKey() {
    local userKey="$KEYS_DIR/id_$USERNAME"
    
    run ssh-keygen -t ed25519 -N "" -C "$USERNAME@$HOSTNAME" -f "$userKey"
    chmod 600 "$userKey"
    USER_PUB="$(< "$userKey.pub")"
    USER_AGE="$(ssh-to-age < "$userKey.pub")"
    
    logDebug "User fingerprint: $(ssh-keygen -lf "$userKey.pub")"
    logInfo "User age key: $USER_AGE"
}

generateHostKey() {
    HOST_KEY_FILE="$KEYS_DIR/ssh_host_ed25519_key"

    run ssh-keygen -t ed25519 -N "" -C "root@$HOSTNAME" -f "$HOST_KEY_FILE"

    HOST_AGE="$(ssh-to-age < "$HOST_KEY_FILE.pub")"

    logDebug "Host fingerprint: $(ssh-keygen -lf "$HOST_KEY_FILE.pub")"
    logInfo "Host age key: $HOST_AGE"
}

# ── write .sops.yaml ─────────────────────────────────────────────────────
writeSopsYaml() {
    if [[ ! -f .sops.yaml ]]; then
        cat > .sops.yaml <<'EOF'
keys:
  - &users:
  - &hosts:
creation_rules:
EOF
        logInfo "Created .sops.yaml"
    fi

    # insert LINE before the first line exactly matching MARKER
    insertBefore() {
        awk -v l="$1" -v m="$2" '
            !done && $0 == m { print l; done = 1 }
            { print }
            END { if (!done) exit 1 }' .sops.yaml > .sops.yaml.tmp \
            || die ".sops.yaml: marker '$2' not found"
        mv .sops.yaml.tmp .sops.yaml
    }

    # Scrub previous entries for this host (no duplicates on re-run)
    logDebug "scrubbing previous $HOSTNAME entries"
    awk -v userAnchor="    - &$USER_ANCHOR " \
        -v hostAnchor="    - &$HOST_ANCHOR " \
        -v rulePrefix="  - path_regex: hosts/$HOSTNAME/secrets" '
        index($0, userAnchor) == 1 { next }
        index($0, hostAnchor) == 1 { next }
        index($0, rulePrefix) == 1 { skip = 1; next }
        skip && (/^  - / || /^[^ ]/) { skip = 0 }
        skip { next }
        { print }
    ' .sops.yaml > .sops.yaml.tmp
    mv .sops.yaml.tmp .sops.yaml

    insertBefore "    - &$USER_ANCHOR $USER_AGE" "  - &hosts:"
    insertBefore "    - &$HOST_ANCHOR $HOST_AGE" "creation_rules:"

    {
        printf '  - path_regex: %s$\n' "${SECRETS//./\\.}"
        printf '    key_groups:\n'
        printf '      - age:\n'
        grep -q -- '- &admin ' .sops.yaml && printf '          - *admin\n'
        printf '          - *%s\n' "$USER_ANCHOR"
        printf '          - *%s\n' "$HOST_ANCHOR"
    } >> .sops.yaml

    logInfo "Added recipients and creation rule"
}

# ── write secrets.json ───────────────────────────────────────────────────
writeSecrets() {
    local hash
    
    formPassword userPw "Login password for '$USERNAME'"
    hash="$(printf '%s' "$userPw" | mkpasswd -m sha-512 --stdin)"

    mkdir -p "$(dirname "$SECRETS")"

    logDebug "jq -n --arg pw ... --rawfile key ... > $SECRETS"
    jq -n \
        --arg pw  "$hash" \
        --rawfile key "$KEYS_DIR/id_$USERNAME" \
        --argjson wifi "$WIFI" \
        '{ userPassword: $pw, userPrivateKey: $key }
         + (if $wifi == {} then {} else { wifi: $wifi } end)' \
        > "$SECRETS"

    run sops --encrypt --in-place "$SECRETS"
    logInfo "Encrypted $SECRETS"
}

# ── write host.json ──────────────────────────────────────────────────────
writeHostJson() {
    local rolesJson gpuJson modulesJson keysJson
    
    rolesJson=$(printf '%s\n' "$ROLE" "${ADDONS[@]}" | jq -R . | jq -sc 'map(select(. != ""))')
    gpuJson=$(printf '%s\n' "${GPU[@]:-}" | jq -R . | jq -sc 'map(select(. != ""))')
    modulesJson=$(printf '%s\n' "${HW_MODULES[@]:-}" | jq -R . | jq -sc 'map(select(. != ""))')
    keysJson=$(printf '%s\n' "$USER_PUB" | jq -R . | jq -sc 'map(select(. != ""))')

    mkdir -p "$HOST_DIR"

    jq -n \
        --arg hostname "$HOSTNAME" \
        --arg system "$SYSTEM" \
        --arg repoPath "/home/${USERNAME}/nixos-config" \
        --arg userName "$USERNAME" \
        --arg userEmail "${USEREMAIL:-}" \
        --arg tz "$TIMEZONE" \
        --arg locale "$LOCALE" \
        --arg extra "$LOCALE_EXTRA" \
        --argjson roles "$rolesJson" \
        --argjson gpu "$gpuJson" \
        --argjson modules "$modulesJson" \
        --argjson keys "$keysJson" \
        '{
            hostname: $hostname,
            system: $system,
            repoPath: $repoPath,
            roles: $roles,
            user: {
                name: $userName,
                email: $userEmail,
                sshKeys: $keys
            },
            hardware: {
                gpu: $gpu,
                modules: $modules
            },
            locale: {
                timeZone: $tz,
                localeDefault: $locale,
                localeExtra: $extra
            }
        }' > "$HOST_DIR/host.json"

    logInfo "Wrote $HOST_DIR/host.json"
}

# ── hardware.nix ───────────────────────────────────────────────────
writeHardwareNix() {
    local genArgs=(--show-hardware-config --no-filesystems)
    
    if [[ -n $TARGET_ROOT ]]; then
        genArgs+=(--root "$TARGET_ROOT")
    fi

    local body
    logDebug "nixos-generate-config ${genArgs[*]}"
    body="$(nixos-generate-config "${genArgs[@]}" \
        | sed -e '/^ *#/d' \
              -e '/^{ config, lib, pkgs, modulesPath, \.\.\. }:$/d' \
              -e '/^{$/d' \
              -e '/^}$/d')"

    body="$(sed -e 's/^./        &/' <<< "$body" | cat -s)"

    mkdir -p "$HOST_DIR"

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
        printf '%s\n' "$body"
        cat <<'EOF'
    };
}
EOF
    } > "$HOST_DIR/hardware.nix"

    logInfo "Wrote $HOST_DIR/hardware.nix"
}
# ── disko.nix ───────────────────────────────────────────────────
writeDiskoNix() {
    formHeader "Disko"

    local disk dev
    logWarn "The disk will be wiped"
    formFilter disk "Choose target disk" "$(listDisks)" "" \
        || die "No disks found"
        
    dev="/dev/$(awk '{print $1}' <<< "$disk")"
    logInfo "Selected disk: $dev"

    mkdir -p "$HOST_DIR"

    cat > "$HOST_DIR/disko.nix" <<'DISKOEOF'
{ inputs, ... }:
let
    inherit (builtins.fromJSON (builtins.readFile ./host.json)) hostname;
    device = "@DEVICE@";
in
{
    flake.modules.nixos."${hostname}Disko" = { pkgs, ... }:
    {
        imports = [ inputs.disko.nixosModules.disko ];

        config = {
            zramSwap.enable = true;

            # Impermanence mounts /persistent in the stage-1 initrd, so it must
            # be flagged neededForBoot (disko doesn't set this on its own).
            fileSystems."/persistent".neededForBoot = true;

            # Ephemeral root. Under systemd stage-1 initrd this is a service, not
            # boot.initrd.postResumeCommands. It runs once the root device exists
            # and before sysroot is mounted: move the current @root aside, prune
            # roots older than 30 days, then restore a pristine snapshot of
            # @root-blank. Only @root is named — @nix/@persistent/@home survive.
            boot.initrd.systemd.services.rollback = {
                description = "Rollback btrfs root to a pristine snapshot";
                wantedBy = [ "initrd.target" ];
                after = [ "initrd-root-device.target" ];
                before = [ "sysroot.mount" ];
                unitConfig.DefaultDependencies = "no";
                serviceConfig.Type = "oneshot";
                script = ''
                    btrfs=${pkgs.btrfs-progs}/bin/btrfs

                    mkdir -p /btrfs_tmp
                    mount -o subvol=/ /dev/disk/by-partlabel/disk-main-root /btrfs_tmp

                    if [[ -e /btrfs_tmp/@root ]]; then
                        mkdir -p /btrfs_tmp/@old_roots
                        timestamp=$(date --date="@$(stat -c %Y /btrfs_tmp/@root)" "+%Y-%m-%d_%H:%M:%S")
                        mv /btrfs_tmp/@root "/btrfs_tmp/@old_roots/$timestamp"
                    fi

                    delete_subvolume_recursively() {
                        IFS=$'\n'
                        for i in $("$btrfs" subvolume list -o "$1" | cut -f 9- -d ' '); do
                            delete_subvolume_recursively "/btrfs_tmp/$i"
                        done
                        "$btrfs" subvolume delete "$1"
                    }

                    for i in $(${pkgs.findutils}/bin/find /btrfs_tmp/@old_roots/ -maxdepth 1 -mtime +30); do
                        delete_subvolume_recursively "$i"
                    done

                    "$btrfs" subvolume snapshot /btrfs_tmp/@root-blank /btrfs_tmp/@root
                    umount /btrfs_tmp
                '';
            };

            disko.devices.disk.main = {
                inherit device;
                type = "disk";
                content = {
                    type = "gpt";
                    partitions = {
                        ESP = {
                            type = "EF00";
                            size = "512M";
                            content = {
                                type = "filesystem";
                                format = "vfat";
                                mountpoint = "/boot";
                                mountOptions = [ "umask=0077" ];
                            };
                        };
                        root = {
                            size = "100%";
                            content = {
                                type = "btrfs";
                                extraArgs = [ "-f" ];
                                subvolumes = {
                                    "@root" = {
                                        mountpoint = "/";
                                        mountOptions = [ "compress=zstd" "noatime" ];
                                    };
                                    "@root-blank" = { };
                                    "@nix" = {
                                        mountpoint = "/nix";
                                        mountOptions = [ "compress=zstd" "noatime" ];
                                    };
                                    "@persistent" = {
                                        mountpoint = "/persistent";
                                        mountOptions = [ "compress=zstd" "noatime" ];
                                    };
                                    "@home" = {
                                        mountpoint = "/home";
                                        mountOptions = [ "compress=zstd" "noatime" ];
                                    };
                                };
                            };
                        };
                    };
                };
            };
        };
    };
}
DISKOEOF

    sed -i "s|@DEVICE@|$dev|" "$HOST_DIR/disko.nix"
    logInfo "Wrote $HOST_DIR/disko.nix (btrfs + impermanence, $dev)"
}

# ── profile.nix ────────────────────────────────────────────────────
writeProfileNix() {

    mkdir -p "$HOST_DIR"

    cat > "$HOST_DIR/profile.nix" <<'EOF'
{ ... }:
let
    inherit (builtins.fromJSON (builtins.readFile ./host.json)) hostname;
in
{
    imports = [
        (import ../../lib/mkHost.nix ./.)
    ];

    flake.modules.nixos."${hostname}Configuration" = { ... }:
    {
        config = {
            profile.system = {
                bootloader.settings = { };
                bootloader.plymouth = { };

                bootloader.refind = {
                    enable = false;
                    theme.name = null;
                    theme.source = null;
                };
            };

            profile.user = {
                xkb.layout = "us";
                xkb.variant = "";
            };

            profile.desktop = {
                displayManager.settings = { };
                displayManager.extraPackages = [ ];
            };
        };
    };
}
EOF

    logInfo "Wrote $HOST_DIR/profile.nix"
}

# ── write dotfiles ───────────────────────────────────────────────────────
writeDotfiles() {

    if [[ -z $DOTFILES_SRC ]]; then
        logInfo "No dotfiles source — skipping"
        return 0
    fi

    local src="$DOTFILES_SRC" dest="$HOST_DIR/home"
    mkdir -p "$dest"

    [[ $src == "~" || $src == "~/"* ]] && src="${src/#\~/$HOME}"
    [[ $src != /* && -e $src ]] && src="$(readlink -f "$src")"

    if [[ -d $src ]]; then
        logDebug "cp -rT $src $dest"
        cp -rT "$src" "$dest"
        rm -rf "$dest/.git"
        logInfo "Copied dotfiles from $src"
    elif [[ $src == *://* || $src == *@*:* || $src == *.git ]]; then
        if run git -c safe.directory='*' clone --depth 1 "$src" "$KEYS_DIR/dotfiles"; then
            cp -rT "$KEYS_DIR/dotfiles" "$dest"
            rm -rf "$dest/.git"
            logInfo "Cloned dotfiles from $src"
        else
            logWarn "Could not clone $src — continuing without"
        fi
    else
        logWarn "Dotfiles source '$src' is not a directory or a git URL — skipping"
    fi
}

# ── verify ───────────────────────────────────────────────────────────────
# Every failure mode that could lock you out, checked byte-exact
verify() {
    local fail=0

    local userKey="$KEYS_DIR/id_$USERNAME"
    local hostKey="$HOST_KEY_FILE"

    local userAge hostAge
    logDebug "ssh-to-age -private-key -i $userKey"
    userAge="$(ssh-to-age -private-key -i "$userKey")"
    logDebug "ssh-to-age -private-key -i $hostKey"
    hostAge="$(ssh-to-age -private-key -i "$hostKey")"

    # 1. host.json shape
    if jq -e '.hostname and .user.name and .system' "$HOST_DIR/host.json" > /dev/null; then
        logInfo "host.json is valid"
    else
        logError "host.json is malformed"
        fail=1
    fi

    # 2. user key decrypts
    if SOPS_AGE_KEY="$userAge" sops -d "$SECRETS" | jq -e '.userPassword and .userPrivateKey' > /dev/null; then
        logInfo "secrets.json decrypts with the user key"
    else
        logError "User key cannot decrypt $SECRETS"
        fail=1
    fi

    # 3. host key decrypts — the lockout check
    if SOPS_AGE_KEY="$hostAge" sops -d --extract '["userPassword"]' "$SECRETS" > /dev/null; then
        logInfo "Host key decrypts its own secrets"
    else
        logError "Host key cannot decrypt $SECRETS"
        fail=1
    fi

    # 4. stored private key round-trips
    if SOPS_AGE_KEY="$userAge" sops -d --extract '["userPrivateKey"]' "$SECRETS" \
        | ssh-keygen -y -f /dev/stdin > /dev/null 2>&1; then
        logInfo "Stored private key is valid"
    else
        logError "Stored private key is malformed"
        fail=1
    fi

    [[ $fail -eq 0 ]] || die "Verification failed"
}

# ── host key placement ───────────────────────────────────────────────────
# Copy the staged host key onto the persisted subvolume. Must run AFTER the
# target is mounted (iso: after `disko ... mount`; local: /persistent already
# exists) and BEFORE nixos-install/nixos-rebuild activates sops.
installHostKey() {
    local dir="$TARGET_ROOT/persistent/etc/ssh"

    run install -d -m 755 "$dir"
    run install -m 600 "$HOST_KEY_FILE"     "$dir/ssh_host_ed25519_key"
    run install -m 644 "$HOST_KEY_FILE.pub" "$dir/ssh_host_ed25519_key.pub"
    logInfo "Installed host key to $dir"
}

# ── handover ─────────────────────────────────────────────────────────────
installRepo() {
    local home="$TARGET_ROOT/home/$USERNAME"
    local sshDir="$home/.ssh"
    local repoTarget="$home/nixos-config"

    run install -d -m 700 "$sshDir"
    run install -m 600 "$KEYS_DIR/id_$USERNAME" "$sshDir/id_$USERNAME"
    run install -m 644 "$KEYS_DIR/id_$USERNAME.pub" "$sshDir/id_$USERNAME.pub"

    if [[ $REPO_ROOT != "$repoTarget" && ! -e $repoTarget ]]; then
        run mkdir -p "$home"
        run cp -rT "$REPO_ROOT" "$repoTarget"
    fi

    run chown -R 1000:100 "$home"
    logInfo "Handed keys + repo to uid 1000 ($USERNAME) at $repoTarget"
}

# ── install ──────────────────────────────────────────────────────────────
installSystem() {
    formConfirm "Install the configuration now?" "y" || { logWarn "Skipped install"; return 0; }

    # Nix evaluates a flake from the git tree, excluding untracked files.
    # Stage the new host files (no commit needed) so import-tree can see them
    # and nixosConfigurations.$HOSTNAME actually exists.
    run git -c safe.directory='*' add -A

    # These commands are interactive and/or stream their own progress: disko
    # asks to confirm the wipe, nixos-install/rebuild print build logs. They must
    # NOT go through run() — gum spin hides stdin/stdout, so any prompt hangs
    # invisibly (which is what stalled the install). Talk to the terminal
    # directly. --no-root-passwd keeps nixos-install non-interactive.
    case "$METHOD" in
        local)
            installHostKey
            nixos-rebuild boot --flake ".#$HOSTNAME"
            ;;
        iso)
            disko --mode destroy,format,mount --flake ".#$HOSTNAME"
            installHostKey
            nixos-install --root /mnt --flake ".#$HOSTNAME" --no-root-passwd
            ;;
    esac

    installRepo
    logInfo "Installed $HOSTNAME"

    formConfirm "Reboot now?" "y" && { logInfo "Rebooting..."; reboot; }
}

# ── main ─────────────────────────────────────────────────────────────────
main() {
    parseArgs "$@"
    shell "$@"
    REPO_ROOT="$(gitRepo -C "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")" rev-parse --show-toplevel)" \
            || die "Not inside the config git repo"
        cd "$REPO_ROOT"
    clear
    
    [[ $VERBOSE == true ]] && export GUM_LOG_LEVEL=debug || export GUM_LOG_LEVEL=info

    resolveTarget

    # Temp directory for key material
    KEYS_DIR="$(mktemp -d)"
    chmod 700 "$KEYS_DIR"

    # Gather all info via gum form
    gatherForm
    generateUserKey
    
    # host files the flake needs before disko can evaluate
    writeHostJson
    writeDiskoNix
    writeHardwareNix
    writeProfileNix
  
    # now the rest
    generateHostKey
    writeSopsYaml
    writeSecrets
    writeDotfiles
    
    run git -c safe.directory='*' add --intent-to-add .
    verify
    installSystem
}

main "$@"