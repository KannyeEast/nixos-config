#!/usr/bin/env bash

#
# install.sh - bootstrap a new host for this config
#

# @TODO: 
# - Clean install methods 
#   - install from fresh nixos install
#   - install from bootable USB
#   - install via nixos-anywhere
# - Implement impermanence & disko
#   - Automatic disko generation or pull/copy existing config
#     - Make sure any pulls follow the flake-parts

set -Eeu -o pipefail

if [[ -z ${IN_NIX_SHELL:-} ]]; then
    printf 'Fetching dependencies...\n'
    exec nix-shell \
        -p age curl git jq mkpasswd nixos-install-tools openssh pciutils sops ssh-to-age util-linux \
        --run "$(printf '%q ' bash "$0" "$@")"
fi

# ── flags ────────────────────────────────────────────────────────────────
VERBOSE=false
ADMIN_KEY=""
PASSWORD_FILE=""
TARGET_ROOT=""

# ── future toggles ───────────────────────────────────────────────────────
# Implemented ahead of time, disabled until the matching Nix modules land.
# Flipping one here MUST be paired with the module change it mentions.

# Impermanence: the host key must live on the persisted tree, and
# modules/system/secrets.nix (sops.age.sshKeyPaths) must point at the
# same path. e.g. "/persist"
PERSIST_DIR=""

# Disko: it owns fileSystems and swapDevices, so hardware.nix must not
# duplicate them. Enable together with the Disko module in lib/mkHost.nix
USE_DISKO=false

# ── state ────────────────────────────────────────────────────────────────
# Set once during the resolve/detect phase, read-only afterwards
REPO_ROOT=""

_HOSTNAME=""
_HOST_DIR=""
_HOST_ANCHOR=""
_ROLES=()

_USERNAME=""
_USER_EMAIL=""
_USER_ANCHOR=""

_TIMEZONE=""
_LOCALE=""
_LOCALE_EXTRA=""

_WIFI='{}'

_SYSTEM=""
_STORAGE=""
_CPU=""
_GPU=()
_HW_MODULES=()

_KEYS_DIR=""
_HOST_KEY_DIR="/etc/ssh"
_HOST_KEY_FILE=""
_HOST_AGE=""
_USER_AGE=""
_USER_PUB=""
_ADMIN_AGE=""
_SECRETS=""

_DISKO_PENDING=false    # disks not formatted/mounted yet (USE_DISKO only)
_APPLIED=""             # what installSystem did: installed/switch/boot/skipped

# ── logging ──────────────────────────────────────────────────────────────
RED=$'\033[0;31m'
GREEN=$'\033[0;32m'
YELLOW=$'\033[1;33m'
BLUE=$'\033[0;34m'
BOLD=$'\033[1m'
DIM=$'\033[2m'
NC=$'\033[0m'

printHeader() {
    local title="$*" rule
    rule="$(printf '─%.0s' $(seq 1 $((54 - ${#title})) 2>/dev/null))"
    printf '\n%s── %s %s%s\n' "$BOLD$GREEN" "$title" "$rule" "$NC"
}

printSuccess() { printf '%s✓%s %s\n' "$GREEN" "$NC" "$*"; }
printError() { printf '%s✗%s %s\n' "$RED" "$NC" "$*" >&2; }
printWarn() { printf '%s!%s %s\n' "$YELLOW" "$NC" "$*"; }
printInfo() { printf '%sℹ%s %s\n' "$BLUE" "$NC" "$*"; }

# Only speaks when --verbose is set
printDebug() {
    [[ $VERBOSE == true ]] || return 0
    printf '%s  · %s%s\n' "$DIM" "$*" "$NC" >&2
}

trapError() {
    local code=$? cmd=$BASH_COMMAND line=${BASH_LINENO[0]} fn=${FUNCNAME[1]:-main}
    printError "'$cmd' failed (exit $code) at $fn():$line"
    exit "$code"
}
trap trapError ERR

cleanup() {
    [[ -n $_KEYS_DIR && -d $_KEYS_DIR ]] && rm -rf "$_KEYS_DIR"
    printf '\033[?25h' >&2
}
trap cleanup EXIT

# ── helpers ──────────────────────────────────────────────────────────────
gitRepo() { git -c safe.directory='*' "$@"; }

needsArg() { [[ -n ${2:-} ]] || { printError "Error: $1 requires an argument"; exit 1; }; }

# Run a side-effect command.
# Verbose: echo the command, run it in the foreground with all output visible.
# Quiet: capture the output, replay it only when the command fails
run() {
    if [[ $VERBOSE == true ]]; then
        printf '%s  $ %s%s\n' "$DIM" "$*" "$NC" >&2
        "$@"
        return
    fi

    local out rc=0
    out="$(mktemp)"
    "$@" > "$out" 2>&1 || rc=$?

    if ((rc != 0)); then
        printError "Command failed: $*"
        sed 's/^/    /' "$out" >&2
    fi

    rm -f "$out"
    return "$rc"
}

# Run a slow command behind a spinner, stdout is the command's stdout.
# Verbose skips the spinner entirely: the command runs in the foreground
# and its stderr goes to the terminal
spin() {
    local msg="$1"; shift
    local rc=0

    if [[ $VERBOSE == true ]]; then
        printf '%s  $ %s%s\n' "$DIM" "$*" "$NC" >&2
        "$@" || rc=$?
        return "$rc"
    fi

    local frames='⠋⠙⠹⠸⠼⠴⠦⠧⠇⠏' i=0 pid
    local out err
    out="$(mktemp)"; err="$(mktemp)"

    "$@" > "$out" 2> "$err" &
    pid=$!

    printf '\033[?25l' >&2
    while kill -0 "$pid" 2>/dev/null; do
        printf '\r  %s  %s%s%s ' "$msg" "$BOLD$BLUE" "${frames:i++%10:1}" "$NC" >&2
        sleep 0.08
    done
    printf '\r\033[K\033[?25h' >&2

    wait "$pid" || rc=$?
    if ((rc == 0)); then
        printf '%s✓%s %s\n' "$GREEN" "$NC" "$msg" >&2
    else
        printf '%s✗%s %s\n' "$RED" "$NC" "$msg" >&2
        tail -n 20 "$err" | sed 's/^/    /' >&2
    fi

    cat "$out"
    rm -f "$out" "$err"
    return "$rc"
}

# ask VAR QUESTION [DEFAULT] - required answer, loops until non-empty
ask() {
    local __var="$1" question="$2" default="${3:-}" reply
    if [[ -n $default ]]; then
        read -rp "$(printf '%s?%s %s [%s]: ' "$BLUE" "$NC" "$question" "$default")" reply
        reply="${reply:-$default}"
    else
        while [[ -z ${reply:-} ]]; do
            read -rp "$(printf '%s?%s %s: ' "$BLUE" "$NC" "$question")" reply
        done
    fi
    printf -v "$__var" '%s' "$reply"
}

# askOptional VAR QUESTION [DEFAULT] - empty answer is allowed
askOptional() {
    local __var="$1" question="$2" default="${3:-}" reply
    read -rp "$(printf '%s?%s %s [%s]: ' "$BLUE" "$NC" "$question" "${default:-none}")" reply
    printf -v "$__var" '%s' "${reply:-$default}"
}

# askList VAR QUESTION OPTION... - numbered menu, first option is the default
askList() {
    local __var="$1" question="$2"; shift 2
    local options=("$@") i reply
    printf '%s?%s %s\n' "$BLUE" "$NC" "$question"
    for i in "${!options[@]}"; do
        printf '    %2d) %s\n' "$((i + 1))" "${options[i]}"
    done
    while :; do
        read -rp "    choice [1]: " reply
        reply="${reply:-1}"
        [[ $reply =~ ^[0-9]+$ ]] && (( reply >= 1 && reply <= ${#options[@]} )) && break
        printError "pick 1-${#options[@]}"
    done
    printf -v "$__var" '%s' "${options[$((reply - 1))]}"
}

confirm() {
    local reply
    read -rp "$(printf '%s?%s %s [y/N]: ' "$YELLOW" "$NC" "$1")" reply
    [[ $reply =~ ^[Yy]$ ]]
}

# ── flags ────────────────────────────────────────────────────────────────
showFlags() {
    cat <<EOF
Usage: sudo ${0##*/} [OPTIONS]

Options:
      --admin-key     <PATH> Public half of the admin key
      --password-file <PATH> Read the hashed password from a file instead of prompting
      --root          <PATH> Install into a mounted target (auto-detects /mnt on the ISO)
  -v, --verbose              Show every command and its output as it runs
  -h, --help                 This message

Examples:
  sudo ./install.sh --admin-key /etc/nixos/id_admin.pub
  sudo ./install.sh --root /mnt

Description:
  Bootstrap a (new) host for this flake and install it. Creates or modifies:
    - host.json
    - host/user SSH Keys
    - secrets.json with userPassword, privateKey, and optionally wifi configuration
    - hardware.nix

  Then applies it (each step asks first):
    - mounted target: nixos-install
    - running system: nixos-rebuild switch/boot

EOF
}

parseArgs() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --admin-key) needsArg "$1" "${2:-}"; ADMIN_KEY="$2"; shift 2 ;;
            --password-file) needsArg "$1" "${2:-}"; PASSWORD_FILE="$2"; shift 2 ;;
            --root) needsArg "$1" "${2:-}"; TARGET_ROOT="$2"; shift 2 ;;
            -v|--verbose) VERBOSE=true; shift ;;
            -h|--help) showFlags; exit 0 ;;
            *) printError "Error: Unknown option: $1"; showFlags; exit 1 ;;
        esac
    done
}

# ── validate ─────────────────────────────────────────────────────────────
# Check every prerequisite up front
validate() {
    printHeader "Validating environment"
    local fail=0

    if grep -qi nixos /etc/os-release 2>/dev/null; then
        printSuccess "Verified NixOS"
    else
        printError "Not NixOS"
        fail=1
    fi

    # Writes /etc/ssh and chowns the user's home
    if [[ $EUID -eq 0 ]]; then
        printSuccess "Verified privileges"
    else
        printError "Failed to access /etc/. Script must be run as root"
        fail=1
    fi

    # Prompts for hostname, username, password
    if [[ -t 0 && -t 1 ]]; then
        printSuccess "Verified terminal"
    else
        printError "No TTY"
        fail=1
    fi

    if REPO_ROOT="$(gitRepo rev-parse --show-toplevel 2>/dev/null)"; then
        printSuccess "Verified config location: $REPO_ROOT"
    else
        printError "Failed to locate config. Not inside git worktree"
        fail=1
    fi

    if [[ -n ${REPO_ROOT:-} && -f $REPO_ROOT/flake.nix ]]; then
        printSuccess "Verified flake.nix"
    else
        printError "Failed to locate flake.nix"
        fail=1
    fi

    if [[ -n $PASSWORD_FILE ]]; then
        if [[ -r $PASSWORD_FILE ]]; then
            printSuccess "Verified password file"
        else
            printError "Failed to read: $PASSWORD_FILE"
            fail=1
        fi
    fi

    if [[ -n $ADMIN_KEY ]]; then
        if [[ -r $ADMIN_KEY ]] && grep -qE '^(ssh-ed25519|ssh-rsa) ' "$ADMIN_KEY"; then
            printSuccess "Verified admin key"
        else
            printError "Failed to locate admin key. $ADMIN_KEY is not a readable SSH key"
            fail=1
        fi
    fi

    [[ $fail -eq 0 ]] || return 1
    printSuccess "Validated environment"
}

# ── target ───────────────────────────────────────────────────────────────
# Decide where the installed system will live.
#   Running system: TARGET_ROOT stays empty, everything happens in place.
#   Installer ISO:  /etc/ssh is a tmpfs that dies at reboot, so the host
#                   key MUST go to the mounted target or first boot cannot
#                   decrypt its own secrets
resolveTarget() {
    if [[ -n $TARGET_ROOT ]]; then
        TARGET_ROOT="${TARGET_ROOT%/}"
        if [[ ! -d $TARGET_ROOT ]]; then
            printError "--root: $TARGET_ROOT is not a directory"
            exit 1
        fi
    elif grep -q 'VARIANT_ID=installer' /etc/os-release 2>/dev/null; then
        printDebug "installer ISO detected via /etc/os-release"
        if findmnt -M /mnt > /dev/null 2>&1; then
            TARGET_ROOT="/mnt"
            printDebug "target mount: $(findmnt -no SOURCE,FSTYPE -M /mnt)"
        elif [[ $USE_DISKO == true ]]; then
            # disko formats and mounts later (provisionTarget), after the
            # host's disko.nix exists
            TARGET_ROOT="/mnt"
            _DISKO_PENDING=true
            printInfo "Nothing mounted at /mnt - disko will format and mount during install"
        else
            printError "Running from the installer ISO but no target is mounted at /mnt"
            printInfo "Partition and mount the target first, or pass --root <PATH>"
            exit 1
        fi
    fi

    _HOST_KEY_DIR="${TARGET_ROOT}${PERSIST_DIR}/etc/ssh"
    printDebug "host key dir: $_HOST_KEY_DIR"

    if [[ -n $TARGET_ROOT ]]; then
        printSuccess "Install target: $TARGET_ROOT"
    fi
}

# ── identity ─────────────────────────────────────────────────────────────
# Hostname, roles, username, git email — everything the host is named by
resolveIdentity() {
    printHeader "Identity"

    # The ISO's own hostname/user are meaningless defaults
    local defHost defUser
    defHost="$(hostname)"
    defUser="${SUDO_USER:-}"
    [[ $defHost == nixos ]] && defHost=""
    [[ $defUser == root || $defUser == nixos ]] && defUser=""

    while :; do
        ask _HOSTNAME "Hostname" "$defHost"

        if [[ ! $_HOSTNAME =~ ^[a-z][a-z0-9-]{0,62}$ ]]; then
            printError "Error: Invalid hostname. Only lowercase letters, digits and hyphens are allowed"
            continue
        fi

        _HOST_DIR="$REPO_ROOT/hosts/$_HOSTNAME"

        if [[ -d $_HOST_DIR ]]; then
            printError "Error: hosts/$_HOSTNAME already exists"
            continue
        fi

        break
    done

    _SECRETS="hosts/$_HOSTNAME/secrets.json"
    printSuccess "New host: hosts/$_HOSTNAME"

    local base addons=() addon input ok
    local validAddons=(dev gaming media)

    askList base "System type" desktop server
    _ROLES=("$base")

    if [[ $base == desktop ]]; then
        while :; do
            askOptional input "Addons (${validAddons[*]})" "dev"
            read -ra addons <<< "$input"

            ok=true
            for addon in "${addons[@]}"; do
                if ! printf '%s\n' "${validAddons[@]}" | grep -qx "$addon"; then
                    printError "Error: Unknown addon - $addon"
                    ok=false
                fi
            done

            [[ $ok == false ]] && continue
            break
        done

        ((${#addons[@]})) && _ROLES+=("${addons[@]}")
    fi

    printSuccess "Roles: ${_ROLES[*]}"

    while :; do
        ask _USERNAME "Username" "$defUser"
        if [[ ! $_USERNAME =~ ^[a-z_][a-z0-9_-]{0,31}$ ]]; then
            printError "Error: Invalid username. Only lowercase letters, digits, hyphens, and underscores are allowed"
            continue
        fi
        break
    done

    _USER_ANCHOR="${_USERNAME}_${_HOSTNAME}"
    _HOST_ANCHOR="$_HOSTNAME"
    printDebug "sops anchors: &$_USER_ANCHOR (user), &$_HOST_ANCHOR (host)"

    ask _USER_EMAIL "git email" "$(gitRepo config user.email 2>/dev/null || true)"
}

# ── locale ───────────────────────────────────────────────────────────────
# Detected from the running environment, every value overridable
resolveLocale() {
    printHeader "Locale"

    _TIMEZONE="$(readlink -f /etc/localtime | sed 's|.*/zoneinfo/||')"
    _LOCALE=${LANG:-en_US.UTF-8}
    _LOCALE_EXTRA=${LC_CTYPE:-en_US.UTF-8}

    ask _TIMEZONE "Timezone" "${_TIMEZONE:-UTC}"
    ask _LOCALE "Locale" "$_LOCALE"
    ask _LOCALE_EXTRA "Extra locale" "$_LOCALE_EXTRA"
}

# ── wifi ─────────────────────────────────────────────────────────────────
# Guided per-network prompts. The editor is an opt-in escape hatch for
# advanced NetworkManager keys, never the entry point. Plaintext psk
# material only touches _KEYS_DIR (dies with the script) and ends up
# encrypted in secrets.json
resolveWifi() {
    printHeader "Wifi"
    confirm "Add wifi networks?" || return 0

    local name ssid psk psk2 profile edited n=0

    while :; do
        ask name "Network name"

        if jq -e --arg n "$name" 'has($n)' <<< "$_WIFI" > /dev/null; then
            printError "'$name' is already configured"
            continue
        fi

        ask ssid "SSID" "$name"

        while :; do
            read -rsp "$(printf '%s?%s Password (hidden): ' "$BLUE" "$NC")" psk
            printf '\n'
            read -rsp "$(printf '%s?%s Password (repeat): ' "$BLUE" "$NC")" psk2
            printf '\n'

            if [[ -z $psk || $psk != "$psk2" ]]; then
                printError "Empty or mismatched. Try again"
                continue
            fi
            if (( ${#psk} < 8 )); then
                printError "WPA-PSK needs 8-63 characters"
                continue
            fi
            break
        done

        profile="$(jq -n --arg id "$name" --arg ssid "$ssid" --arg psk "$psk" '{
            connection: { id: $id, type: "wifi" },
            wifi: { ssid: $ssid },
            "wifi-security": { "key-mgmt": "wpa-psk", psk: $psk }
        }')"

        # Every other keyfile setting, on request only
        # https://networkmanager.dev/docs/api/latest/nm-settings-keyfile.html
        if confirm "Edit advanced settings for '$name'?"; then
            local file="$_KEYS_DIR/wifi-$n.json"
            jq -n --argjson p "$profile" '{
                connection: { id: "", permissions: "", type: "wifi" },
                ipv4: { "dns-search": "", method: "" },
                ipv6: { "addr-gen-mode": "", "dns-search": "", method: "" },
                wifi: { "mac-address-blacklist": "", mode: "", ssid: "" },
                "wifi-security": { "auth-alg": "", "key-mgmt": "wpa-psk", psk: "" }
            } * $p' > "$file"

            "${EDITOR:-nano}" "$file"

            # Keep whatever was filled in, drop the blanks
            if edited="$(jq '
                    walk(
                        if type == "object"
                        then with_entries(select(.value != "" and .value != {}))
                        else .
                        end
                    )
                ' "$file" 2>/dev/null)"; then
                profile="$edited"
            else
                printWarn "Not valid JSON - keeping the basic profile for '$name'"
            fi
        fi

        _WIFI="$(jq --arg name "$name" --argjson p "$profile" '. + { ($name): $p }' <<< "$_WIFI")"
        printSuccess "Added '$name' (ssid: $ssid)"
        n=$((n + 1))

        confirm "Add another network?" || break
    done

    printSuccess "Wifi profiles: $(jq -r 'keys | join(", ")' <<< "$_WIFI")"
}

# ── hardware ─────────────────────────────────────────────────────────────
# Pure detection, no prompts: system, storage, cpu, gpu
detectHardware() {
    printHeader "Hardware"

    _SYSTEM="$(uname -m)-linux"
    printSuccess "System: $_SYSTEM"

    # Storage - on the ISO '/' is the live medium, so probe the target mount.
    # -e 7,11 keeps loop and rom devices out of the fallback
    local src dev rot
    src="$(findmnt -no SOURCE --target "${TARGET_ROOT:-/}" 2>/dev/null || true)"
    dev="$(lsblk -no PKNAME "$src" 2>/dev/null | head -n1 || true)"
    [[ -z $dev ]] && dev="$(lsblk -dno NAME -e 7,11 | head -n1)"
    printDebug "root source: ${src:-?} -> disk: ${dev:-?}"

    rot="$(lsblk -dno ROTA "/dev/$dev" 2>/dev/null || echo 0)"
    if [[ $rot == 1 ]]; then
        _STORAGE="hdd"
    else
        _STORAGE="ssd"
    fi
    printSuccess "Storage: $_STORAGE ($dev)"

    # CPU
    local vendor
    vendor="$(lscpu | grep 'Vendor ID' | awk -F: '{print $2}' | xargs)"
    printDebug "lscpu vendor: ${vendor:-?}"
    case "$vendor" in
        GenuineIntel) _CPU="intel" ;;
        AuthenticAMD) _CPU="amd" ;;
        *) _CPU="" ;;
    esac
    printSuccess "CPU: ${_CPU:-unknown}"

    # GPU - PCI display class, deduplicated, may be multiple (hybrid laptops)
    printDebug "\$ lspci -n -mm -d ::03xx"
    local vid
    while read -r vid; do
        printDebug "pci display vendor: $vid"
        case "$vid" in
            10de) _GPU+=("nvidia") ;;
            1002) _GPU+=("amd") ;;
            8086) _GPU+=("intel") ;;
        esac
    done < <(lspci -n -mm -d ::03xx | awk -F'"' '{print $4}')

    if ((${#_GPU[@]})); then
        mapfile -t _GPU < <(printf '%s\n' "${_GPU[@]}" | awk '!seen[$0]++')
    fi
    printSuccess "GPU: ${_GPU[*]:-none}"
}

# ── nixos-hardware ───────────────────────────────────────────────────────
# Laptops only, by choice: the common-* set is tuned for them and guessing
# for desktops risks more than it fixes.
# Tries the dedicated board module first, falls back to common-*, and the
# final list is always editable

dmi() { cat "/sys/class/dmi/id/$1" 2>/dev/null || true; }

# Module names from the flake-locked nixos-hardware revision (spin target)
fetchHardwareModules() {
    local rev ref="github:NixOS/nixos-hardware"

    rev="$(jq -r '.nodes["nixos-hardware"].locked.rev // empty' "$REPO_ROOT/flake.lock" 2>/dev/null || true)"
    [[ -n $rev ]] && ref="github:NixOS/nixos-hardware/$rev"

    local args=("$ref#nixosModules"
        --apply builtins.attrNames --json
        --extra-experimental-features 'nix-command flakes')

    local json
    json="$(timeout 120 nix eval "${args[@]}")" \
        || json="$(timeout 120 nix eval "${args[@]}" --refresh)" \
        || return 1
    jq -r '.[]' <<< "$json"
}

resolveModules() {
    compgen -G '/sys/class/power_supply/BAT*' > /dev/null || return 0

    printHeader "nixos-hardware"
    printInfo "DMI: $(dmi sys_vendor) / $(dmi product_name) / board $(dmi board_name)"

    local modules
    mapfile -t modules < <(spin "Fetching modules" fetchHardwareModules)

    if ((${#modules[@]} == 0)); then
        printWarn "No module list. Manual entries only"
        local mods
        printInfo "nixos-hardware: https://github.com/NixOS/nixos-hardware"
        askOptional mods "nixos-hardware modules (space separated)" ""
        read -ra _HW_MODULES <<< "$mods"
        return 0
    fi

    printSuccess "Fetched ${#modules[@]} modules"

    # "ROG Zephyrus G16 GU605MY_GU605MY" -> "rog-zephyrus-g16-gu605my-gu605my"
    local slug match=""
    slug="$(dmi board_name)"
    slug="${slug,,}"
    slug="${slug//[^a-z0-9]/-}"
    slug="$(sed -E 's/-+/-/g; s/^-//; s/-$//' <<< "$slug")"
    printDebug "board slug: ${slug:-none}"

    if [[ -n $slug ]]; then
        match="$(printf '%s\n' "${modules[@]}" | grep -x ".*-${slug}" | head -n1 || true)"
    fi

    if [[ -n $match ]]; then
        printSuccess "Matched model: $match"
        if confirm "Use $match?"; then
            _HW_MODULES=("$match")
        else
            printInfo "Declined. Using common modules instead"
        fi
    else
        printInfo "No dedicated module found for '$(dmi product_name)'. Using common modules"
    fi

    if ((${#_HW_MODULES[@]} == 0)); then
        local want=() m

        [[ -n $_CPU ]] && want+=("common-cpu-$_CPU")

        for m in "${_GPU[@]}"; do
            want+=("common-gpu-$m")
        done

        want+=("common-pc-laptop")

        if [[ $_STORAGE == "hdd" ]]; then
            want+=("common-pc-laptop-hdd")
        else
            want+=("common-pc-ssd")
        fi

        # Keep only names that actually exist upstream
        for m in "${want[@]}"; do
            if printf '%s\n' "${modules[@]}" | grep -qx "$m"; then
                _HW_MODULES+=("$m")
            else
                printWarn "Skipping $m (not in nixos-hardware)"
            fi
        done
    fi

    printSuccess "Modules: ${_HW_MODULES[*]:-none}"

    local mods
    printInfo "nixos-hardware: https://github.com/NixOS/nixos-hardware"
    askOptional mods "nixos-hardware modules" "${_HW_MODULES[*]}"
    read -ra _HW_MODULES <<< "$mods"
}

# ── summary ──────────────────────────────────────────────────────────────
# Last stop before anything is written to disk
printSummary() {
    printHeader "Summary"

    printf '    %s%-10s%s %s\n' \
        "$DIM" "host"     "$NC" "$_HOSTNAME" \
        "$DIM" "system"   "$NC" "$_SYSTEM" \
        "$DIM" "roles"    "$NC" "${_ROLES[*]:-none}" \
        "$DIM" "user"     "$NC" "$_USERNAME <$_USER_EMAIL>" \
        "$DIM" "cpu"      "$NC" "${_CPU:-unknown}" \
        "$DIM" "gpu"      "$NC" "${_GPU[*]:-none}" \
        "$DIM" "storage"  "$NC" "$_STORAGE" \
        "$DIM" "modules"  "$NC" "${_HW_MODULES[*]:-none}" \
        "$DIM" "locale"   "$NC" "$_TIMEZONE / $_LOCALE / $_LOCALE_EXTRA" \
        "$DIM" "host key" "$NC" "$_HOST_KEY_DIR/ssh_host_ed25519_key"

    if [[ -n $TARGET_ROOT ]]; then
        printf '    %s%-10s%s %s\n' "$DIM" "target" "$NC" "$TARGET_ROOT"
    fi

    echo
    confirm "Proceed?" || { printInfo "Aborted - nothing was written"; exit 0; }
}

# ── keys ─────────────────────────────────────────────────────────────────
# All three recipients of secrets.json in one place:
#   host  - decrypts at activation (sops-nix, via sshKeyPaths)
#   user  - generated into the temp dir, stored in secrets.json, and seeded
#           into the target ~/.ssh by installRepo. sops-nix owns that path
#           and replaces the seeded file with a symlink into /run/secrets
#           on its first successful activation
#   admin - one global recipient for the whole repo, the user decides who
#           that is. An existing &admin anchor in .sops.yaml is the source
#           of truth, a key file only seeds the anchor the first time
generateKeys() {
    printHeader "Keys"

    # Host key - reused when present. On the ISO it is written to the
    # mounted target so first boot decrypts with the exact key in use here.
    # With disko pending there is no target yet: generate into the temp dir,
    # provisionTarget places it once the disks are mounted
    if [[ $_DISKO_PENDING == true ]]; then
        _HOST_KEY_FILE="$_KEYS_DIR/ssh_host_ed25519_key"
        printDebug "no target mounted yet - host key deferred to $_HOST_KEY_FILE"
    else
        _HOST_KEY_FILE="$_HOST_KEY_DIR/ssh_host_ed25519_key"
    fi

    if [[ -f "$_HOST_KEY_FILE.pub" ]]; then
        printSuccess "Host key: reusing $_HOST_KEY_FILE"
    else
        [[ $_DISKO_PENDING == true ]] || install -d -m 755 "$_HOST_KEY_DIR"
        run ssh-keygen -t ed25519 -N "" -C "root@$_HOSTNAME" -f "$_HOST_KEY_FILE"
        printSuccess "Host key: generated $_HOST_KEY_FILE"
    fi
    printDebug "fingerprint: $(ssh-keygen -lf "$_HOST_KEY_FILE.pub")"
    printDebug "\$ ssh-to-age < $_HOST_KEY_FILE.pub"
    _HOST_AGE="$(ssh-to-age < "$_HOST_KEY_FILE.pub")"
    printInfo "host age:  $_HOST_AGE"

    # User key
    local userKey="$_KEYS_DIR/id_$_USERNAME"
    run ssh-keygen -t ed25519 -N "" -C "$_USERNAME@$_HOSTNAME" -f "$userKey"
    chmod 600 "$userKey"
    _USER_PUB="$(< "$userKey.pub")"
    printDebug "fingerprint: $(ssh-keygen -lf "$userKey.pub")"
    printDebug "\$ ssh-to-age < $userKey.pub"
    _USER_AGE="$(ssh-to-age < "$userKey.pub")"
    printSuccess "User key: generated"
    printInfo "user age:  $_USER_AGE"

    # Admin key
    local pub="${ADMIN_KEY:-$REPO_ROOT/id_admin.pub}"
    local existing="" derived=""

    [[ -f .sops.yaml ]] \
        && existing="$(sed -n 's/^[[:space:]]*- &admin \(age1[0-9a-z]*\).*/\1/p' .sops.yaml | head -n1)"
    [[ -r $pub ]] && derived="$(ssh-to-age < "$pub")"
    printDebug "admin: existing anchor ${existing:-none}, derived ${derived:-none}"

    if [[ -n $existing ]]; then
        _ADMIN_AGE="$existing"
        printSuccess "Admin key: using the &admin anchor from .sops.yaml"
        if [[ -n $derived && $derived != "$existing" ]]; then
            printWarn "$pub derives $derived, which does NOT match the &admin anchor"
            printWarn "Secrets are encrypted to the anchor - that key file cannot decrypt them"
            printInfo "To rotate: replace the anchor, then run 'sops updatekeys' on every secrets.json"
        fi
    elif [[ -n $derived ]]; then
        _ADMIN_AGE="$derived"
        printSuccess "Admin key: seeded from $pub"
    else
        printWarn "No admin key. Secrets will be readable by this host and user only"
        printInfo "Pass --admin-key or place the key at $REPO_ROOT to add one"
    fi
    [[ -n $_ADMIN_AGE ]] && printInfo "admin age: $_ADMIN_AGE"

    return 0
}

# ── .sops.yaml ───────────────────────────────────────────────────────────
writeSopsYaml() {
    printHeader ".sops.yaml"

    if [[ ! -f .sops.yaml ]]; then
        cat > .sops.yaml <<EOF
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
            || { printError ".sops.yaml: marker '$2' not found"; exit 1; }
        mv .sops.yaml.tmp .sops.yaml
    }

    # Re-runs for the same host replace their entries instead of stacking
    # duplicates - duplicate anchors silently resolve to the last one and
    # leave stale keys lying around
    printDebug "scrubbing previous $_HOSTNAME entries"
    awk -v userAnchor="    - &$_USER_ANCHOR " \
        -v hostAnchor="    - &$_HOST_ANCHOR " \
        -v rulePrefix="  - path_regex: hosts/$_HOSTNAME/secrets" '
        index($0, userAnchor) == 1 { next }
        index($0, hostAnchor) == 1 { next }
        index($0, rulePrefix) == 1 { skip = 1; next }
        skip && (/^  - / || /^[^ ]/) { skip = 0 }
        skip { next }
        { print }
    ' .sops.yaml > .sops.yaml.tmp
    mv .sops.yaml.tmp .sops.yaml

    if [[ -n $_ADMIN_AGE ]] && ! grep -q -- "- &admin " .sops.yaml; then
        printDebug "inserting &admin $_ADMIN_AGE"
        insertBefore "    - &admin $_ADMIN_AGE" "  - &hosts:"
    fi

    printDebug "inserting &$_USER_ANCHOR $_USER_AGE"
    insertBefore "    - &$_USER_ANCHOR $_USER_AGE" "  - &hosts:"
    printDebug "inserting &$_HOST_ANCHOR $_HOST_AGE"
    insertBefore "    - &$_HOST_ANCHOR $_HOST_AGE" "creation_rules:"
    printDebug "appending creation rule for ${_SECRETS//./\\.}\$"

    {
        printf '  - path_regex: %s$\n' "${_SECRETS//./\\.}"
        printf '    key_groups:\n'
        printf '      - age:\n'
        [[ -n $_ADMIN_AGE ]] && printf '          - *admin\n'
        printf '          - *%s\n' "$_USER_ANCHOR"
        printf '          - *%s\n' "$_HOST_ANCHOR"
    } >> .sops.yaml

    printSuccess "Added recipients and creation rule"
}

# ── secrets.json ─────────────────────────────────────────────────────────
writeSecrets() {
    printHeader "secrets.json"

    local hash
    if [[ -n $PASSWORD_FILE ]]; then
        hash="$(< "$PASSWORD_FILE")"
    else
        printInfo "Set the login password for '$_USERNAME':"
        hash="$(mkpasswd -m sha-512)"
    fi

    mkdir -p "$(dirname "$_SECRETS")"

    # --rawfile keeps the key byte-for-byte. "$(< file)" would strip the
    # trailing newline and OpenSSH rejects private keys without it
    printDebug "\$ jq -n --arg pw ... --rawfile key ... > $_SECRETS"
    jq -n \
        --arg pw  "$hash" \
        --rawfile key "$_KEYS_DIR/id_$_USERNAME" \
        --argjson wifi "$_WIFI" \
        '{ userPassword: $pw, userPrivateKey: $key }
         + (if $wifi == {} then {} else { wifi: $wifi } end)' \
        > "$_SECRETS"

    run sops --encrypt --in-place "$_SECRETS"
    printSuccess "Encrypted $_SECRETS"
}

# ── host.json ────────────────────────────────────────────────────────────
writeHostJson() {
    printHeader "host.json"

    local adminPub=""
    [[ -r ${ADMIN_KEY:-$REPO_ROOT/id_admin.pub} ]] \
        && adminPub="$(< "${ADMIN_KEY:-$REPO_ROOT/id_admin.pub}")"

    local rolesJson gpuJson modulesJson keysJson
    rolesJson="$(printf '%s\n' "${_ROLES[@]}" | jq -R . | jq -sc 'map(select(. != ""))')"
    gpuJson="$(printf '%s\n' "${_GPU[@]:-}" | jq -R . | jq -sc 'map(select(. != ""))')"
    modulesJson="$(printf '%s\n' "${_HW_MODULES[@]:-}" | jq -R . | jq -sc 'map(select(. != ""))')"
    keysJson="$(printf '%s\n%s\n' "$_USER_PUB" "$adminPub" | jq -R . | jq -sc 'map(select(. != ""))')"

    mkdir -p "$_HOST_DIR"

    jq -n \
        --arg hostname "$_HOSTNAME" \
        --arg system "$_SYSTEM" \
        --arg name "$_USERNAME" \
        --arg email "$_USER_EMAIL" \
        --arg cpu "$_CPU" \
        --arg storage "$_STORAGE" \
        --arg tz "$_TIMEZONE" \
        --arg locale "$_LOCALE" \
        --arg extra "$_LOCALE_EXTRA" \
        --argjson roles "$rolesJson" \
        --argjson gpu "$gpuJson" \
        --argjson modules "$modulesJson" \
        --argjson keys "$keysJson" \
        '{
            hostname: $hostname,
            system: $system,
            roles: $roles,
            user: {
                name: $name,
                email: $email,
                sshKeys: $keys
            },
            hardware: {
                cpu: $cpu,
                gpu: $gpu,
                storage: $storage,
                modules: $modules
            },
            locale: {
                timeZone: $tz,
                localeDefault: $locale,
                localeExtra: $extra
            }
        }' > "$_HOST_DIR/host.json"

    printSuccess "Wrote $_HOST_DIR/host.json"
}

# ── hardware.nix ─────────────────────────────────────────────────────────
writeHardwareNix() {
    printHeader "hardware.nix"

    local genArgs=(--show-hardware-config)
    # --root needs mounted filesystems - with disko pending detect from the
    # live system instead (same machine, and disko owns fileSystems anyway)
    [[ -n $TARGET_ROOT && $_DISKO_PENDING == false ]] && genArgs+=(--root "$TARGET_ROOT")

    local body
    printDebug "\$ nixos-generate-config ${genArgs[*]}"
    body="$(nixos-generate-config "${genArgs[@]}" \
        | sed -e '/^ *#/d' \
              -e '/^{ config, lib, pkgs, modulesPath, \.\.\. }:$/d' \
              -e '/^{$/d' \
              -e '/^}$/d')"

    # Disko owns fileSystems and swapDevices - with it enabled they must
    # not be duplicated here. Inactive while USE_DISKO=false
    if [[ $USE_DISKO == true ]]; then
        body="$(awk '
            /^[[:space:]]*(fileSystems|swapDevices)/ {
                skip = 1
                if (/;[[:space:]]*$/) skip = 0    # single-line form
                next
            }
            skip {
                if (/^[[:space:]]*[}\]];[[:space:]]*$/) skip = 0
                next
            }
            { print }' <<< "$body")"
        printInfo "Stripped fileSystems/swapDevices (disko owns them)"
    fi

    body="$(sed -e 's/^./        &/' <<< "$body" | cat -s)"

    mkdir -p "$_HOST_DIR"

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
    } > "$_HOST_DIR/hardware.nix"

    printSuccess "Wrote $_HOST_DIR/hardware.nix"
}

# ── profile.nix ──────────────────────────────────────────────────────────
writeProfileNix() {
    printHeader "profile.nix"

    mkdir -p "$_HOST_DIR"

    cat > "$_HOST_DIR/profile.nix" <<'EOF'
{ ... }:
let
    inherit (builtins.fromJSON (builtins.readFile ./host.json)) hostname;
in
{
    imports = [
        (import ../../lib/mkHost.nix ./.)
    ];

    flake.modules.nixos."${hostname}Configuration" = { pkgs, ... }:
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
                terminal = pkgs.alacritty;
                xkb.layout = "us";
                xkb.variant = "";

                fonts = {
                    packages = [ ];
                    defaults.serif = [ ];
                    defaults.sans = [ ];
                    defaults.mono = [ ];
                };
            };

            profile.desktop = {
                browser = {
                    extensions.install = { };
                    extensions.settings = { };
                    bookmarks.extra = [ ];
                    tabs.extra = { };
                    tabs.exclude = [ ];
                    spaces.extra = { };
                };

                displayManager.settings = { };
                displayManager.extraPackages = [ ];
            };
        };
    };
}
EOF

    printSuccess "Wrote $_HOST_DIR/profile.nix"
}

# ── dotfiles ─────────────────────────────────────────────────────────────
# hosts/<host>/home mirrors $HOME (see modules/desktop/dotfiles.nix), so a
# dotfiles source must use the same layout (.zshrc at its root, .config/...).
# Optionally seeded from an existing repo or folder, then topped up with
# niri's default config so the first login has working keybindings
writeDotfiles() {
    printHeader "dotfiles"

    local dest="$_HOST_DIR/home"
    mkdir -p "$dest"

    # Existing dotfiles - copied, not linked: this host owns its copy.
    # The input is prefilled with the repo location so completing a local
    # path is quick; clear the line to skip, or paste a git URL
    local src
    read -r -e -i "$PWD/" \
        -p "$(printf '%s?%s %s: ' "$BLUE" "$NC" "Seed dotfiles from (git URL or local path, empty = skip)")" src

    # read does not expand a leading ~ - do it here, against the invoking
    # user's home when running under sudo
    if [[ $src == "~"* ]]; then
        local h="${SUDO_USER:-}"
        if [[ -n $h && $h != root ]]; then h="/home/$h"; else h="$HOME"; fi
        src="$h${src#\~}"
        printDebug "expanded source: $src"
    fi

    if [[ -z $src || ${src%/} == "$PWD" ]]; then
        printInfo "Not seeding dotfiles"
    elif [[ -d $src ]]; then
        printDebug "\$ cp -rT $src $dest"
        cp -rT "$src" "$dest"
        rm -rf "$dest/.git"
        printSuccess "Copied dotfiles from $src"
    elif [[ -n $src ]]; then
        if run gitRepo clone --depth 1 "$src" "$_KEYS_DIR/dotfiles"; then
            cp -rT "$_KEYS_DIR/dotfiles" "$dest"
            rm -rf "$dest/.git"
            printSuccess "Cloned dotfiles from $src"
        else
            printWarn "Could not fetch $src - continuing without"
        fi
    fi

    # niri must have its initial keybindings - only seed the default when
    # the dotfiles source did not bring its own config
    if [[ -f $dest/.config/niri/config.kdl ]]; then
        printSuccess "niri config provided by the dotfiles source"
        return 0
    fi

    mkdir -p "$dest/.config/niri"

    # Pinned - 'main' would mean the config changes under you between installs
    local rev="v26.04"
    local url="https://raw.githubusercontent.com/YaLTeR/niri/$rev/resources/default-config.kdl"

    if ! run curl -fsSL "$url" -o "$dest/.config/niri/config.kdl"; then
        printWarn "Could not fetch niri's default config. Skipping"
        return 0
    fi

    # `spawn` takes an argv and does NOT expand variables, so the stock
    # `spawn "$TERMINAL"` silently fails. `terminal` is our alias binary
    sed -i \
        -e 's|Mod+T hotkey-overlay-title="Open a Terminal: alacritty" { spawn "alacritty"; }|Mod+T hotkey-overlay-title="Open a Terminal" { spawn "terminal"; }|' \
        "$dest/.config/niri/config.kdl"

    printSuccess "Seeded $dest/.config/niri/config.kdl"
}

# ── verify ───────────────────────────────────────────────────────────────
# Every failure mode that locked us out before is checked here, byte-exact
verify() {
    printHeader "Verifying"
    local fail=0

    local userKey="$_KEYS_DIR/id_$_USERNAME"
    local hostKey="$_HOST_KEY_FILE"

    local userAge hostAge
    printDebug "\$ ssh-to-age -private-key -i $userKey"
    userAge="$(ssh-to-age -private-key -i "$userKey")"
    printDebug "\$ ssh-to-age -private-key -i $hostKey"
    hostAge="$(ssh-to-age -private-key -i "$hostKey")"

    # 1. host.json shape
    printDebug "\$ jq -e '.hostname and .user.name and .system' $_HOST_DIR/host.json"
    if jq -e '.hostname and .user.name and .system' "$_HOST_DIR/host.json" > /dev/null; then
        printSuccess "host.json is valid"
    else
        printError "host.json is malformed"
        fail=1
    fi

    # 2. user key decrypts
    printDebug "\$ SOPS_AGE_KEY=<user> sops -d $_SECRETS"
    if SOPS_AGE_KEY="$userAge" sops -d "$_SECRETS" | jq -e '.userPassword and .userPrivateKey' > /dev/null; then
        printSuccess "secrets.json decrypts with the user key"
    else
        printError "User key cannot decrypt $_SECRETS"
        fail=1
    fi

    # 3. host key decrypts - this is the lockout check
    printDebug "\$ SOPS_AGE_KEY=<host> sops -d --extract '[\"userPassword\"]' $_SECRETS"
    if SOPS_AGE_KEY="$hostAge" sops -d --extract '["userPassword"]' "$_SECRETS" > /dev/null; then
        printSuccess "Host key decrypts its own secrets"
    else
        printError "Host key cannot decrypt $_SECRETS - first boot would lock you out"
        fail=1
    fi

    # 4. stored private key round-trips
    # --extract keeps the stored bytes exactly - piping through jq -r would
    # append a newline and hide a truncated key
    if SOPS_AGE_KEY="$userAge" sops -d --extract '["userPrivateKey"]' "$_SECRETS" \
        | ssh-keygen -y -f /dev/stdin > /dev/null 2>&1; then
        printSuccess "Stored private key is valid"
    else
        printError "Stored private key is malformed"
        fail=1
    fi

    # 5. admin key decrypts (informational - the admin's private key
    # usually lives on another machine)
    if [[ -n $_ADMIN_AGE ]]; then
        if sops -d --extract '["userPassword"]' "$_SECRETS" > /dev/null 2>&1; then
            printSuccess "Admin key on this machine decrypts the secrets"
        else
            printInfo "No admin private key on this machine (fine on the target itself)"
        fi
    fi

    [[ $fail -eq 0 ]] || { printError "Verification failed"; exit 1; }
}

# ── handover ─────────────────────────────────────────────────────────────
# Hand everything to the new user: uid 1000 ownership (pinned in
# modules/system/user.nix - single-user config), a bootstrap copy of the
# user key, and the repo at the location the dotfiles module expects
installRepo() {
    printHeader "Handover"

    run chown -R 1000:100 "$REPO_ROOT"
    printSuccess "Ownership: uid 1000 ($_USERNAME)"

    local home="$TARGET_ROOT/home/$_USERNAME"
    local target="$home/nixos-config"

    # Seed the user key. Chicken-and-egg otherwise: the only other copy
    # lives inside secrets.json, which needs this key (or the host key) to
    # open. sops-nix owns this path and swaps the file for a /run/secrets
    # symlink once it activates successfully - until then the seed is what
    # lets the user decrypt and debug
    local sshDir="$home/.ssh"
    run install -d -m 700 "$sshDir"
    run install -m 600 "$_KEYS_DIR/id_$_USERNAME" "$sshDir/id_$_USERNAME"
    run install -m 644 "$_KEYS_DIR/id_$_USERNAME.pub" "$sshDir/id_$_USERNAME.pub"
    run chown 1000:100 "$home" "$sshDir" "$sshDir/id_$_USERNAME" "$sshDir/id_$_USERNAME.pub"
    printSuccess "Seeded $sshDir/id_$_USERNAME"

    # The repo can live anywhere - its location is recorded in host.json
    # below. Moving it to the conventional spot is just the tidy default
    if [[ $REPO_ROOT == "$target" ]]; then
        printSuccess "Repo is already at $target"
    elif [[ -e $target ]]; then
        printWarn "$target already exists. Leaving the repo at $REPO_ROOT"
    elif confirm "Move the repo to $target?"; then
        run mv "$REPO_ROOT" "$target"
        REPO_ROOT="$target"
        cd "$REPO_ROOT"        # our old cwd is now a dangling inode
        printSuccess "Moved repo to $target"
    else
        printInfo "Keeping the repo at $REPO_ROOT"
    fi

    # Record the runtime location in host.json - the single edit point the
    # modules (dotfiles symlinks, nh) read the repo path from.
    # Stripping TARGET_ROOT turns the install-time path into the boot-time one
    local hostJson="$REPO_ROOT/hosts/$_HOSTNAME/host.json"
    local runtimePath="${REPO_ROOT#"$TARGET_ROOT"}"
    printDebug "repoPath: $runtimePath (from $REPO_ROOT)"
    jq --arg p "$runtimePath" '.repoPath = $p' "$hostJson" > "$hostJson.tmp"
    mv "$hostJson.tmp" "$hostJson"
    chown 1000:100 "$hostJson"
    printSuccess "Recorded repo location: $runtimePath"
}

# ── provision ────────────────────────────────────────────────────────────
# Disko pending only: format and mount the disks declared in the host's
# disko.nix (which exists by now), then place the deferred host key.
# Inactive while USE_DISKO=false
provisionTarget() {
    [[ $_DISKO_PENDING == true ]] || return 0

    printHeader "Disks"
    printWarn "disko will DESTROY the disks declared in hosts/$_HOSTNAME/disko.nix"
    confirm "Format and mount now?" || { printError "No mounted target - cannot continue"; exit 1; }

    # --yes-wipe-all-disks: disko's own prompt would hang inside run()
    local cmd=(nix run github:nix-community/disko/latest --
        --mode destroy,format,mount --yes-wipe-all-disks
        --flake "$REPO_ROOT#$_HOSTNAME")
    printInfo "Running: ${cmd[*]}"
    "${cmd[@]}"
    printSuccess "Disks formatted and mounted at $TARGET_ROOT"

    run install -d -m 755 "$_HOST_KEY_DIR"
    run install -m 600 "$_KEYS_DIR/ssh_host_ed25519_key" "$_HOST_KEY_DIR/ssh_host_ed25519_key"
    run install -m 644 "$_KEYS_DIR/ssh_host_ed25519_key.pub" "$_HOST_KEY_DIR/ssh_host_ed25519_key.pub"
    _HOST_KEY_FILE="$_HOST_KEY_DIR/ssh_host_ed25519_key"
    _DISKO_PENDING=false
    printSuccess "Placed the host key on the target"
}

# ── install ──────────────────────────────────────────────────────────────
# Apply the configuration. The command depends on the environment:
#   mounted target (ISO/--root) -> nixos-install
#   running system              -> nixos-rebuild switch or boot
# Output streams directly - this is the long part and progress matters
installSystem() {
    printHeader "Install"

    local flake="$REPO_ROOT#$_HOSTNAME"

    if [[ -n $TARGET_ROOT ]]; then
        # --no-root-passwd: users are declarative (mutableUsers = false)
        local cmd=(nixos-install --root "$TARGET_ROOT" --no-root-passwd --flake "$flake")
        printInfo "Command: ${cmd[*]}"
        if ! confirm "Install now?"; then
            _APPLIED="skipped"
            return 0
        fi
        "${cmd[@]}"
        _APPLIED="installed"
        printSuccess "Installed $_HOSTNAME to $TARGET_ROOT"
    else
        local action
        askList action "Apply the configuration" \
            "switch - build and activate now" \
            "boot   - activate on next reboot" \
            "skip   - just print the command"
        action="${action%% *}"

        if [[ $action == skip ]]; then
            _APPLIED="skipped"
            return 0
        fi

        local cmd=(nixos-rebuild "$action" --flake "$flake")
        printInfo "Command: ${cmd[*]}"
        "${cmd[@]}"
        _APPLIED="$action"
        printSuccess "nixos-rebuild $action finished"
    fi
}

# ── next steps ───────────────────────────────────────────────────────────
printNextSteps() {
    printHeader "Done"
    printInfo "Review and commit:"
    printInfo "git -C $REPO_ROOT add . && git -C $REPO_ROOT commit -m 'feat: add host $_HOSTNAME'"

    case "$_APPLIED" in
        installed) printInfo "Then reboot into $_HOSTNAME" ;;
        boot)      printInfo "Then reboot to activate the configuration" ;;
        switch)    printInfo "The configuration is live" ;;
        *)
            if [[ -n $TARGET_ROOT ]]; then
                printInfo "Install skipped. Run when ready:"
                printInfo "nixos-install --root $TARGET_ROOT --no-root-passwd --flake $REPO_ROOT#$_HOSTNAME"
            else
                printInfo "Build skipped. Run when ready:"
                printInfo "sudo nixos-rebuild switch --flake $REPO_ROOT#$_HOSTNAME"
            fi
            ;;
    esac
}

# ── main ─────────────────────────────────────────────────────────────────
main() {
    clear

    # environment
    parseArgs "$@"
    validate || exit 1
    cd "$REPO_ROOT"
    resolveTarget

    # scratch space for key material and the wifi template - removed on exit
    _KEYS_DIR="$(mktemp -d)"
    chmod 700 "$_KEYS_DIR"

    # gather - prompts and detection, nothing written yet
    resolveIdentity
    resolveLocale
    resolveWifi
    detectHardware
    resolveModules
    printSummary

    # write - only after the summary is confirmed
    generateKeys
    writeSopsYaml
    writeSecrets
    writeHostJson
    writeHardwareNix
    writeProfileNix
    writeDotfiles

    # flakes ignore untracked files - stage them without committing
    run gitRepo add --intent-to-add .

    # check
    verify

    # install
    provisionTarget
    installRepo
    installSystem
    printNextSteps
}

main "$@"
