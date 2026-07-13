#!/usr/bin/env bash

#
# install.sh - bootstrap a new host for this config.
#
set -Eeu -o pipefail

if [[ -z ${IN_NIX_SHELL:-} ]]; then
    echo "Fetching dependencies..."
    exec nix-shell \
        -p age git jq mkpasswd nixos-install-tools openssh pciutils sops ssh-to-age util-linux \
        --run "$(printf '%q ' bash "$0" "$@")"
fi

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

askOptional() {
    local __var="$1" question="$2" default="${3:-}" reply
    read -rp "$(printf '%s?%s %s [%s]: ' "$BLUE" "$NC" "$question" "${default:-none}")" reply
    printf -v "$__var" '%s' "${reply:-$default}"
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
    printSuccess "Validated environment"
}

# ── variables ──────────────────────────────────────────────────────────────
_HOST_ANCHOR=""
_HOSTNAME=""
_HOST_DIR=""
_ROLES=()

_USER_ANCHOR=""
_USERNAME=""
_USER_EMAIL=""

_SYSTEM=""
_TIMEZONE=""
_LOCALE=""
_LOCALE_EXTRA=""

_MODULES=false
_HW_MODULES=()
_STORAGE=""
_CPU=""
_GPU=()

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
    
    local valid=(desktop dev server) input role ok
    while :; do
      ask input "Roles (space separated)" "desktop dev server"
      read -ra _ROLES <<< "$input"
      
      if (( ${#_ROLES[@]} == 0 ));
      then
          printError "Error: Pick at least one role"
          continue
      fi 
      
      ok=true
      for role in "${_ROLES[@]}"; do
          if ! printf '%s\n' "${valid[@]}" | grep -qx "$role";
          then
            printError "Error: Unkown role - $role"
            ok=false
          fi
      done
      
      [[ $ok == false ]] && continue
      break
    done

    printSuccess "Roles: ${_ROLES[*]}"  

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
 
detectSystem() {
    _SYSTEM="$(uname -m)-linux"
    printSuccess "System: $_SYSTEM"
}

detectLocale() {
    _TIMEZONE="$(readlink -f /etc/localtime | sed 's|.*/zoneinfo/||')"
    _LOCALE=${LANG:-en_US.UTF-8}
    _LOCALE_EXTRA=${LC_CTYPE:-en_US.UTF-8}
    
    ask _TIMEZONE "Timezone" "${_TIMEZONE:-UTC}"
    ask _LOCALE "Locale" "$_LOCALE"
    ask _LOCALE_EXTRA "Extra locale" "$_LOCALE_EXTRA"
}

detectStorage() {
    local src dev rot
    
    src="$(findmnt -no SOURCE --target / 2>/dev/null || true)"
    dev="$(lsblk -no PKNAME "$src" 2>/dev/null | head -n1 || true)"
    [[ -z $dev ]] && dev="$(lsblk -dno NAME | head -n1)"
    
    rot="$(lsblk -dno ROTA "/dev/$dev" 2>/dev/null || echo 0)"
    
    if [[ $rot == 1 ]];
    then
      _STORAGE="hdd"
    else 
      _STORAGE="ssd"
    fi
    
    printSuccess "Storage: $_STORAGE ($dev)"
}

detectCpu() {
    case "$(lscpu | grep 'Vendor ID' | awk -F: '{print $2}' | xargs)"
    in
        GenuineIntel) _CPU="intel";;
        AuthenticAMD) _CPU="amd";;
        *) _CPU="";;
    esac
    printSuccess "CPU: ${_CPU:-unknown}"
}

detectGpu() {
    local vid

    while read -r vid; do
        case "$vid" in
            10de) _GPU+=("nvidia") ;;
            1002) _GPU+=("amd") ;;
            8086) _GPU+=("intel") ;;
        esac
    done < <(lspci -n -mm -d ::03xx | awk -F'"' '{print $4}')

    if ((${#_GPU[@]}));
    then
        mapfile -t _GPU < <(printf '%s\n' "${_GPU[@]}" | awk '!seen[$0]++')
    fi
    
    printSuccess "GPU: ${_GPU[*]:-none}"
}

# ── nixos-hardware ───────────────────────────────────────────────────────
detectPlatform() {
    # A battery is the only laptop tell that's reliable from the ISO.
    if compgen -G '/sys/class/power_supply/BAT*' > /dev/null; # @TODO: This can just be an if statement in the module itself
    then
        _MODULES=true
    else
        _MODULES=false
    fi
}

# DMI string: "ROG Zephyrus G16 GU605MY_GU605MY" -> "rog-zephyrus-g16-gu605my-gu605my"
parseDMI() {
    local s="${1,,}"
    s="${s//[^a-z0-9]/-}"
    sed -E 's/-+/-/g; s/^-//; s/-$//' <<< "$s"
}
 
dmi() { cat "/sys/class/dmi/id/$1" 2>/dev/null || true; }

nixosHardwareModules() {
    local rev ref="github:NixOS/nixos-hardware"

    rev="$(jq -r '.nodes["nixos-hardware"].locked.rev // empty' "$REPO_ROOT/flake.lock" 2>/dev/null || true)"
    [[ -n $rev ]] && ref="github:NixOS/nixos-hardware/$rev"

    timeout 30 nix eval "$ref#nixosModules" \
        --apply builtins.attrNames --json \
        --extra-experimental-features 'nix-command flakes' \
        | jq -r '.[]'
}

detectHardwareModules() {
    if compgen -G '/sys/class/power_supply/BAT*' > /dev/null;
    then
        printHeader "Fetching nixos-hardware modules" 
        printInfo "DMI: $(dmi sys_vendor) / $(dmi product_name) / board $(dmi board_name)"
        
        local modules
        if ! mapfile -t modules < <(nixosHardwareAttrs); 
        then
            printWarn "Could not fetch nixos-hardware's module list"
        fi
    
        if ((${#modules[@]} == 0)); 
        then
            printWarn "No module list — falling back to manual entry"
        else
            printSuccess "Fetched ${#modules[@]} modules"
        fi
    
        local mods
        askOptional mods "nixos-hardware modules (space separated)" ""
        read -ra _HW_MODULES <<< "$mods"
    else
        return 0
    fi
}

detectHardware() {
    printHeader "Detecting hardware"
    detectSystem
    detectLocale
    detectStorage
    detectCpu
    detectGpu
    detectPlatform
    detectHardwareModules
}

# ── summary ──────────────────────────────────────────────────────────────
printSummary() {
    printHeader "Summary"
    printInfo "host: $_HOSTNAME"
    printInfo "system: $_SYSTEM"
    printInfo "roles: ${_ROLES[*]:-none}"
    printInfo "user: $_USERNAME <$_USER_EMAIL>"
    printInfo "gpu: ${_GPU[*]:-none}"
    printInfo "modules: ${_HW_MODULES[*]:-none}"
    printInfo "locale: $_TIMEZONE / $_LOCALE"
    printInfo "host key: $_HOST_KEY_DIR/ssh_host_ed25519_key"
    echo
    confirm "Proceed?" || exit 1
}

# ── main ──────────────────────────────────────────────────────────────
main() {
    clear
    parseArgs "$@"
    validate || exit 1
    cd "$REPO_ROOT"
    
    resolveIdentity
    detectHardware
    printSummary
}

main "$@"