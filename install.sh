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
KEYBOARD=""
KEYBOARD_VARIANT=""

# == secrets ==
HOST_AGE=""
USER_AGE=""
WIFI='{}'

# == temp ==
FLAKE=""
TEMP_DIR=""
DISK=""
SWAP=""
HIBERNATE=false
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
    if [[ $VERBOSE == true ]]; then
        logDebug "\$ $*"
        "$@"
    else
        gum spin --title "$*" --show-error -- "$@"
    fi
}

# ── traps ────────
trapError() {
    local code=$? cmd=$BASH_COMMAND line=${BASH_LINENO[0]} fn=${FUNCNAME[1]:-main}
    logError "'$cmd' failed (exit $code) at $fn():$line"
    exit "$code"
}
trap trapError ERR

cleanup() {
    if [[ -n ${TEMP_DIR:-} ]]; then
        [[ -d $TEMP_DIR ]] && rm -rf "$TEMP_DIR"
    fi
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
    [locales]="glibcLocales xkeyboard_config"
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

# == locale ==
listSupportedLocales() {
    command -v locale &>/dev/null || return 1
    locale -a 2>/dev/null \
        | grep -iE '\.utf-?8$' \
        | sed -E 's/\.utf-?8$/.UTF-8/I' \
        | sort -u
}

# == keyboard layouts ==
XKB_RULES=""

xkbRules() {
    local p

    if [[ -n $XKB_RULES ]]; then
        printf '%s\n' "$XKB_RULES"
        return 0
    fi

    # shellcheck disable=SC2086
    for p in ${buildInputs:-} \
             /run/current-system/sw \
             /usr; do
        if [[ -r $p/share/X11/xkb/rules/base.lst ]]; then
            XKB_RULES="$p/share/X11/xkb/rules/base.lst"
            printf '%s\n' "$XKB_RULES"
            return 0
        fi
    done

    return 1
}

listKeyboardLayouts() {
    local out lst

    out=$(localectl list-x11-keymap-layouts 2>/dev/null | awk 'NF' || true)

    if [[ -z $out ]] && lst=$(xkbRules); then
        out=$(awk '/^! layout/{f=1;next} /^!/{f=0} f&&NF{print $1}' "$lst")
    fi

    if [[ -n $out ]]; then
        printf '%s\n' "$out"
    fi
}

listKeyboardVariants() {
    local out lst

    printf '(none)\n'

    out=$(localectl list-x11-keymap-variants "$1" 2>/dev/null | awk 'NF' || true)

    if [[ -z $out ]] && lst=$(xkbRules); then
        # Variant rows read "  nodeadkeys   de: German (no dead keys)"
        out=$(awk -v l="$1" '/^! variant/{f=1;next} /^!/{f=0} f&&$2==l":"{print $1}' "$lst")
    fi

    if [[ -n $out ]]; then
        printf '%s\n' "$out"
    fi
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
        
        if ! formFilter KEYBOARD "Keyboard layout" "$(listKeyboardLayouts)" "e.g. us, de, fr..."; then
            logWarn "No layout list available; enter one by hand"
            formInput KEYBOARD "Keyboard layout" "e.g. us, de, fr..."
        fi

        if ! formFilter KEYBOARD_VARIANT "Layout variant" \
                "$(listKeyboardVariants "$KEYBOARD")" "(none) for the default"; then
            KEYBOARD_VARIANT=""
        fi

        if [[ $KEYBOARD_VARIANT == "(none)" ]]; then
            KEYBOARD_VARIANT=""
        fi

        # == hardware ==
        formHeader "Hardware"
        GPU=()
        HW_MODULES=()
        
        formMulti GPU "Select GPU. Both discrete and/or integrated" "amd" "intel" "nvidia"
        
        if formConfirm "Use nixos-hardware modules?" "n"; then            
            if formConfirm "Add a specific model from nixos-hardware?" "n"; then
                local models selection=""
                models="$(listNixosHardwareModules || true)"
                
                if [[ -n $models ]] && formFilter selection "Search for your model" "$models" "e.g. apple-macbook-pro-8-1, asus-rog-strix-x570e, ..."; then
                    HW_MODULES+=("$selection")
                else
                    logInfo "https://github.com/NixOS/nixos-hardware"
                    formInputOpt selection "Module name" ""
                    [[ -n $selection ]] && HW_MODULES+=("$selection")
                fi
            else
                local pick modules=(
                    "AMD CPU|common-cpu-amd"
                    "Intel CPU|common-cpu-intel-cpu-only"
                    "Intel CPU + iGPU|common-cpu-intel"
                    "AMD GPU|common-gpu-amd"
                    "Intel GPU|common-gpu-intel"
                    "NVIDIA GPU|common-gpu-nvidia-nonprime"
                    "SSD|common-pc-laptop-ssd"
                    "HDD|common-pc-laptop-hdd"
                    "Laptop|common-pc-laptop"
                    "HiDPI console|common-hidpi"
                )

                formMulti pick "Common hardware modules" "${modules[@]%%|*}"
                
                for p in "${pick[@]}"; do
                    for m in "${modules[@]}"; do
                        [[ ${m%%|*} == "$p" ]] && HW_MODULES+=("${m##*|}")
                    done
                done
            fi
        fi
        
        # == disk ==
        formHeader "Disk"
        DISK=""
        
        logWarn "The selected disk will be wiped"
        formFilter DISK "Choose disk" "$(listDisks)" "" \
            || die "No disks found"
        DISK="/dev/$(awk '{print $1}' <<< "$DISK")"

        # == swap ==
        formHeader "Swap"
        SWAP=""
        HIBERNATE=false
        
        ram=$(( $(awk '/MemTotal/{print $2}' /proc/meminfo) / 1048576 ))
        logInfo "Detected ${ram}GiB of RAM"
        
        if formConfirm "Enable hibernation?" "n"; then
            HIBERNATE=true
            swapDefault=$(( ram + 2 ))
        else
            swapDefault=$(( ram < 8 ? ram : 8 ))
        fi
        
        while :; do
            formInputOpt SWAP "Swap size in GiB" "$swapDefault"
            SWAP="${SWAP:-$swapDefault}"
            [[ $SWAP =~ ^[0-9]+$ ]] && (( SWAP > 0 )) && break
            logWarn "Enter a whole number of GiB"
        done

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
    Keyboard       $KEYBOARD / ${KEYBOARD_VARIANT:-skip}
    Disk           $DISK
    Swap           $SWAP
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
    formHeader "Partitioning";
    
    mkdir -p "$FLAKE/hosts/$HOSTNAME"
    cat > "$FLAKE/hosts/$HOSTNAME/disko.nix" <<EOF
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
        swap = {
          priority = 2;
          size = "${SWAP}G";
          content = {
            type = "swap";
            discardPolicy = "both";
            resumeDevice = $HIBERNATE;
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
            };
          };
        };
      };
    };
  };
}
EOF
      git -C "$FLAKE" add --intent-to-add "hosts/$HOSTNAME/disko.nix"
      disko --mode destroy,format,mount "$FLAKE/hosts/$HOSTNAME/disko.nix"
}

# ── generate ssh keys ────────
generate() {
    formHeader "Generating keys";
    
    # == host keys ==
    run ssh-keygen -t ed25519 -N "" -C "root@$HOSTNAME" -f "$TEMP_DIR/ssh_host_ed25519_key"
    HOST_AGE="$(ssh-to-age < "$TEMP_DIR/ssh_host_ed25519_key.pub")"
    
    logInfo "Host fingerprint: $(ssh-keygen -lf "$TEMP_DIR/ssh_host_ed25519_key.pub")"
    
    # == user keys == 
    run ssh-keygen -t ed25519 -N "" -C "$USERNAME@$HOSTNAME" -f "$TEMP_DIR/id_ed25519"
    USER_AGE="$(ssh-to-age < "$TEMP_DIR/id_ed25519.pub")"
    USER_KEY="$(< "$TEMP_DIR/id_ed25519.pub")"
    
    logInfo "User fingerprint: $(ssh-keygen -lf "$TEMP_DIR/id_ed25519.pub")"
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
        --rawfile key "$TEMP_DIR/id_ed25519" \
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
        --arg configPath "/home/${USERNAME}/nixos-config" \
        --argjson roles "$rolesJson" \
        --arg userName "$USERNAME" \
        --arg userEmail "$USEREMAIL" \
        --arg userKey "$USER_KEY" \
        --argjson gpu "$gpuJson" \
        --argjson modules "$modulesJson" \
        --arg tz "$TIMEZONE" \
        --arg locale "$LOCALE" \
        --arg extra "$LOCALE_EXTRA" \
        --arg layout "$KEYBOARD" \
        --arg variant "$KEYBOARD_VARIANT" \
        '{
            hostname: $hostname,
            system: $system,
            configPath: $configPath,
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
                localeExtra: $extra,
                xkbLayout: $layout,
                xkbVariant: $variant
            }
        }' > "$FLAKE/hosts/$HOSTNAME/host.json"

    git -C "$FLAKE" add --intent-to-add "hosts/$HOSTNAME/host.json"

    logInfo "Wrote host file"
}

# ── hardware.nix ────────
writeHardwareNix() {
    nixos-generate-config --show-hardware-config --no-filesystems --root /mnt > "$FLAKE/hosts/$HOSTNAME/hardware.nix"

    git -C "$FLAKE" add --intent-to-add "hosts/$HOSTNAME/hardware.nix"
    
    logInfo "Generated hardware configuration"
}

# ── drop submodules whose path no longer exists ────────
# The cloned branch carries whatever .gitmodules its author had. Those paths
# point at their hosts, not ours, and a section without a matching gitlink
# makes `git submodule update --init` noisy for every later rebuild.
pruneSubmodules() {
    local name path

    [[ -f $FLAKE/.gitmodules ]] || return 0

    while read -r name; do
        name=${name#submodule.}
        name=${name%.path}

        path=$(git -C "$FLAKE" config -f .gitmodules --get "submodule.$name.path" || true)

        if [[ -n $path && -e $FLAKE/$path ]]; then
            continue
        fi

        git -C "$FLAKE" config -f .gitmodules --remove-section "submodule.$name"
        logWarn "Dropped stale submodule '$name'"
    done < <(git -C "$FLAKE" config -f .gitmodules --name-only \
                --get-regexp '^submodule\..*\.path$' || true)

    if [[ ! -s $FLAKE/.gitmodules ]]; then
        rm -f "$FLAKE/.gitmodules"
        return 0
    fi

    git -C "$FLAKE" add --intent-to-add .gitmodules
}

# ── write dotfiles ────────
writeDotfiles() {
    local dest="$FLAKE/hosts/$HOSTNAME/home"

    mkdir -p "$dest"

    if [[ -z $DOTFILES ]]; then
        pruneSubmodules
        return 0
    fi

    if [[ $DOTFILES_METHOD == "path" ]]; then
        run cp -rT "$DOTFILES" "$dest"
    else
        run git clone --recurse-submodules "$DOTFILES" "$TEMP_DIR/home" \
            || die "Failed to clone git repository"
        run cp -rT "$TEMP_DIR/home" "$dest"
    fi

    # Flatten. A nested .git — a directory for the clone itself, a file for each
    # submodule — makes the outer repo treat that path as a gitlink, and we have
    # no .gitmodules entry to back it. Plain tracked files always evaluate.
    run find "$dest" -name .git -prune -exec rm -rf {} +
    rm -f "$dest/.gitmodules"

    pruneSubmodules

    git -C "$FLAKE" add --intent-to-add "hosts/$HOSTNAME/home"

    logInfo "Copied dotfiles"
}

# ── writing all host relevant files ────────
write() {
    formHeader "Writing files";
    
    writeSopsYaml
    writeSecrets
    writeHostJson
    writeHardwareNix
    writeDotfiles
    
    if formConfirm "Validate files?" "y"; then
        gum pager < "$FLAKE/.sops.yaml"
        gum pager < "$FLAKE/hosts/$HOSTNAME/secrets.json"
        gum pager < "$FLAKE/hosts/$HOSTNAME/host.json"
        gum pager < "$FLAKE/hosts/$HOSTNAME/hardware.nix"
        gum pager < "$FLAKE/hosts/$HOSTNAME/disko.nix"
        ls -la -R "$FLAKE/hosts/$HOSTNAME/home"
        
        if ! formConfirm "Everything fine?" "y"; then
            die "Remove created files and rerun script"
        fi
    fi
}

# ── install ────────
installSystem() {
    formHeader "Installing";
    
    formConfirm "Install now?" "y" || die "Skipped install"
    
    # == move files to target ==
    run mkdir -p /mnt/tmp
    export TMPDIR=/mnt/tmp
    run systemctl set-environment TMPDIR=/mnt/tmp
    run systemctl restart nix-daemon
    
    # == host keys ==
    local ssh="/mnt/persistent/etc/ssh"
    
    run install -d -m 755 $ssh
    run install -m 644 "$TEMP_DIR/ssh_host_ed25519_key.pub" "$ssh/ssh_host_ed25519_key.pub"
    run install -m 600 "$TEMP_DIR/ssh_host_ed25519_key" "$ssh/ssh_host_ed25519_key"
    
    # == install ==
    logWarn "First install can take a while"
    nixos-install --root /mnt --flake "git+file://$FLAKE?submodules=1#$HOSTNAME" --no-root-passwd
  
    # == user home ==
    local home="/mnt/persistent/home/$USERNAME"
    
    run install -d -m 755 "$home"
    run cp -rT "$FLAKE" "$home/nixos-config"
    run install -d -m 700 "$home/.ssh"
    run install -m 644 "$TEMP_DIR/id_ed25519.pub" "$home/.ssh/id_ed25519.pub"
    run install -m 600 "$TEMP_DIR/id_ed25519" "$home/.ssh/id_ed25519"
    run chown -R 1000:100 "$home"

    logInfo "Installed $HOSTNAME"
    formConfirm "Reboot now?" "y" || die "Reboot manually"
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

    installSystem
}

main "$@"