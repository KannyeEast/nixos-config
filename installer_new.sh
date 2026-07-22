#!/usr/bin/env bash

#
# installer.sh - bootstrap a host for this flake
#
set -Eeu -o pipfail

# ── method ───────────────────────────────────────────────────────────────
#   local  - this machine, running NixOS   (rebuild in place)
#   iso    - installer ISO, mounted target (nixos-install)
#   remote - another machine               (nixos-anywhere)
METHOD="${INSTALLER_METHOD:-}"

PKGS_BASE="age curl git jq mkpasswd openssh sops ssh-to-age"
PKGS_DETECT="iw pciutils util-linux"
PKGS_ISO="nixos-install-tools"

# ── bootstrap ────────────────────────────────────────────────────────────
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

    case "$METHOD" in
        local)  pkgs="$PKGS_BASE $PKGS_DETECT" ;;
        iso)    pkgs="$PKGS_BASE $PKGS_DETECT $PKGS_ISO" ;;
        remote) pkgs="$PKGS_BASE" ;;
    esac

    printf 'Fetching dependencies (%s)...\n' "$METHOD"
    exec nix-shell -p $pkgs \
        --run "INSTALLER_METHOD=$METHOD $(printf '%q ' bash "$0" "$@")"
fi

# ── flags ────────────────────────────────────────────────────────────────
VERBOSE=false
TARGET_ROOT=""

# ── state ────────────────────────────────────────────────────────────────
REPO_ROOT=""
KEYS_DIR=""

# ── logging ──────────────────────────────────────────────────────────────
RED=$'\033[0;31m'; GREEN=$'\033[0;32m'; YELLOW=$'\033[1;33m'
BLUE=$'\033[0;34m'; BOLD=$'\033[1m'; DIM=$'\033[2m'; NC=$'\033[0m'

printHeader()  { printf '\n%s── %s ─────────────────────────────────%s\n' "$BOLD$GREEN" "$*" "$NC"; }
printSuccess() { printf '%s✓%s %s\n' "$GREEN" "$NC" "$*"; }
printError()   { printf '%s✗%s %s\n' "$RED" "$NC" "$*" >&2; }
printWarn()    { printf '%s!%s %s\n' "$YELLOW" "$NC" "$*"; }
printInfo()    { printf '%sℹ%s %s\n' "$BLUE" "$NC" "$*"; }
printDebug()   { [[ $VERBOSE == true ]] && printf '%s  · %s%s\n' "$DIM" "$*" "$NC" >&2; return 0; }

# ── traps ────────────────────────────────────────────────────────────────
trapError() {
    printError "'$BASH_COMMAND'failed (exit $?) at ${FUNCNAME[1]:-main}():${BASH_LINENO[0]}"
    exit 1
}
trap trapError ERR

cleanup() {
    [[ -n $KEYS_DIR && -d $KEYS_DIR ]] && rm -rf "$KEYS_DIR"
    printf '\033[?25h' >&2
}
trap cleanup EXIT

# ── prompts ──────────────────────────────────────────────────────────────
# ask VAR QUESTION [DEFAULT]   - loops until non-empty
# askList VAR QUESTION OPT...  - numbered menu, first option is default
# confirm QUESTION             - y/N
ask() {
    local __var="$1" question="$2" default="${3:-}" reply
    while :; do
        read -rp "$(printf '%s?%s %s%s: ' "$BLUE" "$NC" "$question" "${default:+ [$default]}")" reply
        reply="${reply:-$default}"
        [[ -n $reply ]] && break
    done
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

# ── flags ────────────────────────────────────────────────────────────────
showFlags() {
    cat <<EOF
Usage: sudo ./installer.sh [OPTIONS]

Options:
      --root <PATH>   iso: the mounted target (default: /mnt)
  -v, --verbose       Show every command and its output
  -h, --help          This message
EOF
}

parseArgs() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --root)
                [[ -n ${2:-} ]] || { printError "--root needs a path"; exit 1; }
                TARGET_ROOT="${2%/}"
                shift 2 ;;
            -v|--verbose) VERBOSE=true; shift ;;
            -h|--help) showFlags; exit 0 ;;
            *) printError "Unknown option: $1"; showFlags; exit 1 ;;
        esac
    done
}

# ── validate ─────────────────────────────────────────────────────────────
FAIL=0
check() {
    local msg="$1"; shift
    if "$@" > /dev/null 2>&1; then
        printSuccess "$msg"
    else
        printError "$msg"
        FAIL=1
    fi
}

gitRepo() { git -c safe.directory='*' "$@"; }

validate() {
    printHeader "Validate ($METHOD)"

    REPO_ROOT="$(gitRepo -C "$(dirname "${BASH_SOURCE[0]}")" rev-parse --show-toplevel 2>/dev/null || true)"

    check "Interactive terminal" test -t 0
    check "Config repo with flake.nix" test -f "$REPO_ROOT/flake.nix"

    case "$METHOD" in
        local)
            check "Running NixOS" grep -qi nixos /etc/os-release
            check "Root privileges" test "$EUID" -eq 0
            if grep -q 'VARIANT_ID=installer' /etc/os-release 2>/dev/null; then
                printWarn "This looks like the installer ISO - did you mean method 'iso'?"
            fi
            ;;
        iso)
            TARGET_ROOT="${TARGET_ROOT:-/mnt}"
            check "Installer ISO" grep -q 'VARIANT_ID=installer' /etc/os-release
            check "Root privileges" test "$EUID" -eq 0
            check "Target mounted at $TARGET_ROOT" findmnt -M "$TARGET_ROOT"
            ;;
        remote)
            : # not implemented for now
            ;;
    esac

    (( FAIL == 0 )) || { printError "Fix the above and rerun"; exit 1; }

    cd "$REPO_ROOT"
    printDebug "repo: $REPO_ROOT | target: ${TARGET_ROOT:-none}"
}

# ── state ────────────────────────────────────────────────────────────────
HOSTNAME_="" # avoid existing $HOSTNAME
HOST_DIR=""
ROLES=()
USERNAME=""
USER_EMAIL=""
TIMEZONE=""
LOCALE=""
LOCALE_EXTRA=""
SYSTEM=""
CPU=""
GPU=()
STORAGE=""
HW_MODULES=()
WIFI='{}'
DOTFILES_SRC=""

# ── gather data ───────────────────────────────────────────────────────────────
detect() {
    [[ $METHOD == remote ]] && return 0

    SYSTEM="$(uname -m)-linux"
    TIMEZONE="$(readlink -f /etc/localtime 2>/dev/null | sed 's|.*/zoneinfo/||')"
    LOCALE="${LANG:-en_US.UTF-8}"
    LOCALE_EXTRA="${LC_CTYPE:-en_US.UTF-8}"

    local u="${SUDO_USER:-}"
    [[ -n $u && $u != root && $u != nixos ]] && USERNAME="$u"
    USER_EMAIL="$(gitRepo config user.email 2>/dev/null || true)"

    local src dev
    src="$(findmnt -no SOURCE --target "${TARGET_ROOT:-/}" 2>/dev/null || true)"
    dev="$(lsblk -no PKNAME "$src" 2>/dev/null | head -n1 || true)"
    [[ -z $dev ]] && dev="$(lsblk -dno NAME -e 7,11 | head -n1)"
    if [[ "$(lsblk -dno ROTA "/dev/$dev" 2>/dev/null)" == "1" ]]; then
        STORAGE="hdd"
    else
        STORAGE="ssd"
    fi

    case "$(lscpu | awk -F: '/Vendor ID/ { print $2; exit }' | xargs)" in
        GenuineIntel) CPU="intel" ;;
        AuthenticAMD) CPU="amd" ;;
    esac

    local vid
    while read -r vid; do
        case "$vid" in
            10de) GPU+=("nvidia") ;;
            1002) GPU+=("amd") ;;
            8086) GPU+=("intel") ;;
        esac
    done < <(lspci -n -mm -d ::03xx | awk -F'"' '{ print $4 }')
    ((${#GPU[@]})) && mapfile -t GPU < <(printf '%s\n' "${GPU[@]}" | awk '!seen[$0]++')

    printDebug "detected: $SYSTEM | ${CPU:-?} | ${GPU[*]:-no gpu} | $STORAGE | $TIMEZONE"
    return 0
}

# ── form ─────────────────────────────────────────────────────────────────
renderForm() {
    local id="!  required"
    [[ -n $HOSTNAME_ && -n $USERNAME ]] \
        && id="$HOSTNAME_ | ${ROLES[*]} | $USERNAME <${USER_EMAIL:-no email}>"

    local wifi="none"
    local count
    count="$(jq -r 'keys | length' <<< "$WIFI")"
    (( count > 0 )) && wifi="$count network(s): $(jq -r 'keys | join(", ")' <<< "$WIFI")"

    printHeader "Host form ($METHOD)"
    printf '    %s%d)%s %-11s %s\n' \
        "$BOLD" 1 "$NC" "Identity" "$id" \
        "$BOLD" 2 "$NC" "Locale" "$TIMEZONE | $LOCALE / $LOCALE_EXTRA" \
        "$BOLD" 3 "$NC" "Hardware" "$SYSTEM | ${CPU:-unknown} | ${GPU[*]:-no gpu} | $STORAGE" \
        "$BOLD" 4 "$NC" "Modules" "${HW_MODULES[*]:-none}" \
        "$BOLD" 5 "$NC" "Wifi" "$wifi" \
        "$BOLD" 6 "$NC" "Dotfiles" "${DOTFILES_SRC:-skip}"
    echo
}

gatherForm() {
    detect

    local choice
    while :; do
        renderForm
        read -rp "$(printf '%s?%s Fill section [1-6], (c)ontinue, (q)uit: ' "$BLUE" "$NC")" choice
        case "$choice" in
            1) editIdentity ;;
            2) editLocale ;;
            3) editHardware ;;
            4) editModules ;;
            5) editWifi ;;
            6) editDotfiles ;;
            c|C)
                if [[ -z $HOSTNAME_ || -z $USERNAME ]]; then
                    printError "Identity (1) is required"
                elif confirm "Write hosts/$HOSTNAME_ and continue?"; then
                    break
                fi
                ;;
            q|Q) printInfo "Aborted - nothing was written"; exit 0 ;;
            *) printError "pick 1-6, c or q" ;;
        esac
    done
}
# ── editors ──────────────────────────────────────────────────────────────
# 1) hostname, roles, user, email
editIdentity() {
    while :; do
        ask HOSTNAME_ "Hostname" "$HOSTNAME_"
        if [[ ! $HOSTNAME_ =~ ^[a-z][a-z0-9-]{0,62}$ ]]; then
            printError "Only lowercase letters, digits and hyphens"
        elif [[ -d $REPO_ROOT/hosts/$HOSTNAME_ ]]; then
            printError "hosts/$HOSTNAME_ already exists"
        else
            break
        fi
    done
    HOST_DIR="$REPO_ROOT/hosts/$HOSTNAME_"

    local base input addon
    askList base "System type" desktop server
    ROLES=("$base")

    if [[ $base == desktop ]]; then
        ask input "Addons (dev gaming media, 'none')" "dev"
        for addon in $input; do
            case "$addon" in
                dev|gaming|media) ROLES+=("$addon") ;;
                none) ;;
                *) printWarn "Skipping unknown addon: $addon" ;;
            esac
        done
    fi

    while :; do
        ask USERNAME "Username" "$USERNAME"
        [[ $USERNAME =~ ^[a-z_][a-z0-9_-]{0,31}$ ]] && break
        printError "Only lowercase letters, digits, hyphens and underscores"
    done

    ask USER_EMAIL "Git email" "$USER_EMAIL"
}

# 2) timezone and locales
editLocale() {
    ask TIMEZONE "Timezone" "${TIMEZONE:-America/New_York}"
    ask LOCALE "Locale" "${LOCALE:-en_US.UTF-8}"
    ask LOCALE_EXTRA "Extra locale" "${LOCALE_EXTRA:-$LOCALE}"
}

# 3) the machine, constrained to what the modules understand
editHardware() {
    ask SYSTEM "System" "${SYSTEM:-x86_64-linux}"

    while :; do
        ask CPU "CPU" "${CPU:-intel}"
        [[ $CPU == intel || $CPU == amd ]] && break
        printError "intel or amd"
    done

    while :; do
        ask STORAGE "Storage" "${STORAGE:-ssd}"
        [[ $STORAGE == ssd || $STORAGE == hdd ]] && break
        printError "ssd or hdd"
    done

    local input ok g
    while :; do
        ask input "GPU" "${GPU[*]:-none}"
        if [[ $input == none ]]; then
            GPU=()
            break
        fi
        ok=true
        for g in $input; do
            case "$g" in
                intel|amd|nvidia) ;;
                *) printError "Unknown gpu: $g"; ok=false ;;
            esac
        done
        if [[ $ok == true ]]; then
            read -ra GPU <<< "$input"
            break
        fi
    done
}

# 4) nixos-hardware modules
# https://github.com/NixOS/nixos-hardware
editModules() {
    local suggest=() g
    [[ -n $CPU ]] && suggest+=("common-cpu-$CPU")
    for g in "${GPU[@]}"; do
        suggest+=("common-gpu-$g")
    done
    if confirm "Is this a laptop?"; then
        suggest+=("common-pc-laptop")
        [[ $STORAGE == hdd ]] && suggest+=("common-pc-laptop-hdd")
    fi
    [[ $STORAGE == ssd ]] && suggest+=("common-pc-ssd")

    local mods
    ask mods "Modules ('none' to clear)" "${HW_MODULES[*]:-${suggest[*]}}"
    if [[ $mods == none ]]; then
        HW_MODULES=()
    else
        read -ra HW_MODULES <<< "$mods"
    fi
}

# 5) wifi: scan the air, pick an SSID, type it when hidden. The editor is
# an opt-in escape hatch for advanced NetworkManager keys. Plaintext psk
# only touches KEYS_DIR and ends up encrypted in secrets.json
scanWifi() {
    if command -v nmcli > /dev/null && nmcli -t general status > /dev/null 2>&1; then
        nmcli --terse --fields SIGNAL,SSID dev wifi list --rescan yes 2>/dev/null \
            | awk -F: 'length($2) && !seen[$2]++' \
            | sort -t: -k1 -rn | cut -d: -f2- | sed 's/\\:/:/g'
        return 0
    fi

    local dev
    dev="$(iw dev 2>/dev/null | awk '/Interface/ { print $2; exit }')"
    [[ -n $dev ]] || return 0
    ip link set "$dev" up 2>/dev/null || true
    iw dev "$dev" scan 2>/dev/null \
        | awk -F'SSID: ' '/\tSSID: / && length($2) && !seen[$2]++ { print $2 }'
}

editWifi() {
    local networks=()
    [[ $METHOD != remote ]] && mapfile -t networks < <(scanWifi | head -12)

    local name ssid psk psk2 profile edited n=0
    while :; do
        if ((${#networks[@]})); then
            askList ssid "SSID" "${networks[@]}" "<hidden or not listed>"
            [[ $ssid == "<hidden or not listed>" ]] && ask ssid "SSID"
        else
            ask ssid "SSID"
        fi

        ask name "Connection name" "$ssid"
        if jq -e --arg n "$name" 'has($n)' <<< "$WIFI" > /dev/null; then
            printError "'$name' is already configured"
            continue
        fi

        while :; do
            read -rsp "$(printf '%s?%s Password (hidden): ' "$BLUE" "$NC")" psk
            printf '\n'
            read -rsp "$(printf '%s?%s Password (repeat): ' "$BLUE" "$NC")" psk2
            printf '\n'
            if [[ -z $psk || $psk != "$psk2" ]]; then
                printError "Empty or mismatched"
            elif (( ${#psk} < 8 )); then
                printError "WPA-PSK needs 8-63 characters"
            else
                break
            fi
        done

        profile="$(jq -n --arg id "$name" --arg ssid "$ssid" --arg psk "$psk" '{
            connection: { id: $id, type: "wifi" },
            wifi: { ssid: $ssid },
            "wifi-security": { "key-mgmt": "wpa-psk", psk: $psk }
        }')"

        # every other keyfile setting, on request only
        # https://networkmanager.dev/docs/api/latest/nm-settings-keyfile.html
        if confirm "Edit advanced settings for '$name'?"; then
            local file="$KEYS_DIR/wifi-$n.json"
            jq -n --argjson p "$profile" '{
                connection: { id: "", permissions: "", type: "wifi" },
                ipv4: { "dns-search": "", method: "" },
                ipv6: { "addr-gen-mode": "", "dns-search": "", method: "" },
                wifi: { "mac-address-blacklist": "", mode: "", ssid: "" },
                "wifi-security": { "auth-alg": "", "key-mgmt": "wpa-psk", psk: "" }
            } * $p' > "$file"

            "${EDITOR:-nano}" "$file"

            if edited="$(jq 'walk(
                    if type == "object"
                    then with_entries(select(.value != "" and .value != {}))
                    else . end
                )' "$file" 2>/dev/null)"; then
                profile="$edited"
            else
                printWarn "Not valid JSON - keeping the basic profile"
            fi
        fi

        WIFI="$(jq --arg name "$name" --argjson p "$profile" '. + { ($name): $p }' <<< "$WIFI")"
        n=$((n + 1))
        confirm "Add another network?" || break
    done
}

# 6) dotfiles seed, copied at write time - this host owns its copy
editDotfiles() {
    local src
    read -r -e -i "${DOTFILES_SRC:-$PWD/}" \
        -p "$(printf '%s?%s %s: ' "$BLUE" "$NC" "Seed dotfiles from (git URL or local path, empty = skip)")" src

    if [[ $src == "~"* ]]; then
        local h="${SUDO_USER:-}"
        if [[ -n $h && $h != root ]]; then h="/home/$h"; else h="$HOME"; fi
        src="$h${src#\~}"
    fi

    if [[ -z $src || ${src%/} == "$PWD" ]]; then
        DOTFILES_SRC=""
    else
        DOTFILES_SRC="$src"
    fi
}

# ── main ─────────────────────────────────────────────────────────────────
main() {
    printHeader "Method: $METHOD"
    parseArgs "$@"
    validate
    
    KEYS_DIR="$(mktemp -d)"
    chmod 700 "$KEYS_DIR"
    
    gatherForm
}

main "$@"