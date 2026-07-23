#!/usr/bin/env bash

#
# installer.sh - bootstrap a host for this flake
#

set -Eeuo pipefail

# ── state ────────────────────────────────────────────────────────────────
# flags
METHOD=""
VERBOSE=false
TARGET_ROOT=""
ADMIN_KEY=""

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
HOST_KEY_DIR="/etc/ssh"
HOST_KEY_FILE=""
HOST_AGE=""
USER_AGE=""
USER_PUB=""
ADMIN_AGE=""
HOST_ANCHOR=""
USER_ANCHOR=""
SECRETS=""
HOST_DIR=""
WIFI='{}'

# Dotfiles
DOTFILES_SRC=""

# Install state
APPLIED=""

# ── palette ──────────────────────────────────────────────────────────────
FG="#ffffff"       # headers, prompts, cursor
MUTED="#6c7086"    # placeholders, unselected, borders
ACCENT="#a6e3a1"   # the selected/matched item
BASE="#1e1e2e"     # text on the accent background

# ── gum theme ────────────────────────────────────────────────────────────
export GUM_INPUT_PROMPT="  "
export GUM_INPUT_WIDTH="60"
export GUM_INPUT_CURSOR_FOREGROUND="$FG"
export GUM_INPUT_PROMPT_FOREGROUND="$FG"
export GUM_INPUT_HEADER_FOREGROUND="$FG"
export GUM_INPUT_PLACEHOLDER_FOREGROUND="$MUTED"

export GUM_CHOOSE_CURSOR="→ "
export GUM_CHOOSE_HEADER_FOREGROUND="$FG"
export GUM_CHOOSE_CURSOR_FOREGROUND="$ACCENT"
export GUM_CHOOSE_SELECTED_FOREGROUND="$ACCENT"

export GUM_FILTER_INDICATOR="→"
export GUM_FILTER_HEADER_FOREGROUND="$FG"
export GUM_FILTER_INDICATOR_FOREGROUND="$ACCENT"
export GUM_FILTER_MATCH_FOREGROUND="$ACCENT"
export GUM_FILTER_PLACEHOLDER_FOREGROUND="$MUTED"
export GUM_FILTER_PROMPT_FOREGROUND="$FG"

export GUM_CONFIRM_PROMPT_FOREGROUND="$FG"
export GUM_CONFIRM_SELECTED_BACKGROUND="$ACCENT"
export GUM_CONFIRM_SELECTED_FOREGROUND="$BASE"
export GUM_CONFIRM_UNSELECTED_FOREGROUND="$MUTED"

export GUM_SPIN_SPINNER_FOREGROUND="$FG"
export GUM_FILE_HEADER_FOREGROUND="$FG"
export GUM_FILE_CURSOR_FOREGROUND="$ACCENT"
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

    local out rc=0
    out="$(mktemp)"
    "$@" > "$out" 2>&1 || rc=$?
    (( rc == 0 )) || { logError "Command failed: $*"; sed 's/^/    /' "$out" >&2; }
    rm -f "$out"
    return "$rc"
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
      --method <TYPE>     local | iso | remote (nixos-anywhere)
      --root <PATH>       iso: the mounted target (default: /mnt)
      --admin-key <PATH>  Public half of the admin SSH key
  -v, --verbose           Show every command and its output
  -h, --help              This message
EOF
}

parseArgs() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --method)
                [[ -n ${2:-} ]] || { printf -- '--method needs a value\n' >&2; exit 1; }
                METHOD="$2"; shift 2 ;;
            --root)
                [[ -n ${2:-} ]] || { printf -- '--root needs a path\n' >&2; exit 1; }
                TARGET_ROOT="${2%/}"
                shift 2 ;;
            --admin-key)
                [[ -n ${2:-} ]] || { printf -- '--admin-key needs a path\n' >&2; exit 1; }
                ADMIN_KEY="$2"
                shift 2 ;;
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
    [iso]="nixos-install-tools"
    [remote]="nixos-anywhere"
)

# ── bootstrap ────────────────────────────────────────────────────────────
# Phase 1: outside nix-shell. No gum, no jq, just bare bash.
# Ask the method, assemble packages, re-exec inside nix-shell.
method() {
    if [[ -z ${IN_NIX_SHELL:-} ]]; then
        if [[ -z $METHOD ]]; then
            printf '\n\033[1;32m── Install method ──────────────────────────\033[0m\n'
            printf '    1) local   - this machine, running NixOS\n'
            printf '    2) iso     - installer ISO with a mounted target\n'
            printf '    3) remote  - generate host files for another machine\n'
            read -rp '    choice [1]: ' reply
            case "${reply:-1}" in
                1) METHOD="local" ;;
                2) METHOD="iso" ;;
                3) METHOD="remote" ;;
                *) printf 'pick 1-3\n' >&2; exit 1 ;;
            esac
        fi
    
        # Method → modules mapping
        MODULES=("base" "secrets" "locales")
        case "$METHOD" in
            local)  : ;;  # nixos-rebuild is already on NixOS
            iso)    MODULES+=("iso") ;;
            remote) MODULES+=("remote") ;;
        esac
    
        # Build the package list from enabled modules
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
    # Source 1: glibc-locales in nix store (most reliable in nix-shell)
    local glibcLocales
    glibcLocales=$(nix-build --no-out-link '<nixpkgs>' -A glibc-locales 2>/dev/null || true)
    if [[ -n $glibcLocales && -f $glibcLocales/lib/locale/locale-archive ]]; then
        # We can't easily list from the archive, so use locale -a if available
        if command -v locale &>/dev/null; then
            locale -a 2>/dev/null | grep -i utf | sort -u
            return
        fi
    fi

    # Source 2: locale -a if the command exists
    if command -v locale &>/dev/null; then
        locale -a 2>/dev/null | grep -i utf | sort -u
        return
    fi
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
        # sshKeys are generated, not asked — collected in generateKeys

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
        formMulti GPU "Select GPU. Both dGPU and iGPU" "nvidia" "amd" "intel"
        
        if formConfirm "Use nixos-hardware modules?" "n"; then            
            HW_MODULES=()
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
        formInput ssid "SSID (network name)" "" "my-network"
        formInput name "Connection name" "$ssid" "home"

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
    addons_str="${ADDONS[*]:-skip}"

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
    if [[ -n $TARGET_ROOT ]]; then
        TARGET_ROOT="${TARGET_ROOT%/}"
        [[ -d $TARGET_ROOT ]] || die "--root: $TARGET_ROOT is not a directory"
    fi

    HOST_KEY_DIR="${TARGET_ROOT}/etc/ssh"
    logDebug "host key dir: $HOST_KEY_DIR"

    if [[ -n $TARGET_ROOT ]]; then
        logInfo "Install target: $TARGET_ROOT"
    fi
}

# ── generate keys ────────────────────────────────────────────────────────
# Three recipients of secrets.json:
#   host  - decrypts at activation (sops-nix, via sshKeyPaths)
#   user  - generated into temp dir, stored in secrets.json, seeded into
#           target ~/.ssh by installRepo
#   admin - one global recipient
generateKeys() {
    formHeader "Key Generation"

    # Host key; reused when present
    HOST_KEY_FILE="$HOST_KEY_DIR/ssh_host_ed25519_key"

    if [[ -f "$HOST_KEY_FILE.pub" ]]; then
        logInfo "Host key: reusing $HOST_KEY_FILE"
    else
        run install -d -m 755 "$HOST_KEY_DIR"
        run ssh-keygen -t ed25519 -N "" -C "root@$HOSTNAME" -f "$HOST_KEY_FILE"
        logInfo "Host key: generated"
    fi
    logDebug "fingerprint: $(ssh-keygen -lf "$HOST_KEY_FILE.pub")"
    HOST_AGE="$(ssh-to-age < "$HOST_KEY_FILE.pub")"
    logInfo "host age: $HOST_AGE"

    # User key
    local userKey="$KEYS_DIR/id_$USERNAME"
    run ssh-keygen -t ed25519 -N "" -C "$USERNAME@$HOSTNAME" -f "$userKey"
    chmod 600 "$userKey"
    USER_PUB="$(< "$userKey.pub")"
    logDebug "fingerprint: $(ssh-keygen -lf "$userKey.pub")"
    USER_AGE="$(ssh-to-age < "$userKey.pub")"
    logInfo "User key: generated"
    logInfo "user age:  $USER_AGE"

    # Admin key
    local pub="${ADMIN_KEY:-$REPO_ROOT/id_admin.pub}"
    local existing="" derived=""

    if [[ -f .sops.yaml ]]; then
        existing="$(sed -n 's/^[[:space:]]*- &admin \(age1[0-9a-z]*\).*/\1/p' .sops.yaml | head -n1)"
    fi
    
    if [[ -r $pub ]]; then
        derived="$(ssh-to-age < "$pub")"
    fi
    
    logDebug "admin: existing anchor ${existing:-none}, derived ${derived:-none}"

    if [[ -n $existing ]]; then
        ADMIN_AGE="$existing"
        logInfo "Admin key: using the &admin anchor from .sops.yaml"
        if [[ -n $derived && $derived != "$existing" ]]; then
            logWarn "$pub derives $derived, which does NOT match the &admin anchor"
            logWarn "Secrets are encrypted to the anchor — that key file cannot decrypt them"
        fi
    elif [[ -n $derived ]]; then
        ADMIN_AGE="$derived"
        logInfo "Admin key: seeded from $pub"
    else
        logWarn "No admin key. Secrets will be readable by this host and user only"
    fi
    [[ -n $ADMIN_AGE ]] && logInfo "admin age: $ADMIN_AGE"
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

    if [[ -n $ADMIN_AGE ]] && ! grep -q -- "- &admin " .sops.yaml; then
        insertBefore "    - &admin $ADMIN_AGE" "  - &hosts:"
    fi

    insertBefore "    - &$USER_ANCHOR $USER_AGE" "  - &hosts:"
    insertBefore "    - &$HOST_ANCHOR $HOST_AGE" "creation_rules:"

    {
        printf '  - path_regex: %s$\n' "${SECRETS//./\\.}"
        printf '    key_groups:\n'
        printf '      - age:\n'
        [[ -n $ADMIN_AGE ]] && printf '          - *admin\n'
        printf '          - *%s\n' "$USER_ANCHOR"
        printf '          - *%s\n' "$HOST_ANCHOR"
    } >> .sops.yaml

    logInfo "Added recipients and creation rule"
}

# ── write secrets.json ───────────────────────────────────────────────────
writeSecrets() {

    local hash
    logInfo "Set the login password for '$USERNAME':"
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

    local adminPub=""
    
    if [[ -r ${ADMIN_KEY:-$REPO_ROOT/id_admin.pub} ]]; then
        adminPub="$(< "${ADMIN_KEY:-$REPO_ROOT/id_admin.pub}")"
    fi

    local rolesJson gpuJson modulesJson keysJson
    rolesJson=$(printf '%s\n' "$ROLE" "${ADDONS[@]}" | jq -R . | jq -sc 'map(select(. != ""))')
    gpuJson=$(printf '%s\n' "${GPU[@]:-}" | jq -R . | jq -sc 'map(select(. != ""))')
    modulesJson=$(printf '%s\n' "${HW_MODULES[@]:-}" | jq -R . | jq -sc 'map(select(. != ""))')
    keysJson=$(printf '%s\n%s\n' "$USER_PUB" "$adminPub" | jq -R . | jq -sc 'map(select(. != ""))')

    mkdir -p "$HOST_DIR"

    jq -n \
        --arg hostname "$HOSTNAME" \
        --arg system "$SYSTEM" \
        --arg repoPath "$REPO_ROOT" \
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

# ── write hardware.nix ───────────────────────────────────────────────────
writeHardwareNix() {

    local genArgs=(--show-hardware-config)
    
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

# ── write profile.nix ────────────────────────────────────────────────────
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

    local dest="$HOST_DIR/home"
    mkdir -p "$dest"

    if [[ -d $DOTFILES_SRC ]]; then
        logDebug "cp -rT $DOTFILES_SRC $dest"
        cp -rT "$DOTFILES_SRC" "$dest"
        rm -rf "$dest/.git"
        logInfo "Copied dotfiles from $DOTFILES_SRC"
    else
        if run gitRepo clone --depth 1 "$DOTFILES_SRC" "$KEYS_DIR/dotfiles"; then
            cp -rT "$KEYS_DIR/dotfiles" "$dest"
            rm -rf "$dest/.git"
            logInfo "Cloned dotfiles from $DOTFILES_SRC"
        else
            logWarn "Could not fetch $DOTFILES_SRC — continuing without"
        fi
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

    # 5. admin key (informational)
    if [[ -n $ADMIN_AGE ]]; then
        if sops -d --extract '["userPassword"]' "$SECRETS" > /dev/null 2>&1; then
            logInfo "Admin key on this machine decrypts the secrets"
        else
            logInfo "No admin private key on this machine (fine on the target itself)"
        fi
    fi

    [[ $fail -eq 0 ]] || die "Verification failed"
}

# ── handover ─────────────────────────────────────────────────────────────
installRepo() {

    run chown -R 1000:100 "$REPO_ROOT"
    logInfo "Ownership: uid 1000 ($USERNAME)"

    local home="$TARGET_ROOT/home/$USERNAME"
    local target="$home/nixos-config"

    # Seed the user key
    local sshDir="$home/.ssh"
    run install -d -m 700 "$sshDir"
    run install -m 600 "$KEYS_DIR/id_$USERNAME" "$sshDir/id_$USERNAME"
    run install -m 644 "$KEYS_DIR/id_$USERNAME.pub" "$sshDir/id_$USERNAME.pub"
    run chown 1000:100 "$home" "$sshDir" "$sshDir/id_$USERNAME" "$sshDir/id_$USERNAME.pub"
    logInfo "Seeded $sshDir/id_$USERNAME"

    # Move repo to conventional location
    if [[ $REPO_ROOT == "$target" ]]; then
        logInfo "Repo is already at $target"
    elif [[ -e $target ]]; then
        logWarn "$target already exists. Leaving the repo at $REPO_ROOT"
    elif formConfirm "Move the repo to $target?" "y"; then
        run mv "$REPO_ROOT" "$target"
        REPO_ROOT="$target"
        cd "$REPO_ROOT"
        logInfo "Moved repo to $target"
    else
        logInfo "Keeping the repo at $REPO_ROOT"
    fi

    # Record runtime location in host.json
    local hostJson="$REPO_ROOT/hosts/$HOSTNAME/host.json"
    local runtimePath="${REPO_ROOT#"$TARGET_ROOT"}"
    logDebug "repoPath: $runtimePath (from $REPO_ROOT)"
    jq --arg p "$runtimePath" '.repoPath = $p' "$hostJson" > "$hostJson.tmp"
    mv "$hostJson.tmp" "$hostJson"
    chown 1000:100 "$hostJson"
    logInfo "Recorded repo location: $runtimePath"
}

# ── install ──────────────────────────────────────────────────────────────
installSystem() {
    local flake="$REPO_ROOT#$HOSTNAME"

    case "$METHOD" in
        local)
            # Local: nixos-rebuild with switch/boot/skip choice
            local action
            formChoose action "Apply the configuration" \
                "switch - build and activate now" \
                "boot   - activate on next reboot" \
                "skip   - just print the command"
            action="${action%% *}"

            if [[ $action == skip ]]; then
                APPLIED="skipped"
                logInfo "Run when ready:"
                logInfo "  sudo nixos-rebuild switch --flake $flake"
                return 0
            fi

            local cmd=(nixos-rebuild "$action" --flake "$flake")
            logInfo "Command: ${cmd[*]}"
            "${cmd[@]}"
            APPLIED="$action"
            logInfo "nixos-rebuild $action finished"
            ;;

        iso)
            # ISO: nixos-install to mounted target
            local cmd=(nixos-install --root "$TARGET_ROOT" --flake "$flake")
            logInfo "Command: ${cmd[*]}"
            if ! formConfirm "Install now?" "y"; then
                APPLIED="skipped"
                logInfo "Run when ready:"
                logInfo "  ${cmd[*]}"
                return 0
            fi
            "${cmd[@]}"
            APPLIED="installed"
            logInfo "Installed $HOSTNAME to $TARGET_ROOT"
            ;;

        remote)
            # Remote: nixos-anywhere
            local target
            formInput target "SSH target" "user@hostname"

            local cmd=(nixos-anywhere --flake "$flake" "$target")
            logInfo "Command: ${cmd[*]}"
            if ! formConfirm "Deploy now?" "y"; then
                APPLIED="skipped"
                logInfo "Run when ready:"
                logInfo "  ${cmd[*]}"
                return 0
            fi
            "${cmd[@]}"
            APPLIED="deployed"
            logInfo "Deployed $HOSTNAME to $target"
            ;;
    esac
}

# ── main ─────────────────────────────────────────────────────────────────
main() {
    clear
    parseArgs "$@"
    method "$@"
    clear
    
    [[ $VERBOSE == true ]] && export GUM_LOG_LEVEL=debug || export GUM_LOG_LEVEL=info

    resolveTarget

    # Temp directory for key material
    KEYS_DIR="$(mktemp -d)"
    chmod 700 "$KEYS_DIR"

    # Gather all info via gum form
    gatherForm

    # Write files
    generateKeys
    writeSopsYaml
    writeSecrets
    writeHostJson
    # writeDisko
    writeHardwareNix
    writeProfileNix
    writeDotfiles

    # run gitRepo add --intent-to-add .

    # Verify 
    verify

    # Install
    case "$METHOD" in
        local) installSystem ;;
        iso) installRepo; installSystem ;;
        remote) installSystem ;;
    esac
}

main "$@"