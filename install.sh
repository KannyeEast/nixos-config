#!/usr/bin/env bash

#
# install.sh - bootstrap a new host for this config.
#
set -Eeu -o pipefail

if [[ -z ${IN_NIX_SHELL:-} ]];
then
    printf 'Fetching dependencies...\n'
    exec nix-shell \
        -p age curl git jq mkpasswd nixos-install-tools openssh pciutils sops ssh-to-age util-linux \
        --run "$(printf '%q ' bash "$0" "$@")"
fi

# ── init ──────────────────────────────────────────────────────────────
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
  -v, --verbose              Trace execution
  -h, --help                 This message
 
Examples:
  sudo ./install.sh --admin-key /etc/nixos/id_admin.pub

Description: 
  Bootstrap a (new) host for this flake. Creates or modifies:
    - host.json
    - host/user SSH Keys
    - secrets.json with userPassword, privateKey, and optionally wifi configuration
    - hardware.nix
 
EOF
}

needsArg() { [[ -n ${2:-} ]] || { printError "Error: $1 requires an argument"; exit 1; }; }

parseArgs() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --admin-key)     needsArg "$1" "${2:-}"; ADMIN_KEY="$2";     shift 2 ;;
            --password-file) needsArg "$1" "${2:-}"; PASSWORD_FILE="$2"; shift 2 ;;
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

spin() {
    local msg="$1"; shift
    local frames='⠋⠙⠹⠸⠼⠴⠦⠧⠇⠏' i=0 pid rc=0
    local tmp; tmp="$(mktemp)"

    "$@" > "$tmp" 2>/dev/null &
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
    fi

    cat "$tmp"
    rm -f "$tmp"
    return "$rc"
}

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
    if [[ $EUID -eq 0 ]];
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

_WIFI='{}'

_SYSTEM=""
_TIMEZONE=""
_LOCALE=""
_LOCALE_EXTRA=""

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
    
    local base addons=() addon input ok
    local validAddons=(dev gaming media)
    
    askList base "System type" desktop server
    _ROLES=("$base")

    if [[ $base == desktop ]];
    then
        while :; do
            askOptional input "Addons (${validAddons[*]})" "dev"
            read -ra addons <<< "$input"

            ok=true
            for addon in "${addons[@]}"; do
                if ! printf '%s\n' "${validAddons[@]}" | grep -qx "$addon";
                then
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

# ── Wifi ──────────────────────────────────────────────────────────────
resolveWifi() {
    printHeader "Wifi"
    confirm "Add wifi networks?" || return 0

    cat > "$_KEYS_DIR/wifi-template.json" <<'EOF'
{
  "<NAME>": {
    "connection": {
      "id": "<NAME>",
      "permissions": "",
      "type": ""
    },
    "ipv4": {
      "dns-search": "",
      "method": "",
    },
    "ipv6": {
      "addr-gen-mode": "",
      "dns-searc"h: "",
      "method": ""
    },
    "wifi": {
      "mac-address-blacklist": "",
      "mode": "",
      "ssid": "<SSID>"
    },
    "wifi-security": {
      "auth-alg": "",
      "key-mgmt": "",
      "psk": "<PASSWORD>"
    }
  }
}
EOF

    printInfo "Your editor will open"
    printInfo "Only ssid and psk are needed required"
    "${EDITOR:-nano}" "$_KEYS_DIR/wifi-template.json"

    if ! jq empty "$_KEYS_DIR/wifi-template.json" 2>/dev/null;
    then
        printError "Not valid JSON"
        return 0
    fi

    _WIFI="$(jq '
            walk(
                if type == "object"
                then with_entries(select(.value != "" and .value != {}))
                else .
                end
            )
        ' "$_KEYS_DIR/wifi-template.json")"
        
    printSuccess "Wifi profiles: $(jq -r 'keys | join(", ")' <<< "$_WIFI")"
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
    compgen -G '/sys/class/power_supply/BAT*' > /dev/null || return 0
    
    printHeader "nixos-hardware" 
    printInfo "DMI: $(dmi sys_vendor) / $(dmi product_name) / board $(dmi board_name)"
    
    local modules
    mapfile -t modules < <(spin "Fetching modules" nixosHardwareModules); 
    
    if ((${#modules[@]} == 0));
    then
        printWarn "No module list. Manual entries only"
        local mods
        printInfo "nixos-hardare: https://github.com/NixOS/nixos-hardware"
        askOptional mods "nixos-hardware modules (space separated)" ""
        read -ra _HW_MODULES <<< "$mods"
        return 0
    fi
    
    printSuccess "Fetched ${#modules[@]} modules"
    
    local boardSlug match=""
    boardSlug="$(parseDMI "$(dmi board_name)")"
    if [[ -n $boardSlug ]];
    then
        match="$(printf '%s\n' "${modules[@]}" | grep -x ".*-${boardSlug}" | head -n1 || true)"
    fi
    
    if [[ -n $match ]];
    then
        printSuccess "Matched model: $match"
        if confirm "Use $match?";
        then
            _HW_MODULES=("$match")
        else
            printInfo "Declined. Using common modules instead"
        fi
    else
        printInfo "No dedicated module found for '$(dmi product_name)'. Using common modules"
    fi
    
    if ((${#_HW_MODULES[@]} == 0));
    then
        local want=() m

        [[ -n $_CPU ]] && want+=("common-cpu-$_CPU")

        for m in "${_GPU[@]}"; do
            want+=("common-gpu-$m")
        done

        want+=("common-pc-laptop")
        
        if [[ $_STORAGE == "hdd" ]];
        then
          want+=("common-pc-laptop-hdd")
        else
          want+=("common-pc-ssd")
        fi

        # Keep only names that actually exist upstream.
        for m in "${want[@]}"; do
            if printf '%s\n' "${modules[@]}" | grep -qx "$m";
            then
                _HW_MODULES+=("$m")
            else
                printWarn "Skipping $m (not in nixos-hardware)"
            fi
        done
    fi

    printSuccess "Modules: ${_HW_MODULES[*]:-none}"

    local mods
    printInfo "nixos-hardare: https://github.com/NixOS/nixos-hardware"
    askOptional mods "nixos-hardware modules" "${_HW_MODULES[*]}"
    read -ra _HW_MODULES <<< "$mods"
}

detectHardware() {
    printHeader "Detecting hardware"
    detectSystem
    detectLocale
    detectStorage
    detectCpu
    detectGpu
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
    printInfo "locale: $_TIMEZONE / $_LOCALE / $_LOCALE_EXTRA "
    printInfo "host key: $_HOST_KEY_DIR/ssh_host_ed25519_key"
    echo
    confirm "Proceed?" || exit 1
}

# ── keys ─────────────────────────────────────────────────────────────────
# Key material is generated into a temp dir that dies with the script.
# The user's private key is never written to a home directory
# it goes into secrets.json, and sops-nix places it at activation

_KEYS_DIR=""
_HOST_AGE=""
_USER_AGE=""
_USER_PUB=""
_ADMIN_AGE=""
_SECRETS=""

cleanup() {
    [[ -n $_KEYS_DIR && -d $_KEYS_DIR ]] && rm -rf "$_KEYS_DIR"
    printf '\033[?25h' >&2
}
trap cleanup EXIT

setupKeysDir() {
    _KEYS_DIR="$(mktemp -d)"
    chmod 700 "$_KEYS_DIR"
    _SECRETS="hosts/$_HOSTNAME/secrets.json"
    mkdir -p "$_HOST_DIR"
}

# ── host key ─────────────────────────────────────────────────────────────
# NixOS generates this on first boot. On a running system it already exists and can be reused
generateHostKey() {
    printHeader "Host key"
 
    local key="$_HOST_KEY_DIR/ssh_host_ed25519_key"
 
    if [[ -f "$key.pub" ]];
    then
        printSuccess "Reusing existing host key: $key"
    else
        printInfo "Generating host key: $key"
        install -d -m 755 "$_HOST_KEY_DIR"
        ssh-keygen -t ed25519 -N "" -C "root@$_HOSTNAME" -f "$key"
    fi
 
    _HOST_AGE="$(ssh-to-age < "$key.pub")"
    printSuccess "Host age key: $_HOST_AGE"
}

# ── user key ─────────────────────────────────────────────────────────────
generateUserKey() {
    printHeader "User key"
 
    local key="$_KEYS_DIR/id_$_USERNAME"
 
    ssh-keygen -t ed25519 -N "" -C "$_USERNAME@$_HOSTNAME" -f "$key"
    chmod 600 "$key"
 
    _USER_PUB="$(cat "$key.pub")"
    _USER_AGE="$(ssh-to-age < "$key.pub")"
    printSuccess "User age key: $_USER_AGE"
}

# ── admin key ────────────────────────────────────────────────────────────
# Optional extra recipient so you can decrypt this host's secrets from another
# machine. Without one, only the user and this host can read them
generateAdminKey() {
    local pub="${ADMIN_KEY:-$REPO_ROOT/id_admin.pub}"
 
    if [[ -r $pub ]];
    then
        _ADMIN_AGE="$(ssh-to-age < "$pub")"
        printSuccess "Admin age key: $_ADMIN_AGE"
    else
        printWarn "No admin key. Secrets will be readable by this host and user only"
        printInfo "Pass --admin-key or place the key at $REPO_ROOT to add one."
    fi
}

# ── .sops.yaml ─────────────────────────────────────────────────────────── 
writeSopsYaml() {
    printHeader ".sops.yaml"
 
    if [[ ! -f .sops.yaml ]];
    then
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
 
    [[ -n $_ADMIN_AGE ]] && ! grep -q -- "- &admin " .sops.yaml \
        && insertBefore "    - &admin $_ADMIN_AGE" "  - &hosts:"
 
    insertBefore "    - &$_USER_ANCHOR $_USER_AGE" "  - &hosts:"
    insertBefore "    - &$_HOST_ANCHOR $_HOST_AGE" "creation_rules:"
 
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
    if [[ -n $PASSWORD_FILE ]];
    then
        hash="$(< "$PASSWORD_FILE")"
    else
        printInfo "Set the login password for '$_USERNAME':"
        hash="$(mkpasswd -m sha-512)"
    fi

    mkdir -p "$(dirname "$_SECRETS")"

    # --arg handles the newlines in the private key; printf would not.
    jq -n \
        --arg pw  "$hash" \
        --arg key "$(< "$_KEYS_DIR/id_$_USERNAME")" \
        --argjson wifi "$_WIFI" \
        '{ userPassword: $pw, userPrivateKey: $key }
         + (if $wifi == {} then {} else { wifi: $wifi } end)' \
        > "$_SECRETS"

    sops --encrypt --in-place "$_SECRETS"
    printSuccess "Encrypted $_SECRETS"
}

# ── host.json ────────────────────────────────────────────────────────────
writeHost() {
    printHeader "host.json"
 
    local adminPub=""
    [[ -r ${ADMIN_KEY:-$REPO_ROOT/id_admin.pub} ]] \
        && adminPub="$(< "${ADMIN_KEY:-$REPO_ROOT/id_admin.pub}")"
 
    local rolesJson gpuJson modulesJson keysJson
    rolesJson="$(printf '%s\n' "${_ROLES[@]}" | jq -R . | jq -sc 'map(select(. != ""))')"
    gpuJson="$(printf '%s\n' "${_GPU[@]:-}" | jq -R . | jq -sc 'map(select(. != ""))')"
    modulesJson="$(printf '%s\n' "${_HW_MODULES[@]:-}" | jq -R . | jq -sc 'map(select(. != ""))')"
    keysJson="$(printf '%s\n%s\n' "$_USER_PUB" "$adminPub" | jq -R . | jq -sc 'map(select(. != ""))')"
 
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
# @TODO: remove fileSystems and swapDevices blocks when disko is in place 
writeHardware() {
    printHeader "hardware.nix"
 
    local body
    body="$(nixos-generate-config --show-hardware-config \
        | sed -e '/^ *#/d' \
              -e '/^{ config, lib, pkgs, modulesPath, \.\.\. }:$/d' \
              -e '/^{$/d' \
              -e '/^}$/d' \
        | sed -e 's/^./        &/' \
        | cat -s)"
 
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

# ── profile.nix ─────────────────────────────────────────────────────────
writeProfile() {
    printHeader "profile"

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
                shell = pkgs.zsh;
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
                    extensions.extra = { };
                    extensions.exclude = [ ];
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

# ── dotfiles ─────────────────────────────────────────────────────────
writeDotfiles() {
    printHeader "dotfiles"

    local dest="$_HOST_DIR/home/.config/niri"
    mkdir -p "$dest"

    # Pinned — 'main' would mean the config changes under you between installs.
    local rev="v26.04"
    local url="https://raw.githubusercontent.com/YaLTeR/niri/$rev/resources/default-config.kdl"

    if ! curl -fsSL "$url" -o "$dest/config.kdl"; then
        printWarn "Could not fetch niri's default config. Skipping"
        return 0
    fi

    # `spawn` takes an argv and does NOT expand variables, so the stock
    # `spawn "$TERMINAL"` silently fails. `terminal` is our alias binary.
    sed -i \
        -e 's|Mod+T hotkey-overlay-title="Open a Terminal: alacritty" { spawn "alacritty"; }|Mod+T hotkey-overlay-title="Open a Terminal" { spawn "terminal"; }|' \
        "$dest/config.kdl"

    printSuccess "Seeded $dest/config.kdl"
}

# ── verify ──────────────────────────────────────────────────────────────
verify() {
    printHeader "Verifying files"
    local fail=0

    local userKey="$_KEYS_DIR/id_$_USERNAME"
    local hostKey="$_HOST_KEY_DIR/ssh_host_ed25519_key"

    local userAge hostAge
    userAge="$(ssh-to-age -private-key -i "$userKey")"
    hostAge="$(ssh-to-age -private-key -i "$hostKey")"

    # 1. check host.json
    if jq -e '.hostname and .user.name and .system' "$_HOST_DIR/host.json" > /dev/null;
    then
        printSuccess "host.json is valid"
    else
        printError "host.json is malformed";
        fail=1
    fi

    # 2. check user decryption
    if SOPS_AGE_KEY="$userAge" sops -d "$_SECRETS" | jq -e '.userPassword and .userPrivateKey' > /dev/null;
    then
        printSuccess "secrets.json decrypts with the user key"
    else
        printError "User key cannot decrypt $_SECRETS";
        fail=1
    fi

    # 3. check host decryption
    if SOPS_AGE_KEY="$hostAge" sops -d --extract '["userPassword"]' "$_SECRETS" > /dev/null;
    then
        printSuccess "Host key decrypts its own secrets"
    else
        printError "Host key cannot decrypt $_SECRETS — first boot would lock you out"; fail=1
    fi
    
    # 4. check private user key
    if SOPS_AGE_KEY="$userAge" sops -d "$_SECRETS" | jq -r '.userPrivateKey' \
        | ssh-keygen -y -f /dev/stdin > /dev/null 2>&1;
        then
        printSuccess "Stored private key is valid"
    else
        printError "Stored private key is malformed";
        fail=1
    fi

    [[ $fail -eq 0 ]] || { printError "Verification failed"; exit 1; }
}

# ── ownership ──────────────────────────────────────────────────────────────
fixOwnership() {
    chown -R 1000:100 "$REPO_ROOT"
    printSuccess "Ownership set to uid 1000 (${_USERNAME})"
}

# ── relocate ──────────────────────────────────────────────────────────────
relocateRepo() {
    local target="/home/$_USERNAME/nixos-config"

    [[ -e $target ]] && { printError "$target already exists"; return 1; }

    if [[ $REPO_ROOT == "$target" ]];
    then
        printSuccess "Repo is already at $target"
        return 0
    fi

    printWarn "The dotfiles module expects the repo at $target"
    printInfo "It is currently at $REPO_ROOT"
    confirm "Move it?" || {
        printWarn "Skipped. Home-manager symlinks will not work until you move it"
        return 0
    }

    mkdir -p "/home/$_USERNAME"
    mv "$REPO_ROOT" "$target"
    chown -R 1000:100 "/home/$_USERNAME"

    REPO_ROOT="$target"
    cd "$REPO_ROOT"        # our cwd is now a dangling inode
    printSuccess "Moved repo to $target"
}

# ── summarize ──────────────────────────────────────────────────────────────
printNextSteps() {
    printHeader "Done"
    printInfo "Review, then commit:"
    printInfo "git -C $REPO_ROOT add . && git -C $REPO_ROOT commit -m 'feat: add host $_HOSTNAME'"
    printInfo ""
    printInfo "Then build:"
    printInfo "sudo nixos-rebuild switch --flake .#$_HOSTNAME"
}

# ── main ──────────────────────────────────────────────────────────────
main() {
    clear

    parseArgs "$@"
    validate || exit 1
    cd "$REPO_ROOT"
    
    resolveIdentity
    resolveWifi
    detectHardware
    printSummary
    
    setupKeysDir
    generateHostKey
    generateUserKey
    generateAdminKey
    
    writeSopsYaml
    writeSecrets
    writeHost
    writeHardware
    writeProfile
    writeDotfiles
    
    gitRepo add --intent-to-add .
    verify 
    fixOwnership
    relocateRepo
    printNextSteps
}

main "$@"