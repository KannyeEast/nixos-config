#!/usr/bin/env bash

#
# installer.sh - bootstrap a host for this flake
#

set -Eeuo pipefail

# ── flags ────────────────────────────────────────────────────────────────
METHOD="${INSTALLER_METHOD:-}"
VERBOSE=false
TARGET_ROOT=""
ADMIN_KEY=""

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


parseArgs "$@"

# ── modular package registry ─────────────────────────────────────────────
# Each "module" registers its packages. The method picks which modules
# to enable.
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


# ── logging ──────────────────────────────────────────────────────────────
# Color palette with terminal detection (no escape codes when piped)
if [[ -t 1 && ${TERM:-} != dumb ]]; then
    RED=$'\033[31m';     GREEN=$'\033[32m';   YELLOW=$'\033[33m'
    BLUE=$'\033[34m';    MAGENTA=$'\033[35m'; CYAN=$'\033[36m'
    BOLD=$'\033[1m';     DIM=$'\033[2m';      NC=$'\033[0m'
    RED_B=$'\033[91m';   GREEN_B=$'\033[92m'; YELLOW_B=$'\033[93m'
    BLUE_B=$'\033[94m';  CYAN_B=$'\033[96m'
else
    RED=''; GREEN=''; YELLOW=''; BLUE=''; MAGENTA=''; CYAN=''
    BOLD=''; DIM=''; NC=''
    RED_B=''; GREEN_B=''; YELLOW_B=''; BLUE_B=''; CYAN_B=''
fi

# ── step tracking ────────────────────────────────────────────────────────
STEP_NUM=0
STEP_TOTAL=0

setStepTotal() { STEP_TOTAL="$1"; }

printStep() {
    (( STEP_NUM++ )) || true
    local prefix=""
    [[ $STEP_TOTAL -gt 0 ]] && prefix=" ${DIM}[$STEP_NUM/$STEP_TOTAL]${NC}"
    printf '\n%s%s── %s ──%s\n' "$BOLD$CYAN_B" "$prefix" "$*" "$NC"
}

printHeader() {
    printf '\n%s── %s ──%s\n' "$BOLD$GREEN_B" "$*" "$NC"
}

printSuccess() { printf '%s%s✓%s %s\n' "$GREEN_B" "$BOLD" "$NC" "$*"; }
printError() { printf '%s%s✗%s %s\n' "$RED_B"   "$BOLD" "$NC" "$*" >&2; }
printWarn() { printf '%s%s⚠%s  %s\n' "$YELLOW_B" "$BOLD" "$NC" "$*"; }
printInfo() { printf '%s%sℹ%s  %s\n' "$BLUE_B"  "$BOLD" "$NC" "$*"; }
printDebug() { [[ $VERBOSE == true ]] || return 0; printf '%s  · %s%s\n' "$DIM" "$*" "$NC" >&2; }
printCmd() { [[ $VERBOSE == true ]] || return 0; printf '%s  » %s%s\n' "$MAGENTA" "$*" "$NC" >&2; }

die() {
    printError "$1"
    exit "${2:-1}"
}

# run CMD — execute with verbose tracing; capture-and-replay on failure
run() {
    printCmd "$*"
    if [[ $VERBOSE == true ]]; then
        "$@"
        return
    fi

    local out rc=0
    out="$(mktemp)"
    "$@" > "$out" 2>&1 || rc=$?

    if (( rc != 0 )); then
        printError "Command failed: $*"
        sed 's/^/    /' "$out" >&2
    fi

    rm -f "$out"
    return "$rc"
}

# ── traps ────────────────────────────────────────────────────────────────
trapError() {
    local code=$? cmd=$BASH_COMMAND line=${BASH_LINENO[0]} fn=${FUNCNAME[1]:-main}
    printError "'$cmd' failed (exit $code) at $fn():$line"
    exit "$code"
}
trap trapError ERR

cleanup() {
    [[ -n ${KEYS_DIR:-} && -d ${KEYS_DIR:-} ]] && rm -rf "$KEYS_DIR"
    printf '\033[?25h' >&2
}
trap cleanup EXIT

# ── helpers ──────────────────────────────────────────────────────────────
gitRepo() { git -c safe.directory='*' "$@"; }

# ── state ────────────────────────────────────────────────────────────────
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

# ── form helpers (gum wrappers) ──────────────────────────────────────────
# formHeader TEXT — styled section divider inside the form
formHeader() {
    gum style --bold --foreground="#7DD3FC" --border="rounded" \
        --border-foreground="#7DD3FC" --padding="0 2" --margin="1 0" "$*"
}

# formInput VAR LABEL [DEFAULT] [PLACEHOLDER]
# Required text input. Loops until non-empty.
formInput() {
    local __var="$1" label="$2" default="${3:-}" placeholder="${4:-$3}"
    local value
    while :; do
        value=$(gum input \
            --prompt="  " \
            --placeholder="${placeholder:-$label}" \
            --header="$label" \
            --header.foreground="#7DD3FC" \
            --width=60) || die "Cancelled"
        [[ -n $value ]] && break
        printWarn "$label cannot be empty"
    done
    printf -v "$__var" '%s' "$value"
}


# formInputOpt VAR LABEL [PLACEHOLDER]
# Optional text input — empty is allowed.
formInputOpt() {
    local __var="$1" label="$2" placeholder="${3:-$label}"
    local value
    value=$(gum input \
        --prompt="  " \
        --placeholder="$placeholder" \
        --header="$label" \
        --header.foreground="#7DD3FC" \
        --width=60) || true
    printf -v "$__var" '%s' "$value"
}

# formPassword VAR LABEL
# Password input — masked, asked twice, minimum 8 chars.
formPassword() {
    local __var="$1" label="$2"
    local pw pw2
    while :; do
        pw=$(gum input \
            --prompt="  " \
            --placeholder="$label" \
            --header="$label" \
            --header.foreground="#7DD3FC" \
            --password \
            --width=60) || die "Cancelled"
        [[ -n $pw && ${#pw} -ge 8 ]] || { printWarn "Min 8 characters"; continue; }
        pw2=$(gum input \
            --prompt="  " \
            --placeholder="Repeat $label" \
            --header="Repeat $label" \
            --header.foreground="#7DD3FC" \
            --password \
            --width=60) || die "Cancelled"
        [[ $pw == "$pw2" ]] && break
        printWarn "Mismatch — try again"
    done
    printf -v "$__var" '%s' "$pw"
}

# formChoose VAR LABEL OPT...  — single select, first option pre-selected
formChoose() {
    local __var="$1" label="$2"; shift 2
    local options=("$@")
    local selected
    selected=$(gum choose \
        --header="$label" \
        --header.foreground="#7DD3FC" \
        --selected="${options[0]}" \
        --height=15 \
        "${options[@]}") || die "Cancelled"
    printf -v "$__var" '%s' "$selected"
}

# formMulti VAR LABEL OPT...  — multi-select, returns bash array via nameref
formMulti() {
    local __var="$1" label="$2"; shift 2
    local options=("$@")
    local selected
    selected=$(gum choose --no-limit \
        --header="$label" \
        --header.foreground="#7DD3FC" \
        --height=15 \
        "${options[@]}") || true
    local -n __ref="$__var"
    if [[ -n $selected ]]; then
        mapfile -t __ref <<< "$selected"
    else
        __ref=()
    fi
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
        printDebug "nix eval failed, retrying with --refresh: $(cat "$err")"
        if ! json="$(timeout 120 nix eval "${args[@]}" --refresh 2>"$err")"; then
            printWarn "Could not fetch nixos-hardware modules"
            printDebug "$(cat "$err")"
            rm -f "$err"
            return 1
        fi
    fi
    rm -f "$err"

    jq -r '.[]' <<< "$json" | sort
}

# ── locale list ──────────────────────────────────────────────────────────
# Returns all glibc-supported locales with UTF-8 encoding (most common case)
# Tries multiple sources in order of preference
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

    # Source 3: Common locales fallback (curated short list)
    cat <<'EOF'
C.UTF-8
en_US.UTF-8
en_GB.UTF-8
de_DE.UTF-8
fr_FR.UTF-8
es_ES.UTF-8
it_IT.UTF-8
pt_BR.UTF-8
ru_RU.UTF-8
ja_JP.UTF-8
ko_KR.UTF-8
zh_CN.UTF-8
zh_TW.UTF-8
nl_NL.UTF-8
pl_PL.UTF-8
sv_SE.UTF-8
tr_TR.UTF-8
EOF
}

# ── validation helpers ───────────────────────────────────────────────────
# validateHostname — loops formInput until the hostname passes regex + uniqueness
validateHostname() {
    while :; do
        formInput HOSTNAME "Hostname" "nixos" "my-nixos"
        if [[ ! $HOSTNAME =~ ^[a-z][a-z0-9-]{0,62}$ ]]; then
            printWarn "Lowercase letters, digits, and hyphens only"
            continue
        fi
        if [[ -d $REPO_ROOT/hosts/$HOSTNAME ]]; then
            printWarn "hosts/$HOSTNAME already exists"
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
        printWarn "Lowercase letters, digits, hyphens, underscores; start with letter or underscore"
    done
}

# ── gather form ──────────────────────────────────────────────────────────
gatherForm() {
    printStep

    while :; do
        # ── Identity ──────────────────────────────────────────────────
        formHeader "Identity"

        validateHostname
        formChoose SYSTEM "Architecture" "x86_64-linux" "aarch64-linux"

        # ── Roles ─────────────────────────────────────────────────────
        formHeader "Role"
        formChoose ROLE "Primary role" "desktop" "server"
        if [[ $ROLE == "desktop" ]]; then
            formMulti ADDONS "Add-ons (space to toggle)" "dev"
        fi

        # ── User ──────────────────────────────────────────────────────
        formHeader "User"

        validateUsername
        formInputOpt USEREMAIL "Email" "$USERNAME@$HOSTNAME"
        # sshKeys are generated, not asked — collected in generateKeys

        # ── Hardware ──────────────────────────────────────────────────
        formHeader "Hardware"
        formMulti GPU "Select GPU driver(s)" "nvidia" "amd" "intel"
        
        # Common modules — all shown, user toggles what applies
        formMulti HW_MODULES "Common hardware modules (toggle what applies)" \
            "common-cpu-intel" "common-cpu-amd" \
            "common-gpu-nvidia" "common-gpu-amd" "common-gpu-intel" \
            "common-pc-ssd" "common-pc-hdd" \
            "common-pc-laptop-hdd" "common-pc-laptop"
        
        # Specific model — searchable list from nixos-hardware flake
        if formConfirm "Add a specific model from nixos-hardware?" "n"; then
            local models specific=""
            models="$(listNixosHardwareModules || true)"

            if [[ -z $models ]]; then
                formInputOpt specific "Module name (fetch failed - type it manually)" "asus-rog-strix-x570e"
            else
                specific=$(gum filter \
                    --header="Search for your model (type to filter)" \
                    --header.foreground="#7DD3FC" \
                    --height=20 \
                    --placeholder="e.g. apple-macbook-pro-8-1, asus-rog-strix-x570e, ..." \
                    <<< "$models") || true
            fi

            [[ -n $specific ]] && HW_MODULES+=("$specific")
        fi
        
        # ── Locale ────────────────────────────────────────────────────
        formHeader "Locale"
        # Timezone: collect all IANA zones, pipe to gum filter
        local zones=""
        # Source 1: timedatectl (works on running NixOS, not in nix-shell)
        zones=$(timedatectl list-timezones 2>/dev/null || true)
        
        # Source 2: find in zoneinfo (standard Linux path)
        if [[ -z $zones ]]; then
            zones=$(find /usr/share/zoneinfo -type f -printf '%P\n' 2>/dev/null \
                | grep -v -E '^(posix|right|Etc)/' | sort || true)
        fi
        
        # Source 3: NixOS-specific zoneinfo path
        if [[ -z $zones ]]; then
            local tzdir
            tzdir=$(nix-build --no-out-link '<nixpkgs>' -A tzdata 2>/dev/null || true)
            if [[ -n $tzdir ]]; then
                zones=$(find "$tzdir/share/zoneinfo" -type f -printf '%P\n' 2>/dev/null \
                    | grep -v -E '^(posix|right|Etc)/' | sort || true)
            fi
        fi
        
        # Source 4: hardcoded fallback with common zones
        if [[ -z $zones ]]; then
            zones="America/New_York America/Chicago America/Denver America/Los_Angeles
        America/Toronto America/Mexico_City
        Europe/London Europe/Paris Europe/Berlin Europe/Madrid Europe/Rome
        Europe/Amsterdam Europe/Stockholm Europe/Moscow
        Asia/Tokyo Asia/Shanghai Asia/Singapore Asia/Dubai Asia/Kolkata
        Australia/Sydney Pacific/Auckland
        UTC"
        fi
        
        TIMEZONE=$(echo "$zones" | gum filter \
            --header="Timezone (type to filter)" \
            --header.foreground="#7DD3FC" \
            --height=15 \
            --placeholder="e.g. America/New_York, Europe/London...") || die "Cancelled"
                
        # Locales: filter through glibc's supported locale list
        # The list is at https://sourceware.org/git/?p=glibc.git;a=blob;f=localedata/SUPPORTED
        # On NixOS it's available in the glibc-locales store path
        LOCALE=$(listSupportedLocales | gum filter \
            --header="Default locale (type to filter)" \
            --header.foreground="#7DD3FC" \
            --height=15 \
            --placeholder="e.g. en_US.UTF-8, de_DE.UTF-8...") || die "Cancelled"
            
        LOCALE_EXTRA=$LOCALE

        # ── Wifi (optional) ───────────────────────────────────────────
        formHeader "Wi-Fi (optional)"
        if formConfirm "Add wifi networks?" "n"; then
            gatherWifi
        fi

        # ── Dotfiles (optional) ───────────────────────────────────────
        formHeader "Dotfiles (optional)"
        if formConfirm "Seed dotfiles from a source?" "n"; then
            formInputOpt DOTFILES_SRC "Git URL or local path" "https://github.com/..."
        fi

        # ── Summary ───────────────────────────────────────────────────
        printHeader "Review Configuration"
        showSummary

        if formConfirm "Does this look correct?" "y"; then
            break
        fi
        printWarn "Let's try again..."
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
            printWarn "'$name' is already configured"
            continue
        fi

        formPassword psk "WPA password (8-63 chars)"

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

        printSuccess "Added '$name' (ssid: $ssid)"
        formConfirm "Add another network?" "n" || break
    done
}

# ── summary ──────────────────────────────────────────────────────────────
showSummary() {
    local gpu_str modules_str addons_str
    local IFS=', '
    gpu_str="${GPU[*]:-none}"
    modules_str="${HW_MODULES[*]:-none}"
    addons_str="${ADDONS[*]:-none}"

    local wifi_count
    wifi_count="$(jq -r 'keys | length' <<< "$WIFI" 2>/dev/null || echo 0)"
    local wifi_str="none"
    (( wifi_count > 0 )) && wifi_str="$wifi_count network(s)"

    gum style --border="rounded" --padding="1 2" --margin="1 0" \
        --border-foreground="#7DD3FC" <<EOF
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

# ── validate environment ─────────────────────────────────────────────────
validate() {
    printStep
    local fail=0

    check() {
        local msg="$1"; shift
        if "$@" > /dev/null 2>&1; then
            printSuccess "$msg"
        else
            printError "$msg"
            fail=1
        fi
    }

    REPO_ROOT="$(gitRepo -C "$(dirname "${BASH_SOURCE[0]}")" rev-parse --show-toplevel 2>/dev/null || true)"

    check "Interactive terminal" test -t 0
    check "Config repo with flake.nix" test -f "$REPO_ROOT/flake.nix"

    case "$METHOD" in
        local)
            check "Running NixOS" grep -qi nixos /etc/os-release
            check "Root privileges" test "$EUID" -eq 0
            if grep -q 'VARIANT_ID=installer' /etc/os-release 2>/dev/null; then
                printWarn "This looks like the installer ISO — did you mean method 'iso'?"
            fi
            ;;
        iso)
            TARGET_ROOT="${TARGET_ROOT:-/mnt}"
            check "Installer ISO" grep -q 'VARIANT_ID=installer' /etc/os-release
            check "Root privileges" test "$EUID" -eq 0
            check "Target mounted at $TARGET_ROOT" findmnt -M "$TARGET_ROOT"
            ;;
        remote)
            : # no local prerequisites
            ;;
    esac

    [[ $fail -eq 0 ]] || die "Fix the above and rerun"

    cd "$REPO_ROOT"
    printDebug "repo: $REPO_ROOT | target: ${TARGET_ROOT:-none}"
}

# ── resolve target ───────────────────────────────────────────────────────
resolveTarget() {
    if [[ -n $TARGET_ROOT ]]; then
        TARGET_ROOT="${TARGET_ROOT%/}"
        [[ -d $TARGET_ROOT ]] || die "--root: $TARGET_ROOT is not a directory"
    fi

    HOST_KEY_DIR="${TARGET_ROOT}/etc/ssh"
    printDebug "host key dir: $HOST_KEY_DIR"

    if [[ -n $TARGET_ROOT ]]; then
        printSuccess "Install target: $TARGET_ROOT"
    fi
}

# ── generate keys ────────────────────────────────────────────────────────
# Three recipients of secrets.json:
#   host  - decrypts at activation (sops-nix, via sshKeyPaths)
#   user  - generated into temp dir, stored in secrets.json, seeded into
#           target ~/.ssh by installRepo
#   admin - one global recipient
generateKeys() {
    printStep
    formHeader "Key Generation"

    # Host key; reused when present
    HOST_KEY_FILE="$HOST_KEY_DIR/ssh_host_ed25519_key"

    if [[ -f "$HOST_KEY_FILE.pub" ]]; then
        printSuccess "Host key: reusing $HOST_KEY_FILE"
    else
        run install -d -m 755 "$HOST_KEY_DIR"
        run ssh-keygen -t ed25519 -N "" -C "root@$HOSTNAME" -f "$HOST_KEY_FILE"
        printSuccess "Host key: generated"
    fi
    printDebug "fingerprint: $(ssh-keygen -lf "$HOST_KEY_FILE.pub")"
    HOST_AGE="$(ssh-to-age < "$HOST_KEY_FILE.pub")"
    printInfo "host age: $HOST_AGE"

    # User key
    local userKey="$KEYS_DIR/id_$USERNAME"
    run ssh-keygen -t ed25519 -N "" -C "$USERNAME@$HOSTNAME" -f "$userKey"
    chmod 600 "$userKey"
    USER_PUB="$(< "$userKey.pub")"
    printDebug "fingerprint: $(ssh-keygen -lf "$userKey.pub")"
    USER_AGE="$(ssh-to-age < "$userKey.pub")"
    printSuccess "User key: generated"
    printInfo "user age:  $USER_AGE"

    # Admin key
    local pub="${ADMIN_KEY:-$REPO_ROOT/id_admin.pub}"
    local existing="" derived=""

    if [[ -f .sops.yaml ]]; then
        existing="$(sed -n 's/^[[:space:]]*- &admin \(age1[0-9a-z]*\).*/\1/p' .sops.yaml | head -n1)"
    fi
    
    if [[ -r $pub ]]; then
        derived="$(ssh-to-age < "$pub")"
    fi
    
    printDebug "admin: existing anchor ${existing:-none}, derived ${derived:-none}"

    if [[ -n $existing ]]; then
        ADMIN_AGE="$existing"
        printSuccess "Admin key: using the &admin anchor from .sops.yaml"
        if [[ -n $derived && $derived != "$existing" ]]; then
            printWarn "$pub derives $derived, which does NOT match the &admin anchor"
            printWarn "Secrets are encrypted to the anchor — that key file cannot decrypt them"
        fi
    elif [[ -n $derived ]]; then
        ADMIN_AGE="$derived"
        printSuccess "Admin key: seeded from $pub"
    else
        printWarn "No admin key. Secrets will be readable by this host and user only"
    fi
    [[ -n $ADMIN_AGE ]] && printInfo "admin age: $ADMIN_AGE"
}

# ── write .sops.yaml ─────────────────────────────────────────────────────
writeSopsYaml() {
    printStep

    if [[ ! -f .sops.yaml ]]; then
        cat > .sops.yaml <<'EOF'
keys:
  - &users:
  - &hosts:
creation_rules:
EOF
        printSuccess "Created .sops.yaml"
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
    printDebug "scrubbing previous $HOSTNAME entries"
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

    printSuccess "Added recipients and creation rule"
}

# ── write secrets.json ───────────────────────────────────────────────────
writeSecrets() {
    printStep

    local hash
    printInfo "Set the login password for '$USERNAME':"
    hash="$(mkpasswd -m sha-512)"

    mkdir -p "$(dirname "$SECRETS")"

    printDebug "jq -n --arg pw ... --rawfile key ... > $SECRETS"
    jq -n \
        --arg pw  "$hash" \
        --rawfile key "$KEYS_DIR/id_$USERNAME" \
        --argjson wifi "$WIFI" \
        '{ userPassword: $pw, userPrivateKey: $key }
         + (if $wifi == {} then {} else { wifi: $wifi } end)' \
        > "$SECRETS"

    run sops --encrypt --in-place "$SECRETS"
    printSuccess "Encrypted $SECRETS"
}

# ── write host.json ──────────────────────────────────────────────────────
writeHostJson() {
    printStep

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

    printSuccess "Wrote $HOST_DIR/host.json"
}

# ── write hardware.nix ───────────────────────────────────────────────────
writeHardwareNix() {
    printStep

    local genArgs=(--show-hardware-config)
    
    if [[ -n $TARGET_ROOT ]]; then
        genArgs+=(--root "$TARGET_ROOT")
    fi

    local body
    printDebug "nixos-generate-config ${genArgs[*]}"
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

    printSuccess "Wrote $HOST_DIR/hardware.nix"
}

# ── write profile.nix ────────────────────────────────────────────────────
writeProfileNix() {
    printStep

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

    printSuccess "Wrote $HOST_DIR/profile.nix"
}

# ── write dotfiles ───────────────────────────────────────────────────────
writeDotfiles() {
    printStep

    if [[ -z $DOTFILES_SRC ]]; then
        printInfo "No dotfiles source — skipping"
        return 0
    fi

    local dest="$HOST_DIR/home"
    mkdir -p "$dest"

    if [[ -d $DOTFILES_SRC ]]; then
        printDebug "cp -rT $DOTFILES_SRC $dest"
        cp -rT "$DOTFILES_SRC" "$dest"
        rm -rf "$dest/.git"
        printSuccess "Copied dotfiles from $DOTFILES_SRC"
    else
        if run gitRepo clone --depth 1 "$DOTFILES_SRC" "$KEYS_DIR/dotfiles"; then
            cp -rT "$KEYS_DIR/dotfiles" "$dest"
            rm -rf "$dest/.git"
            printSuccess "Cloned dotfiles from $DOTFILES_SRC"
        else
            printWarn "Could not fetch $DOTFILES_SRC — continuing without"
        fi
    fi
}

# ── verify ───────────────────────────────────────────────────────────────
# Every failure mode that could lock you out, checked byte-exact
verify() {
    printStep
    local fail=0

    local userKey="$KEYS_DIR/id_$USERNAME"
    local hostKey="$HOST_KEY_FILE"

    local userAge hostAge
    printDebug "ssh-to-age -private-key -i $userKey"
    userAge="$(ssh-to-age -private-key -i "$userKey")"
    printDebug "ssh-to-age -private-key -i $hostKey"
    hostAge="$(ssh-to-age -private-key -i "$hostKey")"

    # 1. host.json shape
    if jq -e '.hostname and .user.name and .system' "$HOST_DIR/host.json" > /dev/null; then
        printSuccess "host.json is valid"
    else
        printError "host.json is malformed"
        fail=1
    fi

    # 2. user key decrypts
    if SOPS_AGE_KEY="$userAge" sops -d "$SECRETS" | jq -e '.userPassword and .userPrivateKey' > /dev/null; then
        printSuccess "secrets.json decrypts with the user key"
    else
        printError "User key cannot decrypt $SECRETS"
        fail=1
    fi

    # 3. host key decrypts — the lockout check
    if SOPS_AGE_KEY="$hostAge" sops -d --extract '["userPassword"]' "$SECRETS" > /dev/null; then
        printSuccess "Host key decrypts its own secrets"
    else
        printError "Host key cannot decrypt $SECRETS — first boot would lock you out"
        fail=1
    fi

    # 4. stored private key round-trips
    if SOPS_AGE_KEY="$userAge" sops -d --extract '["userPrivateKey"]' "$SECRETS" \
        | ssh-keygen -y -f /dev/stdin > /dev/null 2>&1; then
        printSuccess "Stored private key is valid"
    else
        printError "Stored private key is malformed"
        fail=1
    fi

    # 5. admin key (informational)
    if [[ -n $ADMIN_AGE ]]; then
        if sops -d --extract '["userPassword"]' "$SECRETS" > /dev/null 2>&1; then
            printSuccess "Admin key on this machine decrypts the secrets"
        else
            printInfo "No admin private key on this machine (fine on the target itself)"
        fi
    fi

    [[ $fail -eq 0 ]] || die "Verification failed"
}

# ── handover ─────────────────────────────────────────────────────────────
installRepo() {
    printStep

    run chown -R 1000:100 "$REPO_ROOT"
    printSuccess "Ownership: uid 1000 ($USERNAME)"

    local home="$TARGET_ROOT/home/$USERNAME"
    local target="$home/nixos-config"

    # Seed the user key
    local sshDir="$home/.ssh"
    run install -d -m 700 "$sshDir"
    run install -m 600 "$KEYS_DIR/id_$USERNAME" "$sshDir/id_$USERNAME"
    run install -m 644 "$KEYS_DIR/id_$USERNAME.pub" "$sshDir/id_$USERNAME.pub"
    run chown 1000:100 "$home" "$sshDir" "$sshDir/id_$USERNAME" "$sshDir/id_$USERNAME.pub"
    printSuccess "Seeded $sshDir/id_$USERNAME"

    # Move repo to conventional location
    if [[ $REPO_ROOT == "$target" ]]; then
        printSuccess "Repo is already at $target"
    elif [[ -e $target ]]; then
        printWarn "$target already exists. Leaving the repo at $REPO_ROOT"
    elif formConfirm "Move the repo to $target?" "y"; then
        run mv "$REPO_ROOT" "$target"
        REPO_ROOT="$target"
        cd "$REPO_ROOT"
        printSuccess "Moved repo to $target"
    else
        printInfo "Keeping the repo at $REPO_ROOT"
    fi

    # Record runtime location in host.json
    local hostJson="$REPO_ROOT/hosts/$HOSTNAME/host.json"
    local runtimePath="${REPO_ROOT#"$TARGET_ROOT"}"
    printDebug "repoPath: $runtimePath (from $REPO_ROOT)"
    jq --arg p "$runtimePath" '.repoPath = $p' "$hostJson" > "$hostJson.tmp"
    mv "$hostJson.tmp" "$hostJson"
    chown 1000:100 "$hostJson"
    printSuccess "Recorded repo location: $runtimePath"
}

# ── install ──────────────────────────────────────────────────────────────
installSystem() {
    printStep
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
                printInfo "Run when ready:"
                printInfo "  sudo nixos-rebuild switch --flake $flake"
                return 0
            fi

            local cmd=(nixos-rebuild "$action" --flake "$flake")
            printInfo "Command: ${cmd[*]}"
            "${cmd[@]}"
            APPLIED="$action"
            printSuccess "nixos-rebuild $action finished"
            ;;

        iso)
            # ISO: nixos-install to mounted target
            local cmd=(nixos-install --root "$TARGET_ROOT" --flake "$flake")
            printInfo "Command: ${cmd[*]}"
            if ! formConfirm "Install now?" "y"; then
                APPLIED="skipped"
                printInfo "Run when ready:"
                printInfo "  ${cmd[*]}"
                return 0
            fi
            "${cmd[@]}"
            APPLIED="installed"
            printSuccess "Installed $HOSTNAME to $TARGET_ROOT"
            ;;

        remote)
            # Remote: nixos-anywhere
            local target
            formInput target "SSH target" "user@hostname"

            local cmd=(nixos-anywhere --flake "$flake" "$target")
            printInfo "Command: ${cmd[*]}"
            if ! formConfirm "Deploy now?" "y"; then
                APPLIED="skipped"
                printInfo "Run when ready:"
                printInfo "  ${cmd[*]}"
                return 0
            fi
            "${cmd[@]}"
            APPLIED="deployed"
            printSuccess "Deployed $HOSTNAME to $target"
            ;;
    esac
}


# ── next steps ───────────────────────────────────────────────────────────
printNextSteps() {
    printHeader "Done"
    printInfo "Review and commit:"
    printInfo "  git -C $REPO_ROOT add . && git -C $REPO_ROOT commit -m 'feat: add host $HOSTNAME'"

    case "$APPLIED" in
        installed) printInfo "Then reboot into $HOSTNAME" ;;
        boot)      printInfo "Then reboot to activate the configuration" ;;
        switch)    printInfo "The configuration is live" ;;
        deployed)  printInfo "Deployment complete" ;;
        *)
            case "$METHOD" in
                local)
                    printInfo "Build skipped. Run when ready:"
                    printInfo "  sudo nixos-rebuild switch --flake $REPO_ROOT#$HOSTNAME"
                    ;;
                iso)
                    printInfo "Install skipped. Run when ready:"
                    printInfo "  nixos-install --root $TARGET_ROOT --no-root-passwd --flake $REPO_ROOT#$HOSTNAME"
                    ;;
                remote)
                    printInfo "Deploy skipped. Run when ready:"
                    printInfo "  nixos-anywhere --flake $REPO_ROOT#$HOSTNAME user@hostname"
                    ;;
            esac
            ;;
    esac
}


# ── main ─────────────────────────────────────────────────────────────────
main() {
    clear
    
    parseArgs "$@"
    validate
    resolveTarget

    # Scratch space for key material — removed on exit
    KEYS_DIR="$(mktemp -d)"
    chmod 700 "$KEYS_DIR"

    # Phase 1: gather all info via gum form
    gatherForm

    # Phase 2: write files
    generateKeys
    writeSopsYaml
    writeSecrets
    writeHostJson
    writeHardwareNix
    writeProfileNix
    writeDotfiles

    # Flakes ignore untracked files — stage them without committing
    run gitRepo add --intent-to-add .

    # Phase 3: verify
    verify

    # Phase 4: install (method-dependent)
    case "$METHOD" in
        local) installSystem ;;
        iso) installRepo; installSystem ;;
        remote) installSystem ;;
    esac

    printNextSteps
}

main "$@"