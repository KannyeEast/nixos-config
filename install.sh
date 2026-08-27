#!/usr/bin/env bash

#
# installer.sh - bootstrap a host for this flake
#

set -Eeuo pipefail

# ── script variables ────────
# == flags ==
VERBOSE=false
REMOTE=false

# == host ==
HOSTNAME=""
HOST_KEY=""
SYSTEM=""
EXISTING=false
ROLE=""
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

# == roles ==
DESKTOP_ADDONS=("dev")
SERVER_ADDONS=("dev")

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
SSH_OPTS=()
TARGET=""

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

# ── logging/helpers ────────
logInfo() { gum log --level info "$*"; }
logWarn() { gum log --level warn "$*"; }
logError() { gum log --level error "$*"; }
logDebug() { gum log --level debug "$*"; }

die() { logError "$1"; exit "${2:-1}"; }

# == wrap command in gum styling ==
run() {
  if [[ $VERBOSE == true ]]; then
    logDebug "\$ $*"
    "$@"
  else
    gum spin --title "$*" --show-error -- "$@"
  fi
}

# == multiplexing ==
sshInit() {
  SSH_OPTS=(
    -o ControlMaster=auto
    -o ControlPath="$TEMP_DIR/ssh-%C"
    -o ControlPersist=120
    -o ConnectTimeout=10
    -o UserKnownHostsFile="$TEMP_DIR/known_hosts"
    -o StrictHostKeyChecking=accept-new
  )
}

# == decide where to execute command ==
probe() {
  if [[ $REMOTE == true ]]; then
    ssh "${SSH_OPTS[@]}" "$TARGET" "$@"
  else
    "$@"
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
Usage: ./installer.sh [OPTIONS]

Options:
  -r, --remote            Install the config through nixos-anywhere
  -v, --verbose           Show every command and its output
  -h, --help              This message
EOF
}

parseArgs() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      -r|--remote) REMOTE=true; shift ;;
      -v|--verbose) VERBOSE=true; shift ;;
      -h|--help) showFlags; exit 0 ;;
      *) printf 'Unknown option: %s\n' "$1" >&2; showFlags; exit 1 ;;
    esac
  done
}

# ── shell packages ────────
# Also turn all shell elements that run only once into nix run commands instead
declare -A MODULE_PKGS=(
  [base]="gum git jq"
  [locales]="glibcLocales xkeyboard_config"
  [secrets]="mkpasswd openssh sops ssh-to-age"
  [disk]="disko"
)

# ── nix-shell ────────
shell() {
  if [[ -z ${INSTALLER_SHELL:-} ]]; then
    local modules mod pkgs 
    
    modules=("base" "secrets" "locales")
    
    [[ $REMOTE == false ]] && modules+=("disk")

    pkgs=""
    for mod in "${modules[@]}"; do
      pkgs+=" ${MODULE_PKGS[$mod]}"
    done

    export INSTALLER_SHELL=1
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
  probe lsblk -dno NAME,SIZE,MODEL -e 7,11 | awk 'NF'
}

# == list directories ==
listDirs() {
  find / -xdev -maxdepth 6 -type d \
    \( -path /nix -o -path /proc -o -path /sys -o -path /dev -o -path /run \
      -o -name .git -o -name .cache -o -name node_modules \) -prune -o \
    -type d -print 2>/dev/null | sort -u
}

# ── information gathering ────────
# == ssh target ==
gatherTarget() {
  formHeader "Target"
  TARGET=""

  while :; do
    formInput TARGET "SSH destination" "root@192.168.1.50"

    # First connection authenticates and opens the socket
    if ssh "${SSH_OPTS[@]}" "$TARGET" true; then
      break
    fi
    logWarn "Cannot reach $TARGET"
  done

  logInfo "Connected to $(probe hostname) running $(probe uname -sr)"
}

# == host ==
gatherIdentity() {
  formHeader "Identity"
  HOSTNAME=""
  SYSTEM=""
  EXISTING=false

  while :; do
    formInput HOSTNAME "Hostname" "nixos" ""
    if [[ ! $HOSTNAME =~ ^[a-z][a-z0-9-]{0,62}$ ]]; then
      logWarn "Lowercase letters, digits, and hyphens only"
      continue
    fi
    if [[ -d $FLAKE/hosts/$HOSTNAME ]]; then
      logInfo "hosts/$HOSTNAME already exists"
      if formConfirm "Install as $HOSTNAME?" "n"; then
        EXISTING=true
        break
      fi
      continue
    fi
    break
  done

  # An existing host brings its own architecture along in host.json
  [[ $EXISTING == true ]] && return 0

  formChoose SYSTEM "Architecture" "x86_64-linux" "aarch64-linux"
}

# == reuse an existing host ==
loadHost() {
  local dir="$FLAKE/hosts/$HOSTNAME" file missing=()
  file="$dir/host.json"

  [[ -f $file ]] || missing+=("host.json")
  [[ -f $dir/disko.nix ]] || missing+=("disko.nix")
  [[ -f $dir/hardware.nix ]]|| missing+=("hardware.nix")

  if (( ${#missing[@]} > 0 )); then
    logError "hosts/$HOSTNAME is incomplete, missing: ${missing[*]}"
    return 1
  fi

  SYSTEM="$(jq -r '.host.system // empty' "$file")"
  ROLE="$(jq -r '.host.roles[0] // empty' "$file")"
  mapfile -t ADDONS < <(jq -r '.host.roles[1:][]?' "$file")
  USERNAME="$(jq -r '.user.name // empty' "$file")"
  USEREMAIL="$(jq -r '.user.email // empty' "$file")"
  mapfile -t GPU < <(jq -r '.hardware.gpu[]?' "$file")
  mapfile -t HW_MODULES < <(jq -r '.hardware.modules[]?' "$file")
  TIMEZONE="$(jq -r '.locale.timeZone // empty' "$file")"
  LOCALE="$(jq -r '.locale.default // empty' "$file")"
  LOCALE_EXTRA="$(jq -r '.locale.extra // empty' "$file")"
  KEYBOARD="$(jq -r '.locale.xkb.layout // empty' "$file")"
  KEYBOARD_VARIANT="$(jq -r '.locale.xkb.variant // empty' "$file")"

  if [[ -z $USERNAME ]]; then
    logError "hosts/$HOSTNAME/host.json has no user.name"
    return 1
  fi

  # Display only — the existing disko.nix is reused verbatim
  DISK="$(sed -n 's/^[[:space:]]*device = "\(.*\)";.*/\1/p' "$dir/disko.nix" | head -n1)"
  SWAP="$(sed -n 's/^[[:space:]]*size = "\([0-9]\+\)G";.*/\1/p' "$dir/disko.nix" | head -n1)"

  DOTFILES=""
  DOTFILES_METHOD=""

  logInfo "Reusing hosts/$HOSTNAME. Keys and secrets are regenerated"
  return 0
}

# == roles ==
gatherRole() {
  formHeader "Role"
  ROLE=""
  ADDONS=()

  local -a roles=("desktop" "server")
  local -a desktopAddons=("${DESKTOP_ADDONS[@]}")
  local -a serverAddons=("${SERVER_ADDONS[@]}")

  formChoose ROLE "Primary role" "${roles[@]}"

  # desktop -> desktopAddons, server -> serverAddons
  local ref="${ROLE}Addons"
  declare -p "$ref" &>/dev/null || return 0

  local -n addons="$ref"
  (( ${#addons[@]} > 0 )) && formMulti ADDONS "Add-ons" "${addons[@]}"

  return 0
}

# == user ==
gatherUser() {
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
}

# == locale ==
gatherLocale() {
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
}

# == hardware ==
gatherHardware() {
  formHeader "Hardware"
  GPU=()
  HW_MODULES=()

  formMulti GPU "Select GPU. Both discrete and/or integrated" "amd" "intel" "nvidia"

  formConfirm "Use nixos-hardware modules?" "y" || return 0

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
    local p m pick modules=(
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

  return 0
}

# == disk ==
gatherDisk() {
  formHeader "Disk"
  DISK=""

  logWarn "The selected disk will be wiped"
  formFilter DISK "Choose disk" "$(listDisks)" "" \
    || die "No disks found"
  DISK="/dev/$(awk '{print $1}' <<< "$DISK")"
}

# == swap ==
gatherSwap() {
  formHeader "Swap"
  SWAP=""
  HIBERNATE=false

  local ram swapDefault
  ram=$(( $(probe cat /proc/meminfo | awk '/MemTotal/{print $2}') / 1048576 ))
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
}

# == network (optional) ==
# Lives in secrets.json, so it is asked for on every install
gatherWifi() {
  formHeader "Network (optional)"
  WIFI='{}'

  formConfirm "Add wifi network(s)?" "n" || return 0

  local ssid psk

  while :; do
    if [[ $REMOTE == true ]]; then
      formInput ssid "SSID" ""
    else
      formFilter ssid "Select network" "$(listWifiNetworks)" "select SSID" \
        || formInput ssid "SSID" ""
    fi

    formPassword psk "WPA password (8-63 chars)" false

    WIFI=$(jq --argjson prev "$WIFI" \
      --arg ssid "$ssid" --arg psk "$psk" \
      '$prev + {
        ($ssid): {
          connection: { id: $ssid, type: "wifi" },
          wifi: { ssid: $ssid },
          "wifi-security": { "key-mgmt": "wpa-psk", psk: $psk }
        }
      }' <<< "{}")

    logInfo "Added '$ssid'"
    formConfirm "Add another network?" "n" || break
  done

  return 0
}

# == dotfiles (optional) ==
gatherDotfiles() {
  formHeader "Dotfiles (optional)"
  DOTFILES=""

  formConfirm "Clone dotfiles from a source?" "n" || return 0

  formChoose DOTFILES_METHOD "Method" "path" "git clone"

  if [[ $DOTFILES_METHOD == "path" ]]; then
    formFilter DOTFILES "Select directory" "$(listDirs)" "enter path" \
      || die "No directories found"
  else
    formInput DOTFILES "git repo to clone" "enter link"
  fi
}

# == summary ==
gatherSummary() {
  formHeader "Review Configuration"

  local wifi wifiStr="skip"
  wifi="$(jq -r 'keys | length' <<< "$WIFI" 2>/dev/null || echo 0)"
  (( wifi > 0 )) && wifiStr="$wifi network(s)"

  row() { printf '    %-14s %s\n' "$1" "$2"; }

  {
    [[ $REMOTE == true ]] && { row Target "$TARGET"; echo; }

    row Hostname "$HOSTNAME"
    row System "$SYSTEM"
    row Role "$ROLE ${ADDONS[*]}"
    row User "$USERNAME <$USEREMAIL>"
    row GPU "${GPU[*]:-skip}"
    row "HW modules" "${HW_MODULES[*]:-skip}"
    row Timezone "$TIMEZONE"
    row Locale "$LOCALE / $LOCALE_EXTRA"
    row Keyboard "$KEYBOARD / ${KEYBOARD_VARIANT:-skip}"
    row Disk "$DISK"
    row Swap "$SWAP"
    [[ $ROLE == "desktop" ]] && { row Wi-Fi "$wifiStr"; }
    [[ $ROLE == "desktop" ]] && { row Dotfiles "${DOTFILES:-skip}"; }
  } | gum style --border="rounded" --padding="1 2" --margin="1 0"
}

gather() {
  while :; do
    [[ $REMOTE == true ]] && gatherTarget
    
    gatherIdentity

    if [[ $EXISTING == true ]]; then
      loadHost || { logWarn "Pick a different hostname"; continue; }
    else
      gatherRole
      gatherUser
      gatherLocale
      gatherHardware
      gatherDisk
      gatherSwap
      
      [[ $ROLE == "desktop" ]] && gatherDotfiles
    fi

    [[ $ROLE == "desktop" ]] && gatherWifi
    gatherSummary

    if formConfirm "Is this correct?" "y"; then
      break
    fi

    logWarn "Redoing..."
  done
}

# ── generate ssh keys ────────
generate() {
  formHeader "Generating keys";

  # == host keys ==
  run ssh-keygen -t ed25519 -N "" -C "root@$HOSTNAME" -f "$TEMP_DIR/ssh_host_ed25519_key"
  HOST_AGE="$(ssh-to-age < "$TEMP_DIR/ssh_host_ed25519_key.pub")"
  HOST_KEY="$(< "$TEMP_DIR/ssh_host_ed25519_key.pub")"

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
    '{ user-password: $pw, user-privatekey: $key }
      + (if $wifi == {} then {} else { wifi: $wifi } end)' \
    > "$FLAKE/hosts/$HOSTNAME/secrets.json"

  run sops --encrypt --in-place "$FLAKE/hosts/$HOSTNAME/secrets.json"

  git -C "$FLAKE" add --intent-to-add "hosts/$HOSTNAME/secrets.json"

  logInfo "Encrypted secrets"
}

# ── write host.json ────────
writeHostJson() {
  local rolesJson gpuJson modulesJson

  rolesJson=$(printf '%s\n' "$ROLE" "${ADDONS[@]}" | jq -R . | jq -sc 'map(select(. != ""))')
  gpuJson=$(printf '%s\n' "${GPU[@]:-}" | jq -R . | jq -sc 'map(select(. != ""))')
  modulesJson=$(printf '%s\n' "${HW_MODULES[@]:-}" | jq -R . | jq -sc 'map(select(. != ""))')

  jq -n \
    --arg flake "/home/${USERNAME}/nixos-config" \
    --arg hostName "$HOSTNAME" \
    --arg system "$SYSTEM" \
    --argjson roles "$rolesJson" \
    --arg hostKey "$HOST_KEY" \
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
      flake: $flake,
      host: { 
        name: $hostName, 
        system: $system, 
        roles: $roles, 
        publicKey: $hostKey
      },
      user: { 
        name: $userName, 
        email: $userEmail, 
        publicKey: $userKey
      },
      hardware: { 
        gpu: $gpu, 
        modules: $modules
      },
      locale:{ 
        timeZone: $tz, 
        default: $localeDefault, 
        extra: $localeExtra, 
        xkb = { 
          layout: $layout, 
          variant: $variant
        }
      },
    }' > "$FLAKE/hosts/$HOSTNAME/host.json"

  git -C "$FLAKE" add --intent-to-add "hosts/$HOSTNAME/host.json"

  logInfo "Wrote host file"
}

# ── hardware.nix ────────
writeHardwareNix() {
  local file="$FLAKE/hosts/$HOSTNAME/hardware.nix"

  if [[ $REMOTE == true ]]; then
    cat > "$file" <<'EOF'
    # Replaced during deploy by nixos-anywhere --generate-hardware-config.
    throw "hardware.nix has not been generated for this host yet"
EOF
    logInfo "Generated placeholder hardware configuration"
    logInfo "Check after installing if the correct configuration is present"
  else
    sudo nixos-generate-config --show-hardware-config --no-filesystems > "$file"
    logInfo "Generated hardware configuration"
  fi
  
  git -C "$FLAKE" add --intent-to-add "hosts/$HOSTNAME/hardware.nix"
}

# ── disko.nix ────────
writeDiskoNix() {
  local disko="$FLAKE/hosts/$HOSTNAME/disko.nix"

  cat > "$disko" <<EOF
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
              "/persist" = {
                mountpoint = "/persist";
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
  logInfo "Wrote disk layout"
}
  
# ── write dotfiles ────────
writeDotfiles() {
  local dest="$FLAKE/hosts/$HOSTNAME/home"

  mkdir -p "$dest"

  if [[ -z $DOTFILES ]]; then
    return 0
  fi

  if [[ $DOTFILES_METHOD == "path" ]]; then
    run cp -rT "$DOTFILES" "$dest"
  else
    run git clone --recurse-submodules --remote-submodules "$DOTFILES" "$TEMP_DIR/home" \
      || die "Failed to clone git repository"
    run cp -rT "$TEMP_DIR/home" "$dest"
  fi

  run find "$dest" -name .git -prune -exec rm -rf {} +
  rm -f "$dest/.gitmodules"

  git -C "$FLAKE" add --intent-to-add "hosts/$HOSTNAME/home"

  logInfo "Copied dotfiles"
}

# ── writing all host relevant files ────────
write() {
  formHeader "Writing files";
  
  mkdir -p "$FLAKE/hosts/$HOSTNAME"
  
  writeSopsYaml
  writeSecrets
  writeHostJson

  # An existing host keeps its hardware.nix, disko.nix, and dotfiles
  if [[ $EXISTING != true ]]; then
    writeHardwareNix
    writeDiskoNix
    writeDotfiles
  fi

  if formConfirm "Validate files?" "y"; then
    gum pager < "$FLAKE/.sops.yaml"
    gum pager < "$FLAKE/hosts/$HOSTNAME/secrets.json"
    gum pager < "$FLAKE/hosts/$HOSTNAME/host.json"
    gum pager < "$FLAKE/hosts/$HOSTNAME/hardware.nix"
    gum pager < "$FLAKE/hosts/$HOSTNAME/disko.nix"
    [[ -d "$FLAKE/hosts/$HOSTNAME/home" ]] && ls -la -R "$FLAKE/hosts/$HOSTNAME/home"

    while :; do
      if ! formConfirm "Everything fine?" "y"; then
        logWarn "Try fixing the file(s) manually and retry"
        logWarn "Or remove created files and rerun the installer"
        logInfo "If that doesnt fix it please create an issue/pr at https://github.com/KannyeEast/nixos-config"
        continue
      fi
      break
    done
  fi
}

# ── partition disk ────────
partition() {
  formHeader "Partitioning";
  
  if [[ $REMOTE == true ]]; then
    logInfo "Skipping disko. nixos-anywhere partitions the disk"
    return 0
  fi
    
  logWarn "$DISK will be erased"
  sudo disko --mode destroy,format,mount "$FLAKE/hosts/$HOSTNAME/disko.nix"
}

# ── install ────────
installSystem() {
  formHeader "Installing";
  formConfirm "Install now?" "y" || die "Skipped install"
  
  if [[ $REMOTE == true ]]; then
    installRemote
  else
    installLocal
  fi
}

# == install via nixos-install ==
installLocal() {
  # == move files to target ==
  sudo mkdir -p /mnt/tmp
  export TMPDIR=/mnt/tmp
  sudo systemctl set-environment TMPDIR=/mnt/tmp
  sudo systemctl restart nix-daemon

  stageFiles /mnt

  logWarn "First install can take a while"
  sudo nixos-install --root /mnt --flake "git+file://$FLAKE?submodules=1#$HOSTNAME" --no-root-passwd

  logInfo "Installed $HOSTNAME"
  formConfirm "Reboot now?" "y" || die "Reboot manually"
  sudo reboot
}

# == Install via nixos-anywhere ==
installRemote() {
  local stage="$TEMP_DIR/extra"
  local args=(
    --flake "git+file://$FLAKE?submodules=1#$HOSTNAME"
    --extra-files "$stage"
  )

  mkdir -p "$stage"
  stageFiles "$stage"

  # An existing host keeps its committed hardware.nix
  if [[ $EXISTING != true ]]; then
    args+=(--generate-hardware-config nixos-generate-config "$FLAKE/hosts/$HOSTNAME/hardware.nix")
  fi

  logWarn "First install can take a while"
  nix run nixpkgs#nixos-anywhere -- "${args[@]}" "$TARGET"
  
  verifyRemote
}

# == Everything the machine needs on disk before first boot ==
stageFiles() {
  local root="$1"
  local ssh="$root/persist/etc/ssh"
  local home="$root/persist/home/$USERNAME"
  
  local -a priv=()
  [[ $REMOTE == false ]] && priv=(sudo)
  
  # == host keys ==
  run "${priv[@]}" install -d -m 755 "$ssh"
  run "${priv[@]}" install -m 644 "$TEMP_DIR/ssh_host_ed25519_key.pub" "$ssh/ssh_host_ed25519_key.pub"
  run "${priv[@]}" install -m 600 "$TEMP_DIR/ssh_host_ed25519_key" "$ssh/ssh_host_ed25519_key"
  
  # == user home ==
  run "${priv[@]}" install -d -m 700 "$home/.ssh"
  run "${priv[@]}" install -m 644 "$TEMP_DIR/id_ed25519.pub" "$home/.ssh/id_ed25519.pub"
  run "${priv[@]}" install -m 600 "$TEMP_DIR/id_ed25519" "$home/.ssh/id_ed25519"
  run "${priv[@]}" cp -rT "$FLAKE" "$home/nixos-config"
}

# == verify the new system is reachable ==
verifyRemote() {
  local addr="${TARGET#*@}" ok=false i

  # Pin the key we generated, so this proves identity as well as reachability
  printf '%s %s\n' "$addr" "$HOST_KEY" > "$TEMP_DIR/known_hosts"

  logInfo "Waiting for $HOSTNAME to reboot"
  for (( i = 0; i < 60; i++ )); do
    if ssh -o StrictHostKeyChecking=yes -o ControlPath=none -o BatchMode=yes \
        "${SSH_OPTS[@]}" "$USERNAME@$addr" true 2>/dev/null; then
      ok=true
      break
    fi
    sleep 5
  done

  if [[ $ok == true ]]; then
    logInfo "Host key verified, logged in as $USERNAME"
  else
    logWarn "$HOSTNAME did not come back. Check the machine's console"
  fi

  {
    printf '%-10s %s\n' host "$HOSTNAME"
    printf '%-10s %s\n' ssh "ssh $USERNAME@$addr"
  } | gum style --border=rounded --padding="1 2" --margin="1 0"

  logWarn "Commit hosts/$HOSTNAME and rebuild, so this host key is trusted permanently"
  logWarn "If your known_hosts has the old key for $addr: ssh-keygen -R $addr"
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
  
  # Initialize existing submodules
  git -C "$FLAKE" submodule update --init --recursive

  # Temp directory for installer to use
  TEMP_DIR="$(TMPDIR=/tmp mktemp -d)"
  chmod 700 "$TEMP_DIR"
  
  [[ $REMOTE == false ]] && sudo -v
  sshInit

  gather
  generate
  write
  partition
  installSystem
}

main "$@"