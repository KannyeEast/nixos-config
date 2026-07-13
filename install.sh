#!/usr/bin/env nix-shell
#!nix-shell -i bash -p age bash git jq mkpasswd nixos-install-tools openssh pciutils sops ssh-to-age
#
# install.sh - bootstrap a new host for this config.
#
set -Eeu -o pipefail

# ── init ──────────────────────────────────────────────────────────────
DRY_RUN=false
VERBOSE=false
ADMIN_KEY=""
PASSWORD_FILE=""
REPO_ROOT=""

# ── logging ──────────────────────────────────────────────────────────────
RED=$'\033[0;31m';
GREEN=$'\033[0;32m';
YELLOW=$'\033[1;33m'
BLUE=$'\033[0;34m';
BOLD=$'\033[1m';
NC=$'\033[0m'

printHeader() { printf '\n%s== %s ==%s\n' "$BOLD$GREEN" "$*" "$NC"; }
printSuccess() { printf '%s✓%s %s\n' "$GREEN" "$NC" "$*"; }
printError() { printf '%s✗%s %s\n' "$RED" "$NC" "$*" >&2; }
printWarn() { printf '%s!%s %s\n' "$YELLOW" "$NC" "$*"; }
printInfo() { printf '%sℹ%s %s\n' "$BLUE" "$NC" "$*"; }

trapError() {
    local code=$? cmd=$BASH_COMMAND line=${BASH_LINENO[0]} fn=${FUNCNAME[1]:-main}
    printError "'$cmd' failed (exit $code) at $fn():$line"
    exit "$code"
}
trap trapError ERR

# ── flags ──────────────────────────────────────────────────────────────
showFlags() {
    cat <<EOF
Usage: sudo ${0##*/} [OPTIONS]
 
Options:
      --admin-key      PATH  Public half of the admin key
      --password-file  PATH  Read the hashed password from a file instead of prompting
  -n, --dry-run              Print what would happen. Writes nothing
  -v, --verbose              Trace execution
  -h, --help                 This message
 
Examples:
  sudo ./install.sh --verbose --dry-run

Description: 
  Bootstrap a (new) host for this flake. Creates or modifies:
    - host.json
    - host/user SSH Keys
    - secrets.yaml with userPassword and privateKey
    - hardware.nix
 
EOF
}

needsArg() { [[ -n ${2:-} ]] || { printError "Error: $1 requires an argument"; exit 1; }; }

parseArgs() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --admin-key)     needsArg "$1" "${2:-}"; ADMIN_KEY="$2";     shift 2 ;;
            --password-file) needsArg "$1" "${2:-}"; PASSWORD_FILE="$2"; shift 2 ;;
            -n|--dry-run)    DRY_RUN=true;  shift ;;
            -v|--verbose)    VERBOSE=true;  shift ;;
            -h|--help)       showFlags; exit 0 ;;
            *)               printError "Error: Unknown option: $1"; showFlags; exit 1 ;;
        esac
    done

    if [[ $VERBOSE == true ]];
    then set -x;
    fi
}

# ── helpers ──────────────────────────────────────────────────────────────
gitRepo() { git -c safe.directory='*' "$@"; }

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

writeFile() {
    local path="$1" content
    content="$(cat)"
    if [[ $DRY_RUN == true ]]; then
        printInfo "[dry-run] would write $path:"
        printf '%s\n' "$content" | sed 's/^/      /'
        return 0
    fi
    mkdir -p "$(dirname "$path")"
    printf '%s\n' "$content" > "$path"
    printSuccess "wrote $path"
}

# ── validate ──────────────────────────────────────────────────────────────
# Validate if all prerequisites are present for the install process 
validate() {
    printHeader "Validating environment"
    local fail=0

    # The nix-shell shebang only fires when executed directly.
    if [[ -n ${IN_NIX_SHELL:-} ]];
    then
        printSuccess "Verified nix-shell environment"
    else
        printError "Failed to install nix-shell packages"
        fail=1
    fi

    if grep -qi nixos /etc/os-release 2>/dev/null;
    then
        printSuccess "Verified NixOS"
    else
        printError "Not NixOS"
        fail=1
    fi

    # Writes /etc/ssh and chowns the user's home.
    if [[ $DRY_RUN == true || $EUID -eq 0 ]];
    then
        printSuccess "Verified privileges"
    else
        printError "Failed to access /etc/. Script must be run as root"
        fail=1
    fi

    # Prompts for hostname, username, password.
    if [[ -t 0 && -t 1 ]];
    then
        printSuccess "Verified terminal"
    else
        printError "No TTY"
        fail=1
    fi

    if REPO_ROOT="$(gitRepo rev-parse --show-toplevel 2>/dev/null)";
    then
        printSuccess "Verified config location: $REPO_ROOT"
    else
        printError "Failed to locate config. Not inside git worktree"
        fail=1
    fi

    if [[ -n ${REPO_ROOT:-} && -f $REPO_ROOT/flake.nix ]];
    then
        printSuccess "Verified flake.nix"
    else
        printError "Failed to locate flake.nix"
        fail=1
    fi

    if [[ -n $PASSWORD_FILE ]];
    then
        [[ -r $PASSWORD_FILE ]] \
        && printSuccess "Verified password file" \
        || { printError "Failed to read: $PASSWORD_FILE"; fail=1; }
    fi

    if [[ -n $ADMIN_KEY ]];
    then
        if [[ -r $ADMIN_KEY ]] && grep -qE '^(ssh-ed25519|ssh-rsa) ' "$ADMIN_KEY";
        then
            printSuccess "Verified admin key"
        else
            printError "Failed to locate admin key. $ADMIN_KEY is not a readable SSH key"
            fail=1
        fi
    fi

    [[ $fail -eq 0 ]] || return 1
    printSuccess "Validated environment. $'\n' All checks have passed"
}

# ── variables ──────────────────────────────────────────────────────────────
_HOST_ANCHOR=""
_HOSTNAME=""
_HOST_DIR=""
_USER_ANCHOR=""
_USERNAME=""
_USER_EMAIL=""
_SYSTEM=""
_PLATFORM=""
_GPU=()
_GPU_ARCH=""
_HW_MODULES=()
_TIMEZONE=""
_LOCALE=""
_ROLES=()

# @TODO: Becomes /persist/etc/ssh once impermanence is setup
_HOST_KEY_DIR="/etc/ssh"

# ── identity ──────────────────────────────────────────────────────────────
resolveIdentity() {
    printHeader "Identity"

    while :; do
        ask _HOSTNAME "Hostname" "$(hostname)"

        if [[ ! $_HOSTNAME =~ ^[a-z][a-z0-9-]{0,62}$ ]];
        then
            printError "Error: Invalid hostname. Only lowercase letters, digits and hyphens are allowed"
            continue
        fi

        _HOST_DIR="$REPO_ROOT/hosts/$_HOSTNAME"

        if [[ -d $_HOST_DIR ]];
        then
            printError "Error: hosts/$_HOSTNAME already exists"
            continue
        fi

        break
    done

    printSuccess "New host: hosts/$_HOSTNAME"

    while :; do
        ask _USERNAME "Username" "${SUDO_USER:-}"
        if [[ ! $_USERNAME =~ ^[a-z_][a-z0-9_-]{0,31}$ ]];
        then
            printError "Error: Invalid username. Only lowercase letters, digits, hyphens, and underscores are allowed"
            continue
        fi
        break
    done

    _USER_ANCHOR="${_USERNAME}_${_HOSTNAME}"
    _HOST_ANCHOR="$_HOSTNAME"

    ask _USER_EMAIL "git email" "$(gitRepo config user.email 2>/dev/null || true)"
}

# ── hardware detection ────────────────────────────────────────────────────────────
# Everything here tries to answer for itself and only asks when it cannot know.
# Every auto-detected value is still shown and overridable.

# DMI string: "ROG Zephyrus G16 GU605MY_GU605MY" -> "rog-zephyrus-g16-gu605my-gu605my"
parseDMI() {
    local s="${1,,}"
    s="${s//[^a-z0-9]/-}"
    sed -E 's/-+/-/g; s/^-//; s/-$//' <<< "$s"
}
 
dmi() { cat "/sys/class/dmi/id/$1" 2>/dev/null || true; }
 
detectSystem() {
    _SYSTEM="$(uname -m)-linux"
    printSuccess "system: $_SYSTEM"
}

# @TODO: This should be more of a doModules 
detectPlatform() {
    # A battery is the only laptop tell that's reliable from the ISO.
    if compgen -G '/sys/class/power_supply/BAT*' > /dev/null;
    then
        _PLATFORM="laptop"
    else
        _PLATFORM="desktop"
    fi
    printSuccess "platform: $_PLATFORM"
}

detectGpu() {
    local line
    _GPU=()
 
    while read -r line; do
        case "${line,,}" in
            *nvidia*) _GPU+=("nvidia") ;;
            *amd*|*"advanced micro"*|*ati*) _GPU+=("amd") ;;
            *intel*) _GPU+=("intel") ;;
        esac
    done < <(lspci | grep -iE 'vga|3d controller|display controller' || true)
 
    if ((${#_GPU[@]}));
    then
        mapfile -t _GPU < <(printf '%s\n' "${_GPU[@]}" | awk '!seen[$0]++')
    fi
    printSuccess "gpu: ${_GPU[*]:-none}"
}

detectGpuArch() {
    [[ " ${_GPU[*]} " == *" nvidia "* ]] || return 0
 
    # lspci prints the chip codename, and its prefix IS the architecture:
    #   AD107M [GeForce RTX 4070]  ->  ada-lovelace
    local chip
    chip="$(lspci | grep -i 'nvidia' | grep -oiE '\b(GB|AD|GA|TU|GV|GP|GM|GK)[0-9]{3}' | head -n1 || true)"
 
    case "${chip^^}" in
        GB*) _GPU_ARCH="blackwell" ;;
        AD*) _GPU_ARCH="ada-lovelace" ;;
        GA*) _GPU_ARCH="ampere" ;;
        TU*) _GPU_ARCH="turing" ;;
        GV*) _GPU_ARCH="volta" ;;
        GP*) _GPU_ARCH="pascal" ;;
        GM*) _GPU_ARCH="maxwell" ;;
        GK*) _GPU_ARCH="kepler" ;;
        *)   _GPU_ARCH="" ;;
    esac
 
    if [[ -n $_GPU_ARCH ]];
    then
        printSuccess "nvidia arch: $_GPU_ARCH (chip $chip)"
    else
        printWarn "Warning: Could not read the Nvidia chip codename"
        askList _GPU_ARCH "Nvidia architecture" \
            blackwell ada-lovelace ampere turing volta pascal maxwell kepler
    fi
}

detectLocale() {
    _TIMEZONE="$(timedatectl show -p Timezone --value 2>/dev/null || true)"
    [[ -n $_TIMEZONE ]] || _TIMEZONE="$(readlink -f /etc/localtime | sed 's|.*/zoneinfo/||')"
    ask _TIMEZONE "Timezone" "${_TIMEZONE:-UTC}"
 
    ask _LOCALE "Locale" "${LANG:-en_US.UTF-8}"
    ask _LOCALE_EXTRA "Extra locale" "$_LOCALE"
}

# ── nixos-hardware ───────────────────────────────────────────────────────
nixosHardwareModules() {
    nix eval --impure --json --apply builtins.attrNames --expr \
        "(builtins.getFlake \"path:$REPO_ROOT\").inputs.nixos-hardware.nixosModules" \
        2>/dev/null | jq -r '.[]' || true
}

detectHwModules() {
    local vendor product board family
    vendor="$(dmi sys_vendor)"
    product="$(dmi product_name)"
    board="$(dmi board_name)"
    family="$(dmi product_family)"
 
    printInfo "DMI: $vendor / $product / board $board"
 
    local modules
    mapfile -t modules < <(nixosHardwareModules)
    if ((${#modules[@]} == 0));
    then
        printWarn "Warning: Could not read nixos-hardware's module list"
        local mods
        ask mods "nixos-hardware modules (space separated, empty for none)" ""
        read -ra _HW_MODULES <<< "$mods"
        return 0
    fi
 
    # board_name is the model code and appears verbatim in the module
    local boardSlug match=""
    boardSlug="$(parseDMI "$board")"
    if [[ -n $boardSlug ]];
    then
        match="$(printf '%s\n' "${modules[@]}" | grep -x ".*-${boardSlug}" | head -n1 || true)"
    fi
 
    # Weaker fallback: score by how many DMI tokens appear in the module name.
    if [[ -z $match ]];
    then
        local tokens
        tokens="$(parseDMI "$vendor $family $product" | tr '-' '\n' \
            | grep -vE '^(inc|corp|co|ltd|computer|notebook|system|product|name|to|be|filled|by|oem|the|and|version|[0-9]{1,2})$' \
            | grep -E '.{3,}' || true)"
 
        match="$(printf '%s\n' "${modules[@]}" | awk -v toks="$tokens" '
            BEGIN { n = split(toks, t, "\n") }
            {
                score = 0
                for (i = 1; i <= n; i++)
                    if (t[i] != "" && index($0, t[i]) > 0) score++
                if (score > 0) printf "%d\t%s\n", score, $0
            }' | sort -rn | head -n5 | cut -f2)"
    fi
 
    _HW_MODULES=()
 
    if [[ -n $match ]];
    then
        local candidates
        mapfile -t candidates <<< "$match"
        printSuccess "matched: ${candidates[0]}"
        if ((${#candidates[@]} > 1));
        then
            printInfo "other candidates: ${candidates[*]:1}"
        fi
        if confirm "Use ${candidates[0]}?";
        then
            _HW_MODULES=("${candidates[0]}")
        fi
    else
        printWarn "no nixos-hardware module matches this machine"
    fi
 
    # No model-specific module -> assemble the generic common-* ones from what
    # we detected. These exist for exactly this case.
    if ((${#_HW_MODULES[@]} == 0));
    then
        printInfo "falling back to common-* modules"
        local want=() m
 
        case "$(dmi sys_vendor)" in
            *Intel*|*intel*) : ;;
        esac
        grep -qi 'GenuineIntel' /proc/cpuinfo && want+=("common-cpu-intel")
        grep -qi 'AuthenticAMD' /proc/cpuinfo && want+=("common-cpu-amd")
 
        [[ " ${_GPU[*]} " == *" intel "* ]] && want+=("common-gpu-intel")
        [[ " ${_GPU[*]} " == *" amd "*   ]] && want+=("common-gpu-amd")
        if [[ " ${_GPU[*]} " == *" nvidia "* ]];
        then
            want+=("common-gpu-nvidia")
            [[ -n $_GPU_ARCH ]] && want+=("common-gpu-nvidia-$_GPU_ARCH")
        fi
 
        if [[ $_PLATFORM == laptop ]];
        then
            want+=("common-pc-laptop" "common-pc-laptop-ssd")
        else
            want+=("common-pc" "common-pc-ssd")
        fi
 
        # Only keep the ones that actually exist upstream — the arch-suffixed
        # gpu modules in particular aren't named uniformly.
        for m in "${want[@]}"; do
            if printf '%s\n' "${modules[@]}" | grep -qx "$m";
            then
                _HW_MODULES+=("$m")
            else
                printWarn "skipping $m (no such module)"
            fi
        done
    fi
 
    printSuccess "modules: ${_HW_MODULES[*]:-none}"

    local mods
    ask mods "nixos-hardware modules" "${_HW_MODULES[*]}"
    read -ra _HW_MODULES <<< "$mods"
}

detectRoles() {
    local roles
    ask roles "Roles (space separated)" "desktop dev server"
    read -ra _ROLES <<< "$roles"
}

detectHardware() {
    printHeader "Detecting hardware"
    detectSystem
    detectPlatform
    detectGpu
    detectGpuArch
    detectHwModules
    detectLocale
    detectRoles
}

# ── summary ──────────────────────────────────────────────────────────────
printSummary() {
    printHeader "Summary"
    printInfo "host: $_HOSTNAME"
    printInfo "dir: hosts/$_HOSTNAME"
    printInfo "user: $_USERNAME <$_USER_EMAIL>"
    printInfo "system: $_SYSTEM"
    printInfo "platform: $_PLATFORM"
    printInfo "gpu: ${_GPU[*]:-none} ${_GPU_ARCH:+($_GPU_ARCH)}"
    printInfo "modules: ${_HW_MODULES[*]:-none}"
    printInfo "locale: $_TIMEZONE / $_LOCALE"
    printInfo "roles: ${_ROLES[*]:-none}"
    printInfo "host key: $_HOST_KEY_DIR/ssh_host_ed25519_key"
    echo
    confirm "Proceed?" || exit 1
}

# ── main ──────────────────────────────────────────────────────────────
main() {
    parseArgs "$@"
    validate || exit 1
    cd "$REPO_ROOT"
    
    resolveIdentity
    detectHardware
    printPlan
}

main "$@"