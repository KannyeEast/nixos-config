#!/usr/bin/env bash

#
# installer.sh - bootstrap a host for this flake
#

set -Eeuo pipefail

# ── script variables ────────
# == flags ==
VERBOSE=false

# == host ==
HOSTNAME=""
SYSTEM=""
ROLES=""
ADDONS=()
USERNAME=""
USEREMAIL=""
USER_KEY=""
GPU=()
HW_MODULES=()
TIMEZONE=""
LOCALE=""
LOCALE_EXTRA=""

# == secrets ==
HOST_AGE=""
USER_AGE=""
WIFI='{}'

# == temp ==
FLAKE=""
TEMP_DIR=""
DISK=""
DOTFILES_METHOD=""
DOTFILES=""

# ── theme ────────
# == palette ==
FG="#c6c8d1"
MUTED="#6c7086"
CURSOR="#7aa2f7"
ACCENT="#9ece6a"
BASE="#1a1b26"

# == gum ==
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

# ── logging ────────
logInfo() { gum log --level info "$*"; }
logWarn() { gum log --level warn "$*"; }
logError() { gum log --level error "$*"; }
logDebug() { gum log --level debug "$*"; }

die() { logError "$1"; exit "${2:-1}"; }

run() {
    logDebug "\$ $*"
    if [[ $VERBOSE == true ]]; then "$@"; return; fi

    gum spin --title "$*" --show-error -- "$@"
}

# ── traps ────────
trapError() {
    local code=$? cmd=$BASH_COMMAND line=${BASH_LINENO[0]} fn=${FUNCNAME[1]:-main}
    logError "'$cmd' failed (exit $code) at $fn():$line"
    exit "$code"
}
trap trapError ERR

cleanup() {
    [[ -n ${TEMP_DIR:-} && -d ${TEMP_DIR:-} ]] && rm -rf "$TEMP_DIR"
    printf '\033[?25h' >&2
}
trap cleanup EXIT

# ── flags ────────
showFlags() {
    cat <<EOF
Usage: sudo ./installer.sh [OPTIONS]

Options:
  -v, --verbose           Show every command and its output
  -h, --help              This message
EOF
}

parseArgs() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -v|--verbose) VERBOSE=true; shift ;;
            -h|--help) showFlags; exit 0 ;;
            *) printf 'Unknown option: %s\n' "$1" >&2; showFlags; exit 1 ;;
        esac
    done
}

# ── shell packages ────────
declare -A MODULE_PKGS=(
    [base]="gum git jq"
    [locales]="glibcLocales"
    [secrets]="age mkpasswd openssh sops ssh-to-age"
    [iso]="disko"
)

# ── nix-shell ────────
shell() {
    if [[ -z ${IN_NIX_SHELL:-} ]]; then
        MODULES=("base" "secrets" "locales" "iso")
    
        pkgs=""
        for mod in "${MODULES[@]}"; do
            pkgs+=" ${MODULE_PKGS[$mod]}"
        done
    
        printf "Fetching dependencies ..."
        # shellcheck disable=SC2086
        exec nix-shell -p $pkgs --run "$(printf '%q ' bash "$0" "$@")"
    fi
}

# ── gum wrappers ────────
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
    gum style --foreground="$MUTED" "$label: $value"
}

formInputOpt() {
    local __var="$1" label="$2" placeholder="${3:-$2}" value
    value=$(gum input --header="$label" --placeholder="$placeholder") || true
    printf -v "$__var" '%s' "$value"
    gum style --foreground="$MUTED" "$label: ${value:-skip}"
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
    gum style --foreground="$MUTED" "$label: $selected"
}

formMulti() {
    local __var="$1" label="$2"; shift 2
    local selected
    selected=$(gum choose --no-limit --header="$label" --height=15 "$@") || true
    local -n __ref="$__var"
    [[ -n $selected ]] && mapfile -t __ref <<< "$selected" || __ref=()
    gum style --foreground="$MUTED" "$label: ${__ref[*]:-none}"
}

formConfirm() {
    local label="$1" default="${2:-n}"
    case "$default" in
        y|yes|1) default=true ;;
        n|no|0)  default=false ;;
        *)       default=false ;;
    esac
    if gum confirm --default="$default" "$label"; then
        gum style --foreground="$MUTED" "$label: yes"
        return 0
    else
        gum style --foreground="$MUTED" "$label: no"
        return 1
    fi
}

formFilter() {
    local __var="$1" label="$2" options="$3" placeholder="${4:-$2}" selected
    [[ -n $options ]] || return 1
    selected=$(gum filter \
        --header="$label" \
        --height=15 \
        --placeholder="$placeholder" <<< "$options") || die "Cancelled"
    printf -v "$__var" '%s' "$selected"
    gum style --foreground="$MUTED" "$label: $selected"
}

# ── filter lists ────────
# == nixos-hardware modules ==
listNixosHardwareModules() {
    local rev ref="github:NixOS/nixos-hardware"
    rev="$(jq -r '.nodes["nixos-hardware"].locked.rev // empty' "$FLAKE/flake.lock" 2>/dev/null || true)"
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

# == networks ==
listWifiNetworks() {
    command -v nmcli &>/dev/null || return 1
    nmcli -t -f SSID device wifi list --rescan no 2>/dev/null \
        | sed 's/\\:/:/g' | awk 'NF' | sort -u
}

# == timezones ==
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

# == locales ==
listSupportedLocales() {
    command -v locale &>/dev/null || return 1
    locale -a 2>/dev/null \
        | grep -iE '\.utf-?8$' \
        | sed -E 's/\.utf-?8$/.UTF-8/I' \
        | sort -u
}

# == disks ==
listDisks() {
    lsblk -dno NAME,SIZE,MODEL -e 7,11 2>/dev/null | awk 'NF'
}

# == list directories ==
listDirs() {
    find / -xdev -maxdepth 6 -type d \
        \( -path /nix -o -path /proc -o -path /sys -o -path /dev -o -path /run \
           -o -name .git -o -name .cache -o -name node_modules \) -prune -o \
        -type d -print 2>/dev/null | sort -u
}

# ── information gathering ────────
gather() {
    while :; do
        # == host ==
        formHeader "Identity"
        HOSTNAME=""
        SYSTEM=""

        while :; do
            formInput HOSTNAME "Hostname" "nixos" ""
            if [[ ! $HOSTNAME =~ ^[a-z][a-z0-9-]{0,62}$ ]]; then
                logWarn "Lowercase letters, digits, and hyphens only"
                continue
            fi
            if [[ -d $FLAKE/hosts/$HOSTNAME ]]; then
                logWarn "hosts/$HOSTNAME already exists"
                continue
            fi
            break
        done
        
        formChoose SYSTEM "Architecture" "x86_64-linux" "aarch64-linux"

        # == roles ==
        formHeader "Role"
        ROLES=""
        ADDONS=()
        
        formChoose ROLES "Primary role" "desktop" "server"
        if [[ $ROLES == "desktop" ]]; then
            formMulti ADDONS "Add-ons" "dev"
        fi

        # == user ==
        formHeader "User"
        USERNAME=""
        USEREMAIL=""
        
        while :; do
            formInput USERNAME "Username" "$(whoami)" "login name"
            [[ $USERNAME =~ ^[a-z_][a-z0-9_-]{0,31}$ ]] && break
            logWarn "Lowercase letters, digits, hyphens, underscores; start with letter or underscore"
        done
        
        while :; do
            formInputOpt USEREMAIL "Email" "$USERNAME@$HOSTNAME"
            [[ -n $USEREMAIL && $USEREMAIL == *@* ]] && break
            logWarn "Email cannot be empty and must contain '@'"
        done

        # == locale ==
        formHeader "Locale"
        TIMEZONE=""
        LOCALE=""
        LOCALE_EXTRA=""
        
        formFilter TIMEZONE "Timezone" "$(listSupportedTimezones)" "e.g. America/New_York, Europe/London..." \
            || die "No timezones found"

        formFilter LOCALE "Default locale" "$(listSupportedLocales)" "e.g. en_US.UTF-8, de_DE.UTF-8..." \
            || die "No locale found"
            
        LOCALE_EXTRA=$LOCALE

        # == hardware ==
        formHeader "Hardware"
        GPU=()
        HW_MODULES=()
        
        formMulti GPU "Select GPU. Both discrete and/or integrated" "nvidia" "amd" "intel"
        
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
                formMulti HW_MODULES "Common hardware modules" \
                    "common-cpu-amd" "common-cpu-intel" \
                    "common-gpu-amd" "common-gpu-intel" "common-gpu-nvidia" \
                    "common-pc-laptop-hdd" "common-pc-ssd"
            fi
        fi
        
        # == disk ==
        formHeader "Disk"
        DISK=""
        
        logWarn "The selected disk will be wiped"
        formFilter DISK "Choose disk" "$(listDisks)" "" \
            || die "No disks found"
        DISK="/dev/$(awk '{print $1}' <<< "$DISK")"

        # == Network (optional) ==
        formHeader "Network (optional)"
        WIFI='{}'
        
        if formConfirm "Add wifi network(s)?" "n"; then
            local name ssid psk
        
            while :; do
                formInput name "Connection name" "" "home"
        
                if jq -e --arg n "$name" 'has($n)' <<< "$WIFI" > /dev/null 2>&1; then
                    logWarn "'$name' is already configured"
                    continue
                fi
        
                formFilter ssid "Select network" "$(listWifiNetworks)" "select SSID" \
                    || formInput ssid "SSID (network name)" "" "my-network"
        
                formPassword psk "WPA password (8-63 chars)" false
        
                WIFI=$(jq --argjson prev "$WIFI" \
                    --arg name "$name" --arg ssid "$ssid" --arg psk "$psk" \
                    '$prev + {
                        ($name): {
                            connection: { id: $name, type: "wifi" },
                            wifi: { ssid: $ssid },
                            "wifi-security": { "key-mgmt": "wpa-psk", psk: $psk }
                        }
                    }' <<< "{}")
        
                logInfo "Added '$name' ($ssid)"
                formConfirm "Add another network?" "n" || break
            done
        fi

        # == dotfiles (optional) ==
        formHeader "Dotfiles (optional)"
        DOTFILES=""
        
        if formConfirm "Clone dotfiles from a source?" "n"; then
            formChoose DOTFILES_METHOD "Method" "path" "git clone" 
            
            if [[ $DOTFILES_METHOD == "path" ]]; then
                formFilter DOTFILES "Select directory" "$(listDirs)" "enter path" \
                    || die "No directories found"
            else
                formInput DOTFILES "git repo to clone" "enter link"
            fi
        fi
        
        # == summary ==
        formHeader "Review Configuration"
        
        local wifi_count wifi_str
        wifi_count="$(jq -r 'keys | length' <<< "$WIFI" 2>/dev/null || echo 0)"
        (( wifi_count > 0 )) && wifi_str="$wifi_count network(s)"
    
        gum style --border="rounded" --padding="1 2" --margin="1 0" \
            <<EOF
    Hostname       $HOSTNAME
    SYSTEM         $SYSTEM
    Role           $ROLES ${ADDONS[*]}
    User           $USERNAME <$USEREMAIL>
    GPU            ${GPU[*]:-skip}
    HW modules     ${HW_MODULES[*]:-skip}
    Timezone       $TIMEZONE
    Locale         $LOCALE / $LOCALE_EXTRA
    Disk           $DISK
    Wi-Fi          ${wifi_str:-skip}
    Dotfiles       ${DOTFILES:-skip}
EOF

        if formConfirm "Is this correct?" "y"; then
            break
        fi
        
        logWarn "Redoing..."
    done
}

# ── partition disk ────────
partition() {
    cat > "$TEMP_DIR/disko.nix" <<EOF
{ ... }:
let
    device = "$DISK";
in
{
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
                        mountOptions = [
                            "defaults"
                            "umask=0077" 
                        ];
                    };
                };
                root = {
                    size = "100%";
                    content = {
                        type = "btrfs";
                        subvolumes = {
                            "/root" = {
                                mountpoint = "/";
                                mountOptions = [ "compress=zstd" "noatime" "space_cache=v2" ];
                            };
                            "/nix" = {
                                mountpoint = "/nix";
                                mountOptions = [ "compress=zstd" "noatime" "space_cache=v2" ];
                            };
                            "/persistent" = {
                                mountpoint = "/persistent";
                                mountOptions = [ "compress=zstd" "noatime" "space_cache=v2" ];
                            };
                            "/home" = {
                                mountpoint = "/home";
                                mountOptions = [ "compress=zstd" "noatime" "space_cache=v2" ];
                            };
                        };
                    };
                };
            };
        };
    };
}
EOF

    disko --mode destroy,format,mount "$TEMP_DIR/disko.nix"
}

# ── generate ssh keys ────────
generate() {
    # == host keys ==
    run ssh-keygen -t ed25519 -N "" -C "root@$HOSTNAME" -f "$TEMP_DIR/ssh_host_ed25519_key"
    HOST_AGE="$(ssh-to-age < "$TEMP_DIR/ssh_host_ed25519_key.pub")"
    
    logDebug "Host fingerprint: $(ssh-keygen -lf "$TEMP_DIR/ssh_host_ed25519_key.pub")"
    
    # == user keys == 
    run ssh-keygen -t ed25519 -N "" -C "$USERNAME@$HOSTNAME" -f "$TEMP_DIR/id_$USERNAME"
    USER_AGE="$(ssh-to-age < "$TEMP_DIR/id_$USERNAME.pub")"
    USER_KEY="$(< "$TEMP_DIR/id_$USERNAME.pub")"
    
    logDebug "User fingerprint: $(ssh-keygen -lf "$TEMP_DIR/id_$USERNAME.pub")"
}

# ── write .sops.yaml ────────
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
    awk -v userAnchor="    - &${USERNAME}_${HOSTNAME} " \
        -v hostAnchor="    - &$HOSTNAME " \
        -v rulePrefix="  - path_regex: hosts/$HOSTNAME/secrets" '
        index($0, userAnchor) == 1 { next }
        index($0, hostAnchor) == 1 { next }
        index($0, rulePrefix) == 1 { skip = 1; next }
        skip && (/^  - / || /^[^ ]/) { skip = 0 }
        skip { next }
        { print }
    ' .sops.yaml > .sops.yaml.tmp
    mv .sops.yaml.tmp .sops.yaml

    insertBefore "    - &${USERNAME}_${HOSTNAME} $USER_AGE" "  - &hosts:"
    insertBefore "    - &$HOSTNAME $HOST_AGE" "creation_rules:"

    {
        printf '  - path_regex: %s$\n' "hosts/$HOSTNAME/secrets\.json"
        printf '    key_groups:\n'
        printf '      - age:\n'
        printf '          - *%s\n' "${USERNAME}_${HOSTNAME}"
        printf '          - *%s\n' "$HOSTNAME"
    } >> .sops.yaml
    
    git -C "$FLAKE" add --intent-to-add .sops.yaml
    
    logInfo "Added recipients and creation rule"
}

# ── write secrets.json ────────
writeSecrets() {
    local hash pwd
    
    formPassword pwd "Login password for '$USERNAME'"
    hash="$(printf '%s' "$pwd" | mkpasswd -m sha-512 --stdin)"

    jq -n \
        --arg pw "$hash" \
        --rawfile key "$TEMP_DIR/id_$USERNAME" \
        --argjson wifi "$WIFI" \
        '{ userPassword: $pw, userPrivateKey: $key }
         + (if $wifi == {} then {} else { wifi: $wifi } end)' \
        > "$FLAKE/hosts/$HOSTNAME/secrets.json"

    run sops --encrypt --in-place "$FLAKE/hosts/$HOSTNAME/secrets.json"
    
    git -C "$FLAKE" add --intent-to-add "hosts/$HOSTNAME/secrets.json"
    
    logInfo "Encrypted secrets"
}

# ── write host.json ────────
writeHostJson() {
    local rolesJson gpuJson modulesJson
    
    rolesJson=$(printf '%s\n' "$ROLES" "${ADDONS[@]}" | jq -R . | jq -sc 'map(select(. != ""))')
    gpuJson=$(printf '%s\n' "${GPU[@]:-}" | jq -R . | jq -sc 'map(select(. != ""))')
    modulesJson=$(printf '%s\n' "${HW_MODULES[@]:-}" | jq -R . | jq -sc 'map(select(. != ""))')
    
    jq -n \
        --arg hostname "$HOSTNAME" \
        --arg system "$SYSTEM" \
        --arg repoPath "/home/${USERNAME}/nixos-config" \
        --arg userName "$USERNAME" \
        --arg userEmail "$USEREMAIL" \
        --arg userKey "$USER_KEY" \
        --arg tz "$TIMEZONE" \
        --arg locale "$LOCALE" \
        --arg extra "$LOCALE_EXTRA" \
        --argjson roles "$rolesJson" \
        --argjson gpu "$gpuJson" \
        --argjson modules "$modulesJson" \
        '{
            hostname: $hostname,
            system: $system,
            repoPath: $repoPath,
            roles: $roles,
            user: {
                name: $userName,
                email: $userEmail,
                sshKeys: [ $userKey ]
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
        }' > "$FLAKE/hosts/$HOSTNAME/host.json"

    git -C "$FLAKE" add --intent-to-add "hosts/$HOSTNAME/host.json"

    logInfo "Wrote host file"
}

# ── hardware.nix ────────
writeHardwareNix() {
    local body

    # Generates hardware config and deletes: 
    # - The "Do not modify this file!" comment
    # - Argument header
    # - Opening and closing curly brackets
    body="$(nixos-generate-config --show-hardware-config --no-filesystems --root /mnt \
        | sed -e '/^ *#/d' \
              -e '/^{.*}:$/d' \
              -e '/^{$/d' \
              -e '/^}$/d')"

    # shellcheck disable=SC2001
    body="$(sed -e 's/^./        &/' <<< "$body" | cat -s)"
    
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
    } > "$FLAKE/hosts/$HOSTNAME/hardware.nix"
    
    git -C "$FLAKE" add --intent-to-add "hosts/$HOSTNAME/hardware.nix"
    
    logInfo "Generated hardware configuration"
}

# ── disko.nix ────────
writeDiskoNix() {
    cat > "$FLAKE/hosts/$HOSTNAME/disko.nix" <<EOF
{ inputs, ... }:
let
    inherit (builtins.fromJSON (builtins.readFile ./host.json)) hostname;
    device = "$DISK";
in
{
    flake.modules.nixos."\${hostname}Disko" = { ... }: {
        imports = [ inputs.disko.nixosModules.disko ];

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
                            mountOptions = [
                                "defaults"
                                "umask=0077" 
                            ];
                        };
                    };
                    root = {
                        size = "100%";
                        content = {
                            type = "btrfs";
                            subvolumes = {
                                "/root" = {
                                    mountpoint = "/";
                                    mountOptions = [ "compress=zstd" "noatime" "space_cache=v2" ];
                                };
                                "/nix" = {
                                    mountpoint = "/nix";
                                    mountOptions = [ "compress=zstd" "noatime" "space_cache=v2" ];
                                };
                                "/persistent" = {
                                    mountpoint = "/persistent";
                                    mountOptions = [ "compress=zstd" "noatime" "space_cache=v2" ];
                                };
                                "/home" = {
                                    mountpoint = "/home";
                                    mountOptions = [ "compress=zstd" "noatime" "space_cache=v2" ];
                                };
                            };
                        };
                    };
                };
            };
        };
    };
}
EOF
    git -C "$FLAKE" add --intent-to-add "hosts/$HOSTNAME/disko.nix"
    
    logInfo "Wrote disko file"
}

# ── profile.nix ────────
writeProfileNix() {
    cat > "$FLAKE/hosts/$HOSTNAME/profile.nix" <<'EOF'
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
    git -C "$FLAKE" add --intent-to-add "hosts/$HOSTNAME/profile.nix"
    
    logInfo "Wrote host profile"
}

# ── write dotfiles ────────
writeDotfiles() {
    mkdir -p "$FLAKE/hosts/$HOSTNAME/home"

    if [[ -z $DOTFILES ]]; then
        return 0
    fi

    if [[ $DOTFILES_METHOD == "path" ]]; then
        run cp -rT "$DOTFILES" "$FLAKE/hosts/$HOSTNAME/home"
        run rm -rf "$FLAKE/hosts/$HOSTNAME/home/.git"
    else
        if run git clone "$DOTFILES" "$TEMP_DIR/home"; then
            run cp -rT "$TEMP_DIR/home" "$FLAKE/hosts/$HOSTNAME/home"
            run rm -rf "$FLAKE/hosts/$HOSTNAME/home/.git"
        else 
            die "Failed to clone git repository"
        fi
    fi
    
    git -C "$FLAKE" add --intent-to-add "hosts/$HOSTNAME/home"
    
    logInfo "Copied dotfiles"
}

# ── writing all host relevant files ────────
write() {
    mkdir -p "$FLAKE/hosts/$HOSTNAME"
    
    writeSopsYaml
    writeSecrets
    writeHostJson
    writeHardwareNix
    writeDiskoNix
    writeProfileNix
    writeDotfiles
    
    if formConfirm "Validate files?" "y"; then
        gum pager < "$FLAKE/.sops.yaml"
        gum pager < "$FLAKE/hosts/$HOSTNAME/secrets.json"
        gum pager < "$FLAKE/hosts/$HOSTNAME/host.json"
        gum pager < "$FLAKE/hosts/$HOSTNAME/hardware.nix"
        gum pager < "$FLAKE/hosts/$HOSTNAME/disko.nix"
        gum pager < "$FLAKE/hosts/$HOSTNAME/profile.nix"
        ls -la -R "$FLAKE/hosts/$HOSTNAME/home"
        
        if formConfirm "Everything fine?" "n"; then
          die "Remove created files and rerun script"
        fi
    fi
}

# ── install ────────
install() {
    formConfirm "Install the configuration now?" "y" || { die "Skipped install"; }

    nixos-install --root /mnt --flake .#"$HOSTNAME"
    nixos-enter --root /mnt
    
    # == host keys ==
    run install -d -m 755 "/persistent/etc/ssh"
    run install -m 644 "$TEMP_DIR/ssh_host_ed25519_key.pub" "/persistent/etc/ssh/ssh_host_ed25519_key.pub"
    run install -m 600 "$TEMP_DIR/ssh_host_ed25519_key" "/persistent/etc/ssh/ssh_host_ed25519_key"
    
    # == user home ==
    run mkdir -p "/home/$USERNAME"
    run cp -rT "$FLAKE" "/home/$USERNAME/nixos-config" 
    
    # == user keys ==
    run install -d -m 700 "/home/$USERNAME/.ssh"
    run install -m 644 "$TEMP_DIR/id_$USERNAME.pub" "/home/$USERNAME/.ssh/id_$USERNAME.pub"
    run install -m 600 "$TEMP_DIR/id_$USERNAME" "/home/$USERNAME/.ssh/id_$USERNAME"

    # == ownership ==
    run chown -R 1000:100 "/home/$USERNAME"

    logInfo "Successfully installed $HOSTNAME"

    formConfirm "Reboot now?" "y" || { die "Reboot manually"; }
    reboot
}

# ── main ────────
main() {
    parseArgs "$@"
    shell "$@"
    clear
    
    if [[ $VERBOSE == true ]]; then
      export GUM_LOG_LEVEL=debug
    else
      export GUM_LOG_LEVEL=info
    fi
    
    # Set path to flake.nix and cd into it
    FLAKE=$(dirname -- "$(readlink -f -- "$0")")
    cd "$FLAKE"

    # Temp directory for installer to use
    TEMP_DIR="$(mktemp -d)"
    chmod 700 "$TEMP_DIR"

    gather
    partition
    generate
    write
    install
}

main "$@"